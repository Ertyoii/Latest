//
//  AppStoreCheckerOperationTest.swift
//  Latest Tests
//
//  Created by ertyoii on 12.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-05-12.
//  Licensed under GPL-3.0; see LICENSE.md.

import XCTest

@testable import Latest

class AppStoreCheckerOperationTest: XCTestCase {

  func testNativeMacAppStoreAppsPreferDesktopLookupBeforeFallback() throws {
    XCTAssertEqual(
      AppStoreUpdateCheckerOperation.lookupEntityTypes(isIOSAppBundle: false),
      ["desktopSoftware", "macSoftware"])
  }

  func testWrappedIOSAppsSkipDesktopLookup() throws {
    XCTAssertEqual(
      AppStoreUpdateCheckerOperation.lookupEntityTypes(isIOSAppBundle: true), ["macSoftware"])
  }

  func testLookupBundleIdentifiersPreferExactIdentifierBeforeAliases() throws {
    XCTAssertEqual(
      AppStoreUpdateCheckerOperation.lookupBundleIdentifiers(for: "com.example.App"),
      ["com.example.App"]
    )
  }

  func testLookupBundleIdentifiersIncludeLegacyIWorkAliases() throws {
    XCTAssertEqual(
      AppStoreUpdateCheckerOperation.lookupBundleIdentifiers(for: "com.apple.iWork.Keynote"),
      ["com.apple.iWork.Keynote", "com.apple.Keynote"]
    )
    XCTAssertEqual(
      AppStoreUpdateCheckerOperation.lookupBundleIdentifiers(for: "com.apple.iWork.Numbers"),
      ["com.apple.iWork.Numbers", "com.apple.Numbers"]
    )
    XCTAssertEqual(
      AppStoreUpdateCheckerOperation.lookupBundleIdentifiers(for: "com.apple.iWork.Pages"),
      ["com.apple.iWork.Pages", "com.apple.Pages"]
    )
  }

  func testReceiptURLFallsBackToStandardMacAppReceiptLocation() throws {
    let appURL = temporaryAppURL()
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

    XCTAssertEqual(
      AppStoreReceipt.url(forAppAt: appURL),
      appURL.appendingPathComponent("Contents/_MASReceipt/receipt", isDirectory: false)
    )
  }

  func testCanPerformUpdateCheckRequiresExistingReceipt() throws {
    let appURL = temporaryAppURL()
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

    XCTAssertFalse(AppStoreUpdateCheckerOperation.canPerformUpdateCheck(forAppAt: appURL))
  }

  func testCanPerformUpdateCheckFindsStandardMacAppReceipt() throws {
    let appURL = temporaryAppURL()
    let receiptURL = AppStoreReceipt.standardReceiptURL(forAppAt: appURL)
    try writeReceipt(at: receiptURL)

    XCTAssertTrue(AppStoreUpdateCheckerOperation.canPerformUpdateCheck(forAppAt: appURL))
    XCTAssertFalse(AppStoreUpdateCheckerOperation.isIOSAppBundle(at: appURL))
  }

  func testReceiptURLFindsExistingWrappedIOSReceipt() throws {
    let appURL = temporaryAppURL()
    let receiptURL = appURL.appendingPathComponent(
      "Contents/Wrapper/WrappedBundle.app/_MASReceipt/receipt", isDirectory: false)
    try writeReceipt(at: receiptURL)

    XCTAssertEqual(
      AppStoreReceipt.url(forAppAt: appURL)?.resolvingSymlinksInPath(),
      receiptURL.resolvingSymlinksInPath()
    )
    XCTAssertTrue(AppStoreUpdateCheckerOperation.canPerformUpdateCheck(forAppAt: appURL))
    XCTAssertTrue(AppStoreUpdateCheckerOperation.isIOSAppBundle(at: appURL))
  }

  func testStandardReceiptTakesPriorityOverWrappedReceipt() throws {
    let appURL = temporaryAppURL()
    let standardReceiptURL = AppStoreReceipt.standardReceiptURL(forAppAt: appURL)
    let wrappedReceiptURL = appURL.appendingPathComponent(
      "Contents/Wrapper/WrappedBundle.app/_MASReceipt/receipt", isDirectory: false)
    try writeReceipt(at: standardReceiptURL)
    try writeReceipt(at: wrappedReceiptURL)

    XCTAssertEqual(
      AppStoreReceipt.url(forAppAt: appURL)?.resolvingSymlinksInPath(),
      standardReceiptURL.resolvingSymlinksInPath()
    )
    XCTAssertFalse(AppStoreUpdateCheckerOperation.isIOSAppBundle(at: appURL))
  }

