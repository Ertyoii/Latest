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

  /// The production scene chooses the renderer for the current OS. Fixtures
  /// supply data and services only; they never assemble or restyle a row.
  static func make(
    apps: [Latest.App], selected: Latest.App? = nil, dark: Bool = false,
    searchFocusController: SearchFocusController = SearchFocusController(),
    updating: any AppUpdating = AppUpdateService.shared, testCase: XCTestCase
  ) async throws -> SidebarInputFixture {
    let settings = try isolatedAppListSettings(for: testCase)
    let model = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: apps, filterQuery: nil, settings: settings),
      settings: settings, updating: updating)
    model.select(selected)
    let environment = AppEnvironment(
      searchFocusController: searchFocusController, settings: settings,
      updating: updating, updatesListViewModel: model)
    let window = try await makeLatestTestWindow(
      environment: environment, dark: dark, testCase: testCase)
    let fixture = try SidebarInputFixture(window: window, model: model)
    window.layoutIfNeeded()
    try await Task.sleep(for: .milliseconds(150))
    return fixture
  }

  func contentFrame(for app: Latest.App) throws -> CGRect {
    if let table = scroll.documentView as? NSTableView {
      let index = try XCTUnwrap(model.snapshot.firstIndex(of: app))
      let cell = try XCTUnwrap(table.view(atColumn: 0, row: index, makeIfNecessary: true))
      return cell.convert(cell.bounds, to: nil)
    }
    NSApp.accessibilitySetValue(true, forAttribute: .init(rawValue: "AXEnhancedUserInterface"))
    let row = try XCTUnwrap(
      accessibilityElements().first {
        $0.accessibilityIdentifier() == "updates.app.\(app.identifier)"
          && $0.accessibilityFrame().intersects(window.frame)
      })
    // SwiftUI's source-list content begins 16pt inside the full-width AX row.
    return window.convertFromScreen(row.accessibilityFrame()).offsetBy(dx: 16, dy: 0)
  }

  func captureRow(for app: Latest.App) async throws -> NSBitmapImageRep {
    let frame = try contentFrame(for: app)
    let bitmap = try await captureWindowBitmap(window)
    let crop = CGRect(
      x: frame.minX * 2, y: (window.frame.height - frame.maxY) * 2,
      width: frame.width * 2, height: frame.height * 2)
    return NSBitmapImageRep(cgImage: try XCTUnwrap(bitmap.cgImage?.cropping(to: crop)))
  }

  func clickProgress(for app: Latest.App) async throws {
    let frame = try contentFrame(for: app)
    let location = CGPoint(x: frame.minX + 264, y: frame.midY - 10)
    let down = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: location, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    let up = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseUp, location: location, modifierFlags: [],
        timestamp: down.timestamp + 0.05, windowNumber: window.windowNumber,
        context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
    NSApp.postEvent(up, atStart: false)
    window.sendEvent(down)
    try await Task.sleep(for: .milliseconds(50))
  }
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
    var entry = 0
    var y: CGFloat = 0
    for section in model.snapshot.sections {
      if index == entry { return CGRect(x: 0, y: y, width: 308, height: 27) }
      let count = section.apps.count
      if index > entry && index <= entry + count {
        return CGRect(x: 0, y: y + 37 + CGFloat(index - entry - 1) * 60, width: 308, height: 60)
      }
      entry += count + 1
      y += 37 + CGFloat(count) * 60
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
    try click(row: XCTUnwrap(row, "The sidebar must contain a fully visible app row"))
  }

  func scroll(to y: CGFloat) {
    scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
    scroll.reflectScrolledClipView(scroll.contentView)
    window.contentView?.layoutSubtreeIfNeeded()
  }

  func accessibilityElements() -> [SidebarAccessibilityElement] {
    var seen = Set<ObjectIdentifier>()
    var elements: [SidebarAccessibilityElement] = []
    func visit(_ value: Any) {
      guard let object = value as? NSObject,
        seen.insert(ObjectIdentifier(object)).inserted
      else { return }
      let element = SidebarAccessibilityElement(object: object)
      elements.append(element)
      for child in element.accessibilityChildren() ?? [] { visit(child) }
      // Hosting views may be ignored AX containers; their native children
      // still lead to virtual SwiftUI row elements.
      for child in (value as? NSView)?.subviews ?? [] { visit(child) }
    }
    visit(window)
    return elements
  }

  func activate() async throws {
    NSApp.setActivationPolicy(.regular)
    print("SIDEBAR_TEST_WAITING_FOR_FOCUS pid=\(ProcessInfo.processInfo.processIdentifier)")
    fflush(stdout)
    let deadline = ContinuousClock.now + .seconds(5)
    repeat {
      NSApp.activate()
      window.makeKeyAndOrderFront(nil)
      if window.isKeyWindow { return }
      try await Task.sleep(for: .milliseconds(20))
    } while ContinuousClock.now < deadline
    XCTFail(
      "UI test window could not acquire focus: title=\(window.title), class=\(type(of: window)), visible=\(window.isVisible), canBecomeKey=\(window.canBecomeKey), onActiveSpace=\(window.isOnActiveSpace), active=\(NSApp.isActive), policy=\(NSApp.activationPolicy().rawValue). Run --ui when the desktop is available."
    )
    throw CocoaError(.userCancelled)
  }

  func click(row: Int) throws {
    let document = try XCTUnwrap(scroll.documentView)
    let rect = rowRect(row)
    let y = document.isFlipped ? rect.midY : document.bounds.height - rect.midY
    let point = document.convert(CGPoint(x: 110, y: y), to: nil)
    try clickTestWindow(window, at: point)
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
extension MigrationInteractionContractTest {
  private func makeFixture() async throws -> (SidebarInputFixture, AppEnvironment) {
    let settings = try isolatedAppListSettings(for: self)
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
    let window = try await makeLatestTestWindow(environment: environment, testCase: self)
    let fixture = try SidebarInputFixture(window: window, model: model)
    try await fixture.activate()
    try await Task.sleep(for: .milliseconds(100))
    return (fixture, environment)
  }

  func checkSwiftUISidebarNavigation() async throws {
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

  func checkSwiftUISidebarSearch() async throws {
    let (fixture, environment) = try await makeFixture()
    defer { fixture.window.close() }
    try fixture.focus()
    try await Task.sleep(for: .milliseconds(50))
    environment.commands.focusSearch()
    try await Task.sleep(for: .milliseconds(100))
    let editor = try XCTUnwrap(fixture.window.firstResponder as? NSTextView)
    editor.insertText("Sidebar App 00", replacementRange: NSRange(location: NSNotFound, length: 0))
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
    try clickTestWindow(fixture.window, at: clearLocation)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(fixture.model.searchQuery, "")
    XCTAssertEqual(fixture.model.snapshot.sections.flatMap(\.apps).count, 40)
    XCTAssertTrue(fixture.window.firstResponder === editor)
    editor.insertText("Sidebar App 00", replacementRange: NSRange(location: NSNotFound, length: 0))
    try await Task.sleep(for: .milliseconds(100))
    environment.commands.focusSearch()
    let escape = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: fixture.window.windowNumber, context: nil,
        characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
    fixture.window.sendEvent(escape)
    try await Task.sleep(for: .milliseconds(100))
    // SwiftUI can temporarily retain the reusable AppKit field editor while
    // transferring focus. The following arrow must navigate the actual list.
    fixture.model.setSearchQuery("")
    try await Task.sleep(for: .milliseconds(100))
    try fixture.press(down: true)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(fixture.selectedRow, 2)
    XCTAssertTrue(fixture.model.isKeyboardSelection)
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
}
