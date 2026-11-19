//
//  AppStoreCheckerOperationTest.swift
//  Latest Tests
//
//  Created by ertyoii on 12.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-05-12.
//  Licensed under GPL-3.0; see LICENSE.md.

import CommerceKit
import StoreFoundation
import Synchronization
import XCTest

@testable import Latest

class AppStoreCheckerOperationTest: XCTestCase {
  @MainActor
  func testDownloadObserverRegistrationReturnsRemovableStringToken() {
    let observer = PassiveAppStoreDownloadObserver()
    let queue = CKDownloadQueue.shared()
    let token: String = queue.add(observer)
    defer { queue.removeObserver(token) }
    XCTAssertFalse(token.isEmpty)
  }

  @MainActor
  func testMissingPurchaseResponseSurvivesSwiftAsyncImport() async throws {
    let purchase = SSPurchase(buyParameters: "")
    let (_, completed, response) = try await EmptyAppStorePurchaseController().perform(
      purchase, withOptions: 0)
    XCTAssertFalse(completed)
    XCTAssertNil(response, "A missing callback response must not be force-unwrapped by Swift")
  }

  func testDownloadFieldsCanBeAbsentBeforeProgressStarts() {
    let download = SSDownload()
    download.metadata = nil
    download.status = nil
    XCTAssertNil(download.metadata)
    XCTAssertNil(download.status)

    let status = SSDownloadStatus()
    status.error = nil
    XCTAssertNil(status.error)
    XCTAssertNil(status.activePhase)

    let response = SSPurchaseResponse()
    response.downloads = nil
    XCTAssertNil(response.downloads)

    let metadata = SSDownloadMetadata(kind: "software")
    XCTAssertEqual(metadata.kind, "software")
  }

  @MainActor
  func testNativeActionKeepsItsCapabilityWhenCheckedUnderManualPreference() async throws {
    let defaults = UserDefaults.standard
    let previousArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
    defer { defaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
    var arguments = previousArguments
    arguments[AppStoreUpdateSettings.alwaysPerformManualUpdates.rawValue] = true
    // Override only this test host's volatile domain; never persist the user's preference.
    defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    XCTAssertTrue(AppStoreUpdateSettings.alwaysPerformManualUpdates.active)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AppStoreLookupURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let app = App.Bundle(
      version: Version(versionNumber: "1", buildNumber: nil), name: "Native",
      bundleIdentifier: "com.example.native.\(UUID())", fileURL: temporaryAppURL(),
      source: .appStore)
    let update = try await AppStoreUpdateCheckerOperation(with: app, session: session).check()
    guard case .builtIn = update.updateAction else {
      return XCTFail(
        "A native app must retain its update capability when manual mode later changes")
    }
    let wrappedURL = temporaryAppURL()
    try writeReceipt(
      at: wrappedURL.appendingPathComponent("Contents/Wrapper/Wrapper.app/_MASReceipt/receipt"))
    let wrapped = App.Bundle(
      version: app.version, name: "Wrapped", bundleIdentifier: "com.example.wrapped.\(UUID())",
      fileURL: wrappedURL, source: .appStore)
    let wrappedUpdate = try await AppStoreUpdateCheckerOperation(with: wrapped, session: session)
      .check()
    guard case .external = wrappedUpdate.updateAction else {
      return XCTFail("Wrapped iOS apps must keep their external-only capability")
    }
  }

  @MainActor
  func testNativeUpdateClickImmediatelyQueuesOnceWithoutOpeningSetup() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AppStoreLookupURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let bundle = App.Bundle(
      version: Version(versionNumber: "1", buildNumber: nil), name: "Native",
      bundleIdentifier: "com.example.store.\(UUID())", fileURL: temporaryAppURL(), source: .appStore
    )
    let update = try await AppStoreUpdateCheckerOperation(with: bundle, session: session).check()
    let app = App(bundle: bundle, update: .success(update), isIgnored: false)
    let queue = UpdateQueue.shared
    let suspended = queue.isSuspended
    let manual = AppStoreUpdateSettings.alwaysPerformManualUpdates.active
    queue.isSuspended = true
    AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
    defer {
      queue.cancelUpdate(for: bundle.identifier)
      queue.isSuspended = suspended
      AppStoreUpdateSettings.alwaysPerformManualUpdates.active = manual
    }
    let service = AppUpdateService(queue: queue)
    service.update(app)
    service.update(app)
    XCTAssertTrue(service.isUpdating(app))
    XCTAssertEqual(
      queue.operations.compactMap { $0 as? AppStoreUpdateOperation }
        .filter { $0.appIdentifier == bundle.identifier }.count, 1)
    XCTAssertFalse(UpdateInstallHelperAlert.shared.isPresented)
  }