  func testInstallationReplyGateResumesContinuationOnlyOnce() async throws {
    let expected = URL(fileURLWithPath: "/Applications/Updated.app")
    let installed = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<URL, Error>) in
      let replyGate = InstallationReplyGate(continuation: continuation)
      replyGate.resume(with: .success(expected))
      replyGate.resume(with: .failure(LatestError.installHelperCommunicationFailed))
    }
    XCTAssertEqual(installed, expected)
  }

  func testDownloadedArtifactsSurviveRemovalAndRefreshWhenInodeChanges() throws {
    let folder = temporaryAppURL().deletingPathExtension()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let package = folder.appendingPathComponent("update.pkg")
    let receipt = folder.appendingPathComponent("receipt")
    try Data("partial".utf8).write(to: package)
    try Data("receipt-1".utf8).write(to: receipt)
    var artifacts = AppStoreDownloadArtifacts()
    defer {
      artifacts.removeAll()
      try? FileManager.default.removeItem(at: folder)
    }
    try artifacts.refresh(in: folder)
    let oldLink = try XCTUnwrap(artifacts.packageURL)
    // App Store atomically replaces a partial package and receipt.
    try Data("complete".utf8).write(to: package, options: .atomic)
    try Data("receipt-2".utf8).write(to: receipt, options: .atomic)
    try artifacts.refresh(in: folder)
    XCTAssertNotEqual(artifacts.packageURL, oldLink)
    try FileManager.default.removeItem(at: folder)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(artifacts.packageURL)), Data("complete".utf8))
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(artifacts.receiptURL)), Data("receipt-2".utf8))
  }

  func testManualInstallRepairsOnlyPackageKitEntitlementFailure() {
    XCTAssertTrue(
      AppStoreDownloadArtifacts.requiresPackageInstallation(
        NSError(domain: "PKInstallErrorDomain", code: 201)))
    XCTAssertTrue(
      AppStoreDownloadArtifacts.requiresPackageInstallation(
        NSError(
          domain: "wrapper", code: 1,
          userInfo: [
            NSUnderlyingErrorKey:
              NSError(domain: "PKInstallErrorDomain", code: 201)
          ])))
    XCTAssertFalse(
      AppStoreDownloadArtifacts.requiresPackageInstallation(
        NSError(domain: "PKInstallErrorDomain", code: 202)))
    XCTAssertFalse(
      AppStoreDownloadArtifacts.requiresPackageInstallation(
        NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
  }

  func testPackageKitRestrictionUsesHelperEvenWhenAppleMarksDownloadCancelled() {
    let error = NSError(domain: "PKInstallErrorDomain", code: 201)
    let result = AppStoreDownloadResult(
      failed: true, cancelled: true, error: error, wasCancelled: false)
    guard case .installPackage = result else {
      return XCTFail("Apple's cancellation flag must not skip the PackageKit workaround")
    }
    let userCancelled = AppStoreDownloadResult(
      failed: true, cancelled: true, error: error, wasCancelled: true)
    guard case .failed(let failure) = userCancelled else {
      return XCTFail("Cancelling in Latest must prevent installation")
    }
    XCTAssertTrue(failure is CancellationError)
  }

  func testDownloadRemovalDoesNotHideErrorsOrReportCancellationAsSuccess() {
    let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
    let errored = AppStoreDownloadResult(
      failed: false, cancelled: false, error: error, wasCancelled: false)
    guard case .failed(let failure) = errored else {
      return XCTFail("An error must take priority over Apple's failure flag")
    }
    XCTAssertEqual(failure as NSError, error)
    let cancelled = AppStoreDownloadResult(
      failed: false, cancelled: true, error: nil, wasCancelled: false)
    guard case .failed(let cancellation) = cancelled else {
      return XCTFail("A cancelled download must not report success")
    }
    XCTAssertTrue(cancellation is CancellationError)
  }

  func testRefreshDiscoversMacUpdateDespiteStaleHTTPCaches() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AppStoreLookupURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let app = App.Bundle(
      version: Version(versionNumber: "7.67", buildNumber: "1.472078.10"),
      name: "Amazon Kindle", bundleIdentifier: "com.example.Kindle.\(UUID().uuidString)",
      fileURL: temporaryAppURL(), source: .appStore)
    let checker = AppStoreUpdateCheckerOperation(with: app, session: session)

    let update = try await checker.check()
    XCTAssertEqual(update.remoteVersion.versionNumber, "7.68")
    XCTAssertTrue(update.updateAvailable, "The available Mac release must appear as an update")
    XCTAssertEqual(update.minimumOSVersion?.majorVersion, 14)
    XCTAssertEqual(update.date, ISO8601DateFormatter().date(from: "2026-10-02T03:19:36Z"))
    guard case .html(let notes) = update.releaseNotes else {
      return XCTFail("The App Store response should retain its release notes")
    }
    XCTAssertEqual(notes, "- Fixed launch.\n- Improved sync.\nThanks for updating.")

    // An explicit refresh must fetch current metadata again, beyond the actor cache.
    await AppStoreUpdateCheckerOperation.invalidateLookupCache()
    let refreshed = try await checker.check()
    XCTAssertTrue(refreshed.updateAvailable)
    XCTAssertEqual(refreshed.remoteVersion.versionNumber, "7.68")
  }

  private func temporaryAppURL() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathExtension("app")
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }

  private func writeReceipt(at url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: url)
  }

}

/// Models two independent stale layers: a URL-keyed CDN and URLSession's HTTP cache.
private final class AppStoreLookupURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let url = request.url!
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    let hasFreshURL = items.contains { $0.name == "t" && $0.value?.isEmpty == false }
    let bypassesLocalCache = request.cachePolicy == .reloadIgnoringLocalCacheData
    let fresh = hasFreshURL && bypassesLocalCache
    let entity = items.first { $0.name == "entity" }?.value
    // A newer iOS version must never replace a valid native Mac response.
    let version = entity == "desktopSoftware" ? (fresh ? "7.68" : "7.67") : "7.68.1"
    let body = """
      {"results":[{"version":"\(version)","minimumOsVersion":"14.0",
      "releaseNotes":"- Fixed launch.<br>- Improved sync.<br />Thanks for updating.",
      "currentVersionReleaseDate":"2026-10-02T03:19:36Z",
      "trackViewUrl":"https://apps.apple.com/us/app/id302584613","trackId":302584613}]}
      """
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
      cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
