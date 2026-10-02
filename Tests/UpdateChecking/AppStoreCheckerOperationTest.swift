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

  func testInstallationReplyGateTimesOutWhenHelperNeverReplies() async {
    do {
      let _: URL = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<URL, Error>) in
        let replyGate = InstallationReplyGate(continuation: continuation)
        replyGate.scheduleTimeout(after: .milliseconds(10))
      }
      XCTFail("Expected the helper reply gate to time out")
    } catch {
      guard case LatestError.installHelperCommunicationFailed = error else {
        return XCTFail("Expected helper communication timeout, got \(error)")
      }
    }
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
