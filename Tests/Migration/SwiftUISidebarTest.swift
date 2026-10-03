// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import XCTest

@testable import Latest

/// Exercises the shipping scene through real input, without exposing a SwiftUI
/// coordinator or replacing its navigation with a test implementation.
@MainActor
struct SidebarInputFixture {
  let window: NSWindow
  let model: UpdatesListViewModel
  let scroll: NSScrollView

  init(window: NSWindow, model: UpdatesListViewModel) throws {
    self.window = window
    self.model = model
    func find(_ view: NSView) -> NSScrollView? {
      if let scroll = view as? NSScrollView,
        scroll.convert(scroll.bounds, to: window.contentView).minX < 308
      {
        return scroll
      }
      return view.subviews.lazy.compactMap { find($0) }.first
    }
    scroll = try XCTUnwrap(window.contentView.flatMap { find($0) })
  }

  var selectedRow: Int {
    model.selectedApp.flatMap { model.snapshot.firstIndex(of: $0) } ?? -1
  }

  func rowRect(_ index: Int) -> CGRect {
    var y: CGFloat = 0
    for (row, entry) in model.snapshot.entries.enumerated() {
      let height: CGFloat
      switch entry {
      case .section: height = 27
      case .app: height = 60
      }
      if row == index { return CGRect(x: 0, y: y, width: 308, height: height) }
      y += height
      if case .section = entry { y += 10 }
    }
    return .zero
  }

  func focus() throws {
    // Click a visible app, so SwiftUI obtains focus through its normal path.
    let y = scroll.contentView.bounds.minY
    let row = model.snapshot.entries.indices.first {
      if case .app = model.snapshot.entries[$0] {
        let rect = rowRect($0)
        return rect.minY >= y + 27 && rect.maxY <= y + scroll.contentSize.height
      }
      return false
    }
    if let row { try click(row: row) }
  }

  func scroll(to y: CGFloat) {
    scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
    scroll.reflectScrolledClipView(scroll.contentView)
    window.contentView?.layoutSubtreeIfNeeded()
  }

  func accessibilityElements() -> [SidebarAccessibilityElement] {
    var seen = Set<ObjectIdentifier>()
    func visit(_ value: Any) -> [SidebarAccessibilityElement] {
      guard let object = value as? NSObject,
        seen.insert(ObjectIdentifier(object)).inserted
      else { return [] }
      let element = SidebarAccessibilityElement(object: object)
      // Hosting views may be ignored accessibility containers. Traverse their
      // native children as well so virtual SwiftUI row elements remain reachable.
      let nativeChildren = (value as? NSView)?.subviews ?? []
      return [element] + (element.accessibilityChildren() ?? []).flatMap { visit($0) }
        + nativeChildren.flatMap { visit($0) }
    }
    return visit(window)
  }

  func click(row: Int) throws {
    let document = try XCTUnwrap(scroll.documentView)
    let rect = rowRect(row)
    let y = document.isFlipped ? rect.midY : document.bounds.height - rect.midY
    let point = document.convert(CGPoint(x: 110, y: y), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: point, modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
      window.sendEvent(event)
    }
  }

  func press(down: Bool, repeatKey: Bool = true) throws {
    let character = down ? "\u{F701}" : "\u{F700}"
    let event = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: character, charactersIgnoringModifiers: character,
        isARepeat: repeatKey, keyCode: down ? 125 : 126))
    window.sendEvent(event)
  }
}

/// SwiftUI's virtual elements implement accessibility getters without always
/// declaring the formal AppKit protocol. Query the exposed getters through KVC.
@MainActor
struct SidebarAccessibilityElement {
  let object: NSObject
  private func value(_ key: String) -> Any? {
    guard object.responds(to: NSSelectorFromString(key)) else { return nil }
    return object.value(forKey: key)
  }
  func accessibilityChildren() -> [Any]? { value("accessibilityChildren") as? [Any] }
  func accessibilityIdentifier() -> String? { value("accessibilityIdentifier") as? String }
  func accessibilityLabel() -> String? { value("accessibilityLabel") as? String }
  func accessibilityFrame() -> CGRect {
    (value("accessibilityFrame") as? NSValue)?.rectValue ?? .zero
  }
}