  func testTransportCancellationDoesNotTryAnotherEntity() async throws {
    let (checker, session, control, identifier) = controlledLookup(failure: .cancelled)
    defer {
      session.invalidateAndCancel()
      ControlledAppStoreURLProtocol.controls.withLock { $0[identifier] = nil }
    }
    do {
      _ = try await checker.check()
      XCTFail("A cancelled transport must fail")
    } catch {
      XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
    }
    XCTAssertEqual(control.requestCount, 1)
  }

  func testTimeoutStopsAfterOneRequestWhileMissingResultsTryTheNextEntity() async throws {
    let outcomes: [(URLError.Code?, Int)] = [(.timedOut, 200), (nil, 200), (nil, 404)]
    for (failure, firstStatusCode) in outcomes {
      let (checker, session, control, identifier) = controlledLookup(
        failure: failure, firstEmptyStatus: firstStatusCode)
      defer {
        session.invalidateAndCancel()
        ControlledAppStoreURLProtocol.controls.withLock { $0[identifier] = nil }
      }
      if let failure {
        do {
          _ = try await checker.check()
          XCTFail("Expected a transport error")
        } catch {
          XCTAssertEqual((error as? URLError)?.code, failure)
        }
        XCTAssertEqual(control.requestCount, 1)
      } else {
        let update = try await checker.check()
        XCTAssertEqual(update.remoteVersion.versionNumber, "2.0")
        XCTAssertEqual(control.requestCount, 2)
      }
    }
  }

  func testCancelledLookupReaderStopsWhileSharedFetchContinues() async throws {
    let (checker, session, control, identifier) = controlledLookup()
    defer {
      session.invalidateAndCancel()
      ControlledAppStoreURLProtocol.controls.withLock { $0[identifier] = nil }
    }
    let stopped = expectation(description: "Cancelled reader stopped before transport completed")
    let reader = Task {
      let result: Result<App.Update, Error>
      do { result = .success(try await checker.check()) } catch { result = .failure(error) }
      stopped.fulfill()
      return result
    }
    await fulfillment(of: [control.started], timeout: 2)
    reader.cancel()
    await fulfillment(of: [stopped], timeout: 0.5)
    let otherReader = Task { try await checker.check() }
    let request = try XCTUnwrap(control.firstRequest)
    request.complete()
    let cancelled = await reader.value
    guard case .failure(let error) = cancelled else {
      return XCTFail("Cancelled lookup returned an update")
    }
    XCTAssertTrue(error is CancellationError)
    let update = try await otherReader.value
    XCTAssertEqual(update.remoteVersion.versionNumber, "2.0")
    XCTAssertEqual(control.requestCount, 1, "Readers must share the unfinished fetch")
  }

  private func controlledLookup(
    failure: URLError.Code? = nil, firstEmptyStatus: Int? = nil
  ) -> (
    AppStoreUpdateCheckerOperation, URLSession, ControlledAppStoreURLProtocol.Control, String
  ) {
    let identifier = "com.example.lookup.\(UUID())"
    let control = ControlledAppStoreURLProtocol.Control(
      failure: failure, firstEmptyStatus: firstEmptyStatus)
    ControlledAppStoreURLProtocol.controls.withLock { $0[identifier] = control }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ControlledAppStoreURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let app = App.Bundle(
      version: Version(versionNumber: "1.0", buildNumber: nil), name: "Lookup",
      bundleIdentifier: identifier, fileURL: temporaryAppURL(), source: .appStore)
    return (
      AppStoreUpdateCheckerOperation(with: app, session: session), session, control, identifier
    )
  }

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

