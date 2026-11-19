// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import Synchronization
import XCTest

@testable import Latest

final class InstallHelperInteractionTest: XCTestCase {
  @MainActor
  func testHelperSheetRepairApprovalCancelAndFallback() throws {
    try requireUITests()
    try runApplicationTest {
      for dark in [false, true] {
        let helper = HelperRegistrationFixture()
        helper.failure = NSError(
          domain: "registration", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Signing does not match"])
        let workspace = StubApplicationWorkspace()
        let presenter = UpdateInstallHelperAlert(helper: helper, workspace: workspace)
        let host = NSHostingView(
          rootView: Color(nsColor: .windowBackgroundColor)
            .modifier(UpdateInstallHelperPresentation(presenter: presenter)))
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        defer { window.close() }
        try await activateTestWindow(window)
        var starts = 0
        let url = URL(string: "macappstore://apps.apple.com/updates")!
        presenter.prepare(fallbackURL: url, error: .installHelperNotRegistered) { starts += 1 }
        try await waitForHelper { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        try await self.capture(sheet, name: "\(dark ? "dark" : "light")-setup")
        try await self.press("Continue", in: sheet)
        try await waitForHelper { presenter.primaryTitle == "Open App Store" }
        XCTAssertEqual(helper.registrations, 1)
        XCTAssertEqual(starts, 0)
        XCTAssertTrue(window.attachedSheet === sheet, "Repair must keep one stable sheet")
        try await self.capture(sheet, name: "\(dark ? "dark" : "light")-failure")
        XCTAssertTrue(
          self.elements(sheet).contains {
            if $0.accessibilityLabel()?.contains("Signing does not match") == true { return true }
            guard $0.object.responds(to: NSSelectorFromString("accessibilityValue")) else {
              return false
            }
            return ($0.object.value(forKey: "accessibilityValue") as? String)?.contains(
              "Signing does not match") == true
          })
        let escape = try XCTUnwrap(
          NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: sheet.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        sheet.sendEvent(escape)
        try await waitForHelper { window.attachedSheet == nil }
        XCTAssertEqual(starts, 0)

        presenter.prepare(fallbackURL: url, error: .installHelperRequiresApproval) { starts += 1 }
        try await waitForHelper { window.attachedSheet != nil }
        let approvalSheet = try XCTUnwrap(window.attachedSheet)
        try await self.capture(approvalSheet, name: "\(dark ? "dark" : "light")-approval")
        try await self.press("Open Settings", in: approvalSheet)
        try await waitForHelper { presenter.primaryTitle == "Open App Store" }
        try await self.press("Open App Store", in: approvalSheet)
        try await waitForHelper { window.attachedSheet == nil }
        XCTAssertEqual(workspace.openedURLs, [url])
        helper.enabled = true
        presenter.resumeIfAvailable()
        XCTAssertEqual(starts, 0)

        helper.suspendsCheck = true
        helper.failure = nil
        presenter.prepare(fallbackURL: url, error: .installHelperRequiresApproval) { starts += 1 }
        presenter.resumeIfAvailable()
        try await waitForHelper { window.attachedSheet != nil && helper.pendingCheck != nil }
        let checkingSheet = try XCTUnwrap(window.attachedSheet)
        try await self.capture(
          checkingSheet, name: "\(dark ? "dark" : "light")-checking", animated: true)
        try await self.press("Cancel", in: checkingSheet)
        try await waitForHelper { window.attachedSheet == nil }
        let completedChecks = helper.completedChecks
        helper.pendingCheck?.resume()
        try await waitForHelper { helper.completedChecks > completedChecks }
        XCTAssertEqual(starts, 0, "Cancelling the checking sheet must discard its late reply")
      }
    }
  }

  @MainActor
  func testFailedStoreUpdateShowsRetryAndOpensTheSpecificProduct() throws {
    try requireUITests()
    try runApplicationTest {
      let retries = Mutex(0)
      let app = makeTestApp(
        name: "Store fixture", version: "1", remoteVersion: "2",
        updateAction: .builtIn { _ in retries.withLock { $0 += 1 } })
      let url = URL(string: "macappstore://apps.apple.com/app/id123")!
      let queue = UpdateQueue()
      let updating = AppUpdateService(queue: queue)
      let workspace = StubApplicationWorkspace()
      let operation = UpdateOperation(
        bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
      queue.addOperation(operation)
      try await waitForHelper { operation.isExecuting }
      operation.finish(
        with: AppStoreUpdateFailure(
          pageURL: url, installedVersion: app.version,
          cause: URLError(.networkConnectionLost)))
      for dark in [false, true] {
        let window = try await makeLatestTestWindow(
          content: UpdateActionView(app: app, workspace: workspace, updating: updating)
            .frame(width: 160, height: 80), dark: dark, testCase: self)
        defer { window.close() }
        try await activateTestWindow(window)
        try await self.capture(window, name: "\(dark ? "dark" : "light")-update-failed")
        try await self.press("Open \(app.name) in the App Store", in: window)
        XCTAssertEqual(workspace.openedURLs.last, url)
        let previous = retries.withLock { $0 }
        try await self.press("Retry updating \(app.name)", in: window)
        XCTAssertEqual(retries.withLock { $0 }, previous + 1)
      }
    }
  }

  @MainActor
  func testStoreDestinationCanBeChangedInGeneralSettings() throws {
    try requireUITests()
    try runApplicationTest {
      let name = "StoreDestination.\(UUID().uuidString)"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
      defer { defaults.removePersistentDomain(forName: name) }
      let window = try await makeLatestTestWindow(
        content: SettingsRootView().defaultAppStorage(defaults), dark: false, testCase: self)
      defer { window.close() }
      try await activateTestWindow(window)
      let key = AppStoreUpdateSettings.alwaysPerformManualUpdates.rawValue
      XCTAssertFalse(defaults.bool(forKey: key))
      try await self.press("App Store", in: window, usingMouse: true)
      try await waitForHelper { defaults.bool(forKey: key) }
      try await self.press("Latest", in: window, usingMouse: true)
      try await waitForHelper { !defaults.bool(forKey: key) }
      try await self.capture(window, name: "settings")
    }
  }

  @MainActor
  private func elements(_ window: NSWindow) -> [SidebarAccessibilityElement] {
    NSApp.accessibilitySetValue(true, forAttribute: .init(rawValue: "AXEnhancedUserInterface"))
    var seen = Set<ObjectIdentifier>()
    var result: [SidebarAccessibilityElement] = []
    func visit(_ value: Any) {
      guard let object = value as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else {
        return
      }
      let element = SidebarAccessibilityElement(object: object)
      result.append(element)
      for child in element.accessibilityChildren() ?? [] { visit(child) }
      for child in (value as? NSView)?.subviews ?? [] { visit(child) }
    }
    visit(window)
    return result
  }

  @MainActor
  private func press(_ title: String, in window: NSWindow, usingMouse: Bool = false) async throws {
    func matchingElements() -> [SidebarAccessibilityElement] {
      elements(window).filter {
        if $0.accessibilityLabel() == title { return true }
        if let button = $0.object as? NSButton, button.title == title { return true }
        guard $0.object.responds(to: NSSelectorFromString("accessibilityTitle")) else {
          return false
        }
        return $0.object.value(forKey: "accessibilityTitle") as? String == title
      }
    }
    try await waitForHelper { !matchingElements().isEmpty }
    let matches = matchingElements()
    let selector = NSSelectorFromString("accessibilityPerformPress")
    if !usingMouse, let button = matches.first(where: { $0.object.responds(to: selector) }) {
      typealias Press = @convention(c) (NSObject, Selector) -> Bool
      let press = unsafeBitCast(button.object.method(for: selector), to: Press.self)
      XCTAssertTrue(press(button.object, selector))
      return
    }
    let element = try XCTUnwrap(matches.first, "Missing control: \(title)")
    let frame = element.accessibilityFrame()
    XCTAssertFalse(frame.isEmpty)
    let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
    try clickTestWindow(window, at: point)
  }

  @MainActor
  private func capture(_ window: NSWindow, name: String, animated: Bool = false) async throws {
    try await Task.sleep(for: .milliseconds(250))
    // A running progress indicator cannot produce identical settled frames.
    let bitmap =
      try await animated ? captureWindowBitmap(window) : settledWindowBitmap(window)
    let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
        "build/helper-repair")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
      to: output.appendingPathComponent("\(name).png"))
  }
}
