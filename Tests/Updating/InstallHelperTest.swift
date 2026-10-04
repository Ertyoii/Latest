// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import XCTest

@testable import Latest

final class InstallHelperTest: XCTestCase {
  @MainActor
  func testHelperRegistrationResumesPendingUpdateAfterApprovalOnlyOnce() {
    let stored = AppStoreUpdateSettings.alwaysPerformManualUpdates.active
    AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
    defer { AppStoreUpdateSettings.alwaysPerformManualUpdates.active = stored }
    let helper = HelperRegistrationFixture()
    let presenter = UpdateInstallHelperAlert(helper: helper)
    var resumed = 0
    presenter.present(.installHelperNotRegistered, fallbackURL: URL(string: "https://example.com")!)
    { resumed += 1 }
    presenter.enableHelper()
    XCTAssertEqual(helper.registrations, 1)
    XCTAssertEqual(resumed, 0)
    helper.enabled = true
    presenter.resumeIfAvailable()
    presenter.resumeIfAvailable()
    XCTAssertEqual(resumed, 1)
    XCTAssertFalse(presenter.isPresented)
  }

  @MainActor
  func testHelperRegistrationFailureIsVisibleAndCancelDoesNotRetry() async {
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
    await Task.yield()
    XCTAssertTrue(presenter.isPresented)
    XCTAssertTrue(presenter.message.contains("Signing does not match"))
    presenter.cancel()
    helper.enabled = true
    presenter.resumeIfAvailable()
    XCTAssertFalse(resumed)
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
  func register() throws {
    registrations += 1
    if let failure { throw failure }
  }
}