  @MainActor
  func testDownloadCanBeDeletedBeforeMainActorHandlesRemoval() async throws {
    try XCTSkipUnless(AppStoreUpdateOperation.requiresManualInstallation)
    let directory = temporaryAppURL()
    let folder = directory.appendingPathComponent("123")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let payload = Data("finished package".utf8)
    let receipt = Data("finished receipt".utf8)
    try payload.write(to: folder.appendingPathComponent("update.pkg"))
    try receipt.write(to: folder.appendingPathComponent("receipt"))
    let app = makeTestApp(name: "Store fixture", version: "1", remoteVersion: "2")
    let installations = Mutex(0)
    let op = AppStoreUpdateOperation(
      app: app.bundle, itemIdentifier: 123, pageURL: AppStoreUpdateSettings.updatesPage,
      downloadDirectory: directory
    ) { package, url, data in
      XCTAssertEqual(try package.readToEnd(), payload)
      XCTAssertEqual(url, app.fileURL)
      XCTAssertEqual(data, receipt)
      installations.withLock { $0 += 1 }
    }
    let download = SSDownload()
    let metadata = SSDownloadMetadata(kind: "software")
    metadata.itemIdentifier = 123
    download.metadata = metadata
    let status = SSDownloadStatus()
    download.status = status
    let queue = CKDownloadQueue.shared()
    op.downloadQueue(queue, statusChangedFor: download)
    try FileManager.default.removeItem(at: folder)
    status.error = NSError(domain: "PKInstallErrorDomain", code: 201)
    status.isCancelled = true
    op.downloadQueue(queue, changedWithRemoval: download)
    try await waitForHelper { op.isFinished }
    XCTAssertNil(op.error)
    XCTAssertEqual(installations.withLock { $0 }, 1)
  }

  func testDownloadedArtifactsSurviveRemovalAndRefreshWhenInodeChanges() throws {
    let folder = temporaryAppURL().deletingPathExtension()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let package = folder.appendingPathComponent("update.pkg")
    let receipt = folder.appendingPathComponent("receipt")
    try Data("partial".utf8).write(to: package)
    try Data("receipt-1".utf8).write(to: receipt)
    let artifacts = AppStoreDownloadArtifacts()
    defer { try? FileManager.default.removeItem(at: folder) }
    artifacts.capture(in: folder)
    // The store replaces partial files, then removes its folder before the UI can run.
    try Data("complete".utf8).write(to: package, options: .atomic)
    try Data("receipt-2".utf8).write(to: receipt, options: .atomic)
    artifacts.capture(in: folder)
    try FileManager.default.removeItem(at: folder)
    artifacts.capture(in: folder)
    let files = try XCTUnwrap(artifacts.take())
    XCTAssertEqual(try files.package?.readToEnd(), Data("complete".utf8))
    XCTAssertEqual(files.receiptData, Data("receipt-2".utf8))
    artifacts.capture(in: folder)
    XCTAssertNil(artifacts.take(), "Late callbacks cannot reopen a finished download")

  }

  func testReportedPackageAndEarlyMetadataReceiptSurviveStoreCleanup() throws {
    let root = temporaryAppURL()
    let cache = root.appendingPathComponent("com.apple.appstore")
    let legacyFolder = cache.appendingPathComponent("123")
    let directory = root.appendingPathComponent("com.apple.appstoreagent/com.apple.appstore")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let package = directory.appendingPathComponent("download.pkg")
    let payload = Data("complete local asset".utf8)
    let receipt = Data("receipt from an earlier callback".utf8)
    try payload.write(to: package)
    let artifacts = AppStoreDownloadArtifacts()
    artifacts.capture(in: legacyFolder, assetPaths: [package.path], receiptData: receipt)
    try FileManager.default.removeItem(at: directory)
    artifacts.capture(in: legacyFolder, assetPaths: [package.path], receiptData: Data())
    let files = try XCTUnwrap(artifacts.take())
    XCTAssertEqual(try files.package?.readToEnd(), payload)
    XCTAssertEqual(files.receiptData, receipt)
  }

