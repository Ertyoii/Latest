// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import XCTest

@testable import Latest

final class InstallHelperInteractionTest: XCTestCase {
  @MainActor
  func testHelperInstallButtonPresentsRegistrationFailure() async throws {
    try requireUITests()
    let stored = AppStoreUpdateSettings.alwaysPerformManualUpdates.active
    AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
    defer { AppStoreUpdateSettings.alwaysPerformManualUpdates.active = stored }
    let helper = HelperRegistrationFixture()
    helper.failure = NSError(
      domain: "registration", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Signing does not match"])
    let presenter = UpdateInstallHelperAlert(helper: helper)
    let host = NSHostingView(
      rootView: Color(nsColor: .windowBackgroundColor)
        .background(WindowAccessor())
        .modifier(UpdateInstallHelperPresentation(presenter: presenter)))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    presenter.present(
      .installHelperNotRegistered, fallbackURL: URL(string: "https://example.com")!, retry: {})
    for _ in 0..<80 {
      if window.attachedSheet != nil { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    let sheet = try XCTUnwrap(window.attachedSheet)
    let install = try XCTUnwrap(
      sheet.contentView?.allDescendants().compactMap { $0 as? NSButton }
        .first { $0.title == presenter.primaryTitle })
    install.performClick(nil)
    var displayedMessages: [String] = []
    for _ in 0..<80 {
      displayedMessages =
        window.attachedSheet?.contentView?.allDescendants()
        .compactMap { ($0 as? NSTextField)?.stringValue } ?? []
      if displayedMessages.contains(where: { $0.contains("Signing does not match") }) { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTAssertEqual(helper.registrations, 1)
    XCTAssertTrue(
      displayedMessages.contains(where: { $0.contains("Signing does not match") }),
      "Install Helper must show its failure in a new visible dialog")
    presenter.cancel()
  }

  @MainActor
  func testHelperDialogRemembersManualUpdatesAndDismissesWithCancelOrEscape() async throws {
    try requireUITests()
    let stored = AppStoreUpdateSettings.alwaysPerformManualUpdates.active
    AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
    defer { AppStoreUpdateSettings.alwaysPerformManualUpdates.active = stored }
    let presenter = UpdateInstallHelperAlert(helper: HelperRegistrationFixture())
    let host = NSHostingView(
      rootView: Color(nsColor: .windowBackgroundColor)
        .background(WindowAccessor())
        .modifier(UpdateInstallHelperPresentation(presenter: presenter)))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    try await activateTestWindow(window)
    for error in [InstallHelperError.installHelperNotRegistered, .installHelperRequiresApproval] {
      presenter.present(error, fallbackURL: URL(string: "https://example.com")!, retry: {})
      for _ in 0..<80 {
        if window.attachedSheet != nil { break }
        try await Task.sleep(for: .milliseconds(25))
      }
      let sheet = try XCTUnwrap(window.attachedSheet)
      let buttons = sheet.contentView?.allDescendants().compactMap { $0 as? NSButton } ?? []
      XCTAssertTrue(buttons.contains { $0.title == presenter.primaryTitle })
      let suppression = try XCTUnwrap(
        buttons.first {
          $0.title == NSLocalizedString("UpdateInstallHelperAlert.SuppressionTitle", comment: "")
        })
      suppression.performClick(nil)
      try await Task.sleep(for: .milliseconds(25))
      if error == .installHelperRequiresApproval {
        let escape = try XCTUnwrap(
          NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: sheet.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        sheet.sendEvent(escape)
      } else {
        let cancel = try XCTUnwrap(
          buttons.first {
            $0.title == NSLocalizedString("UpdateInstallHelperAlert.Cancel", comment: "")
          })
        cancel.performClick(nil)
      }
      for _ in 0..<80 {
        if window.attachedSheet == nil { break }
        try await Task.sleep(for: .milliseconds(25))
      }
      XCTAssertNil(window.attachedSheet)
      XCTAssertFalse(presenter.isPresented)
      XCTAssertTrue(AppStoreUpdateSettings.alwaysPerformManualUpdates.active)
      AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
    }
  }
}
