// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import XCTest

@testable import Latest

final class InstallHelperTest: XCTestCase {
  @MainActor
  func testHelperRegistrationResumesPendingUpdateAfterApprovalOnlyOnce() async throws {
    let stored = AppStoreUpdateSettings.alwaysPerformManualUpdates.active
    AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
    defer { AppStoreUpdateSettings.alwaysPerformManualUpdates.active = stored }
    let helper = HelperRegistrationFixture()
    let presenter = UpdateInstallHelperAlert(helper: helper)
    var resumed = 0
    presenter.present(.installHelperNotRegistered, fallbackURL: URL(string: "https://example.com")!)
    { resumed += 1 }
    presenter.enableHelper()
    try await waitForHelper { !presenter.isChecking }
    XCTAssertEqual(helper.registrations, 1)
    XCTAssertEqual(resumed, 0)
    helper.enabled = true
    presenter.resumeIfAvailable()
    presenter.resumeIfAvailable()
    try await waitForHelper { !presenter.isChecking }
    XCTAssertEqual(resumed, 1)
    XCTAssertFalse(presenter.isPresented)
  }

  @MainActor
  func testHelperRegistrationFailureIsVisibleAndCancelDoesNotRetry() async throws {
    let stored = AppStoreUpdateSettings.alwaysPerformManualUpdates.active
    AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
    defer { AppStoreUpdateSettings.alwaysPerformManualUpdates.active = stored }
    let helper = HelperRegistrationFixture()
    helper.failure = NSError(
      domain: "registration", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Signing does not match"])
    let presenter = UpdateInstallHelperAlert(helper: helper)
    var resumed = false
    presenter.present(.installHelperNotRegistered, fallbackURL: URL(string: "https://example.com")!)
    { resumed = true }
    presenter.enableHelper()
    try await waitForHelper { !presenter.isChecking }
    XCTAssertTrue(presenter.isPresented)
    XCTAssertTrue(
      presenter.registrationError?.localizedDescription.contains("Signing does not match") == true)
    presenter.cancel()
    helper.enabled = true
    presenter.resumeIfAvailable()
    XCTAssertFalse(resumed)
  }
  @MainActor
  func testFailedReadinessBlocksWholeBatchAndRetryStartsEachUpdateOnce() async throws {
    let helper = HelperRegistrationFixture()
    helper.enabled = true
    helper.readinessFailure = InstallHelperError.unavailable("Connection rejected")
    let presenter = UpdateInstallHelperAlert(helper: helper)
    var downloads: [Int] = []
    let url = URL(string: "macappstore://apps.apple.com/updates")!
    presenter.prepare(fallbackURL: url) { downloads.append(1) }
    presenter.prepare(fallbackURL: url) { downloads.append(2) }
    try await waitForHelper { !presenter.isChecking }
    XCTAssertTrue(downloads.isEmpty)
    XCTAssertTrue(presenter.isPresented)
    XCTAssertEqual(presenter.primaryTitle, "Check Again")
    helper.readinessFailure = nil
    presenter.enableHelper()
    try await waitForHelper { !presenter.isChecking }
    XCTAssertEqual(downloads, [1, 2])
    presenter.resumeIfAvailable()
    XCTAssertEqual(downloads, [1, 2])
  }

  @MainActor
  func testCancelAndAppStoreFallbackDiscardLateSuccessfulReadiness() async throws {
    for opensStore in [false, true] {
      let helper = HelperRegistrationFixture()
      helper.enabled = true
      helper.suspendsCheck = true
      let workspace = StubApplicationWorkspace()
      let presenter = UpdateInstallHelperAlert(helper: helper, workspace: workspace)
      let url = URL(string: "macappstore://apps.apple.com/updates")!
      var downloads = 0
      presenter.prepare(fallbackURL: url) { downloads += 1 }
      try await waitForHelper { helper.pendingCheck != nil }
      if opensStore { presenter.openAppStore() } else { presenter.cancel() }
      helper.pendingCheck?.resume()
      try await Task.sleep(for: .milliseconds(30))
      XCTAssertEqual(downloads, 0)
      XCTAssertFalse(presenter.isPresented)
      XCTAssertEqual(workspace.openedURLs, opensStore ? [url] : [])
    }
  }

  func testReadinessRepairsStaleDaemonAndChecksAgainForNextBatch() async throws {
    let backend = ReadinessFixture(probes: [
      .success(Data([0])), .success(Data([1])), .success(Data([1])),
    ])
    let readiness = InstallHelperReadiness(backend: backend)
    try await readiness.prepare()
    try await readiness.prepare()
    let events = await backend.events
    XCTAssertEqual(events, ["verify", "probe", "refresh", "probe", "verify", "probe"])
  }

  func testFailedPrerequisiteDoesNotContactOrRefreshDaemon() async {
    let backend = ReadinessFixture(probes: [])
    await backend.failVerification()
    do {
      try await InstallHelperReadiness(backend: backend).prepare()
      XCTFail("Must stop before download")
    } catch { XCTAssertEqual(error as? InstallHelperError, .installHelperRequiresApproval) }
    let events = await backend.events
    XCTAssertEqual(events, ["verify"])
  }

  func testUnreachableHelperStopsBeforeInstallationAfterOneRepair() async {
    let backend = ReadinessFixture(
      probes: Array(repeating: .failure(CocoaError(.xpcConnectionInvalid)), count: 4))
    let readiness = InstallHelperReadiness(backend: backend)
    do {
      _ = try await readiness.install {
        XCTFail("Must not install")
        return URL(fileURLWithPath: "/unused")
      }
      XCTFail("Unreachable helper must fail")
    } catch {}
    let events = await backend.events
    XCTAssertEqual(events.filter { $0 == "refresh" }.count, 1)
    XCTAssertEqual(events.filter { $0 == "probe" }.count, 4)
  }

  func testReadinessFailureDoesNotRestartAnActiveInstallation() async throws {
    let backend = ReadinessFixture(probes: [
      .success(Data([1])), .failure(CocoaError(.xpcConnectionInvalid)),
    ])
    let readiness = InstallHelperReadiness(backend: backend)
    let started = expectation(description: "Installation dispatched")
    let (release, continuation) = AsyncStream<Void>.makeStream()
    let installation = Task {
      try await readiness.install {
        started.fulfill()
        for await _ in release { break }
        return URL(fileURLWithPath: "/installed.app")
      }
    }
    await fulfillment(of: [started], timeout: 2)
    do {
      try await readiness.prepare()
      XCTFail("Broken helper must not admit another download")
    } catch { XCTAssertTrue(error.localizedDescription.contains("installation")) }
    let events = await backend.events
    XCTAssertFalse(events.contains("refresh"))
    continuation.yield(())
    continuation.finish()
    _ = try await installation.value
  }

  func testConcurrentReadinessChecksShareOnlyTheInFlightProbe() async throws {
    let backend = ReadinessFixture(probes: [.success(Data([1])), .success(Data([1]))])
    await backend.suspendFirstProbe()
    let readiness = InstallHelperReadiness(backend: backend)
    let first = Task { try await readiness.prepare() }
    for _ in 0..<100 {
      if await backend.isProbing { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let second = Task { try await readiness.prepare() }
    try await Task.sleep(for: .milliseconds(30))
    await backend.releaseProbe()
    try await first.value
    try await second.value
    try await readiness.prepare()
    let events = await backend.events
    XCTAssertEqual(events, ["verify", "probe", "verify", "probe"])
  }

  func testLostInstallationReplyPreventsBlindRefreshUntilLiveIdleResponse() async throws {
    let backend = ReadinessFixture(probes: [
      .success(Data([1])), .failure(CocoaError(.xpcConnectionInvalid)), .success(Data([1])),
    ])
    let readiness = InstallHelperReadiness(backend: backend)
    do {
      _ = try await readiness.install { throw CocoaError(.xpcConnectionInterrupted) }
      XCTFail("Installation reply must fail")
    } catch {}
    do {
      try await readiness.prepare()
      XCTFail("Unknown installation outcome must block repair")
    } catch { XCTAssertTrue(error.localizedDescription.contains("unknown")) }
    try await readiness.prepare()
    let events = await backend.events
    XCTAssertFalse(events.contains("refresh"))
  }

  func testCancellationDuringReadinessNeverDispatchesInstallation() async throws {
    let backend = ReadinessFixture(probes: [.success(Data([1]))])
    await backend.suspendFirstProbe()
    let readiness = InstallHelperReadiness(backend: backend)
    let installation = Task {
      try await readiness.install {
        XCTFail("Cancelled caller must not install")
        return URL(fileURLWithPath: "/unused")
      }
    }
    for _ in 0..<100 {
      if await backend.isProbing { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    installation.cancel()
    await backend.releaseProbe()
    do {
      _ = try await installation.value
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
  }

}

@MainActor
final class HelperRegistrationFixture: InstallHelperServicing {
  var enabled = false
  var failure: Error?
  private(set) var registrations = 0
  func verifyAvailability() throws {
    if !enabled { throw InstallHelperError.installHelperRequiresApproval }
  }
  var pendingCheck: CheckedContinuation<Void, Error>?
  var suspendsCheck = false
  var readinessFailure: Error?
  func prepareForUpdates() async throws {
    if suspendsCheck {
      try await withCheckedThrowingContinuation { pendingCheck = $0 }
    }
    if let readinessFailure { throw readinessFailure }
    try verifyAvailability()
  }
  func register() throws {
    registrations += 1
    if let failure { throw failure }
  }
}

@MainActor
func waitForHelper(_ condition: () -> Bool) async throws {
  for _ in 0..<200 {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  XCTFail("Helper state did not settle")
  throw CocoaError(.userCancelled)
}

private actor ReadinessFixture: InstallHelperReadinessBackend {
  var events: [String] = []
  var probes: [Result<Data, Error>]
  var verificationFails = false
  var isProbing = false
  private var suspended = false
  private var probeContinuation: CheckedContinuation<Void, Never>?
  func suspendFirstProbe() { suspended = true }
  func releaseProbe() {
    probeContinuation?.resume()
    probeContinuation = nil
  }

  init(probes: [Result<Data, Error>]) { self.probes = probes }
  func failVerification() { verificationFails = true }
  func verify() throws -> Data {
    events.append("verify")
    if verificationFails { throw InstallHelperError.installHelperRequiresApproval }
    return Data([1])
  }
  func probe() async throws -> InstallHelperHealth {
    events.append("probe")
    if suspended {
      suspended = false
      isProbing = true
      await withCheckedContinuation { probeContinuation = $0 }
    }
    guard !probes.isEmpty else { throw CocoaError(.xpcConnectionInvalid) }
    return InstallHelperHealth(signature: try probes.removeFirst().get(), isInstalling: false)
  }
  func refresh() { events.append("refresh") }
}
