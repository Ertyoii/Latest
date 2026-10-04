// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import XCTest

@testable import Latest

final class ApplicationLifecycleTest: XCTestCase {
  @MainActor
  func testUnitTestsUseIsolatedApplicationLifecycle() {
    XCTAssertTrue(ApplicationRuntime.isRunningUnitTests)
    if ProcessInfo.processInfo.environment["LATEST_UI_TESTS"] != "1" {
      XCTAssertEqual(NSApp.activationPolicy(), .prohibited)
      XCTAssertFalse(NSApp.isActive, "Background tests must not activate over another app")
    }
  }

  @MainActor
  func testStartupActivatesReleaseNotesCatalogBeforeInitialUpdateCheck() async {
    var events = [String]()
    await AppStartupSequence.run(
      refreshCatalog: {
        events.append("catalog")
        await Task.yield()
        events.append("catalog-ready")
      },
      checkForUpdates: {
        events.append("check")
      }
    )

    XCTAssertEqual(events, ["catalog", "catalog-ready", "check"])
  }
}