  func testReportedPackageFromAnotherItemOrOutsideTheStoreCacheIsIgnored() throws {
    let root = temporaryAppURL()
    let cache = root.appendingPathComponent("com.apple.appstore")
    for directory in [
      cache.appendingPathComponent("456"), root.appendingPathComponent("elsewhere/123"),
    ] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let package = directory.appendingPathComponent("update.pkg")
      try Data("unrelated".utf8).write(to: package)
      let artifacts = AppStoreDownloadArtifacts()
      artifacts.capture(in: cache.appendingPathComponent("123"), assetPaths: [package.path])
      XCTAssertNil(artifacts.take()?.package)
    }
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

  @MainActor
  func testOnlyStoreInitiatedCancellationOffersRecovery() async throws {
    let app = makeTestApp(name: "Cancel fixture", version: "1", remoteVersion: "2")
    let url = URL(string: "macappstore://apps.apple.com/app/id123")!
    for userCancelled in [false, true] {
      let operation = AppStoreUpdateOperation(app: app.bundle, itemIdentifier: 123, pageURL: url)
      if userCancelled { operation.cancel() }
      operation.finish(with: CancellationError())
      try await waitForHelper { operation.isFinished }
      if userCancelled {
        XCTAssertNil(operation.error)
      } else {
        let failure = try XCTUnwrap(operation.error as? AppStoreUpdateFailure)
        XCTAssertEqual(failure.pageURL, url)
        XCTAssertEqual(failure.explanation, "The App Store cancelled the download.")
      }
    }
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

/// Observe the real queue without initiating or changing a download.
private final class PassiveAppStoreDownloadObserver: NSObject, CKDownloadQueueObserver {
  func downloadQueue(_ queue: CKDownloadQueue, changedWithAddition download: SSDownload) {}
  func downloadQueue(_ queue: CKDownloadQueue, changedWithRemoval download: SSDownload) {}
  func downloadQueue(_ queue: CKDownloadQueue, statusChangedFor download: SSDownload) {}
}

/// Exercise the Clang callback-to-async bridge without contacting the App Store.
private final class EmptyAppStorePurchaseController: CKPurchaseController {
  override func perform(
    _ purchase: SSPurchase, withOptions options: UInt64,
    completionHandler: SSPurchaseCompletion?
  ) {
    completionHandler?(purchase, false, nil, nil)
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

private final class ControlledAppStoreURLProtocol: URLProtocol, @unchecked Sendable {
  final class Control: @unchecked Sendable {
    let started = XCTestExpectation(description: "Transport started")
    private let lock = NSLock()
    private var requests = [ControlledAppStoreURLProtocol]()
    var requestCount: Int { lock.withLock { requests.count } }
    var firstRequest: ControlledAppStoreURLProtocol? { lock.withLock { requests.first } }
    func record(_ request: ControlledAppStoreURLProtocol) -> Bool {
      lock.withLock {
        requests.append(request)
        return requests.count == 1
      }
    }
    let failure: URLError.Code?
    let firstEmptyStatus: Int?
    init(failure: URLError.Code?, firstEmptyStatus: Int?) {
      self.failure = failure
      self.firstEmptyStatus = firstEmptyStatus
    }
  }
  static let controls = Mutex<[String: Control]>([:])
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let identifier =
      URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first {
        $0.name == "bundleId"
      }?.value ?? ""
    guard let control = Self.controls.withLock({ $0[identifier] }) else { return }
    let isFirst = control.record(self)
    if isFirst { control.started.fulfill() }
    if let failure = control.failure {
      client?.urlProtocol(self, didFailWithError: URLError(failure))
    } else if let firstEmptyStatus = control.firstEmptyStatus {
      complete(empty: isFirst, statusCode: isFirst ? firstEmptyStatus : 200)
    }
  }
  func complete(empty: Bool = false, statusCode: Int = 200) {
    let body =
      empty
      ? #"{"results":[]}"#
      : #"{"results":[{"version":"2.0","minimumOsVersion":"14.0","trackViewUrl":"https://apps.apple.com/app/id123","trackId":123}]}"#
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!,
      cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