@MainActor
final class SwiftUISidebarChecks {
  private let testCase: XCTestCase
  init(testCase: XCTestCase) { self.testCase = testCase }
  private func makeFixture() async throws -> (SidebarInputFixture, AppEnvironment) {
    #if compiler(>=6.4)
      try XCTSkipUnless(
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27,
        "Custom SwiftUI swipe containers require macOS 27.")
    #else
      throw XCTSkip("Custom SwiftUI swipe containers require the macOS 27 SDK.")
    #endif
    let settings = try isolatedAppListSettings(for: testCase)
    let apps = (0..<40).map { index in
      let bundle = Latest.App.Bundle(
        version: Version(versionNumber: "1.0", buildNumber: nil),
        name: String(format: "Sidebar App %02d", index),
        bundleIdentifier: "com.example.sidebar.\(index)",
        fileURL: URL(fileURLWithPath: "/Applications/Sidebar-\(index).app"), source: .appStore)
      let update = Latest.App.Update(
        app: bundle,
        remoteVersion: Version(versionNumber: "2.0", buildNumber: nil), minimumOSVersion: nil,
        source: .appStore, date: nil, releaseNotes: nil, updateAction: .builtIn { _ in })
      return Latest.App(
        bundle: bundle, update: index < 25 ? .success(update) : nil, isIgnored: false)
    }
    let model = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: apps, filterQuery: nil, settings: settings),
      settings: settings)
    let environment = AppEnvironment(settings: settings, updatesListViewModel: model)
    NSApp.setActivationPolicy(.regular)
    let window = try await makeLatestTestWindow(environment: environment, testCase: testCase)
    print("SIDEBAR_TEST_WAITING_FOR_FOCUS")
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    for _ in 0..<3000 {
      if window.isKeyWindow { break }
      NSApp.activate()
      window.makeKeyAndOrderFront(nil)
      try await Task.sleep(for: .milliseconds(20))
    }
    window.makeKey()
    XCTAssertTrue(window.isKeyWindow)
    try await Task.sleep(for: .milliseconds(100))
    return (try SidebarInputFixture(window: window, model: model), environment)
  }

  func verifyNavigation() throws {
    try runInteractions { try await self.checkPointerKeyboardRepeatReversalHeadersAndEdges() }
  }

  private func checkPointerKeyboardRepeatReversalHeadersAndEdges() async throws {
    let (fixture, _) = try await makeFixture()
    defer { fixture.window.close() }
    try fixture.focus()
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(fixture.selectedRow, 1)
    try fixture.press(down: true)
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(fixture.selectedRow, 2)
    XCTAssertTrue(fixture.model.isKeyboardSelection)
    var previousY: CGFloat = 0
    for _ in 0..<30 {
      try fixture.press(down: true)
      try await Task.sleep(for: .milliseconds(16))
      let y = fixture.scroll.contentView.bounds.minY
      XCTAssertGreaterThanOrEqual(y + 0.5, previousY)
      XCTAssertTrue(
        fixture.scroll.contentView.bounds.contains(fixture.rowRect(fixture.selectedRow)),
        "Selected row must remain fully visible: \(fixture.selectedRow), viewport=\(fixture.scroll.contentView.bounds)"
      )
      previousY = y
    }
    XCTAssertEqual(fixture.selectedRow, 33, "Arrow navigation must skip the second section heading")
    try fixture.press(down: false)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(fixture.selectedRow, 32)
    let reversedY = fixture.scroll.contentView.bounds.minY
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(fixture.scroll.contentView.bounds.minY, reversedY, accuracy: 0.5)
    try fixture.click(row: fixture.selectedRow - 1)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(fixture.selectedRow, 31)
    XCTAssertFalse(fixture.model.isKeyboardSelection)
    for _ in 0..<50 {
      try fixture.press(down: true)
      try await Task.sleep(for: .milliseconds(8))
    }
    XCTAssertEqual(fixture.selectedRow, fixture.model.snapshot.entries.count - 1)
    for _ in 0..<50 {
      try fixture.press(down: false)
      try await Task.sleep(for: .milliseconds(8))
    }
    XCTAssertEqual(fixture.selectedRow, 1)
    XCTAssertEqual(fixture.scroll.contentView.bounds.minY, 0, accuracy: 0.5)
  }

  func verifySearch() throws {
    try runInteractions {
      try await self.checkSearchTypingClearAndEscapeRestoresKeyboardNavigation()
    }
  }

  private func checkSearchTypingClearAndEscapeRestoresKeyboardNavigation() async throws {
    let (fixture, environment) = try await makeFixture()
    defer { fixture.window.close() }
    try fixture.focus()
    try await Task.sleep(for: .milliseconds(50))
    environment.commands.focusSearch()
    try await Task.sleep(for: .milliseconds(100))
    let editor = try XCTUnwrap(fixture.window.firstResponder as? NSTextView)
    editor.insertText("Sidebar App 00")
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(fixture.model.snapshot.sections.flatMap(\.apps).count, 1)
    func findSearch(in view: NSView) -> NSTextField? {
      if let field = view as? NSTextField, field.currentEditor() === editor {
        return field
      }
      return view.subviews.lazy.compactMap { findSearch(in: $0) }.first
    }
    let search = try XCTUnwrap(fixture.window.contentView.flatMap { findSearch(in: $0) })
    let searchFrame = search.convert(search.bounds, to: nil)
    let clearLocation = NSPoint(x: searchFrame.maxX + 7, y: searchFrame.midY)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: clearLocation, modifierFlags: [], timestamp: 0,
          windowNumber: fixture.window.windowNumber, context: nil,
          eventNumber: 0, clickCount: 1, pressure: 1))
      fixture.window.sendEvent(event)
    }
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(fixture.model.searchQuery, "")
    XCTAssertEqual(fixture.model.snapshot.sections.flatMap(\.apps).count, 40)
    XCTAssertTrue(fixture.window.firstResponder === editor)
    editor.insertText("Sidebar App 00")
    try await Task.sleep(for: .milliseconds(100))
    environment.commands.focusSearch()
    let escape = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: fixture.window.windowNumber, context: nil,
        characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
    fixture.window.sendEvent(escape)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertFalse(fixture.window.firstResponder === editor)
    fixture.model.setSearchQuery("")
    try await Task.sleep(for: .milliseconds(100))
    try fixture.press(down: true)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(fixture.selectedRow, 2)
    fixture.model.setSearchQuery("No matching app")
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertTrue(fixture.model.snapshot.sections.isEmpty)
    XCTAssertEqual(fixture.scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    fixture.model.setSearchQuery("")
    try await Task.sleep(for: .milliseconds(100))
    try fixture.press(down: true)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(fixture.selectedRow, 2)
  }
  private func runInteractions(_ operation: @escaping @MainActor () async throws -> Void) throws {
    var failure: Error?
    Task { @MainActor in
      do { try await operation() } catch { failure = error }
      NSApp.stop(nil)
      if let wake = NSEvent.otherEvent(
        with: .applicationDefined, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        subtype: 0, data1: 0, data2: 0)
      {
        NSApp.postEvent(wake, atStart: true)
      }
    }
    NSApp.run()
    if let failure { throw failure }
  }

}
