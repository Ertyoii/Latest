// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import Synchronization
import XCTest

@testable import Latest

/// Exercises the shipping scene through real input, without exposing a SwiftUI
/// coordinator or replacing its navigation with a test implementation.
@MainActor
struct SidebarInputFixture {
  let window: NSWindow
  let model: UpdatesListViewModel

  /// The production scene uses the shared SwiftUI renderer. Fixtures
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
    NSApp.accessibilitySetValue(true, forAttribute: .init(rawValue: "AXEnhancedUserInterface"))
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

  func clickSearchClearButton() async throws {
    for _ in 0..<100 {
      window.contentView?.layoutSubtreeIfNeeded()
      if let button = accessibilityElements().first(where: {
        $0.accessibilityLabel() == "Clear Search"
          && !$0.accessibilityFrame().isEmpty
          && $0.accessibilityFrame().intersects(window.frame)
      }) {
        let frame = window.convertFromScreen(button.accessibilityFrame())
        try clickTestWindow(window, at: NSPoint(x: frame.midX, y: frame.midY))
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("The visible search clear button did not expose its accessibility frame")
    throw CocoaError(.coderInvalidValue)
  }

  func activate() async throws {
    try await activateTestWindow(window)
  }

  func click(row: Int) throws {
    guard case .app(let app) = model.snapshot.entries[row] else {
      XCTFail("Mouse targeting requires an app row")
      return
    }
    let frame = try contentFrame(for: app)
    try clickTestWindow(window, at: CGPoint(x: frame.minX + 110, y: frame.midY))
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

  func wheel(dx: Int32 = 0, dy: Int32) throws {
    let event = try XCTUnwrap(
      CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
        wheel1: dy, wheel2: dx, wheel3: 0))
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: event)))
  }

  func horizontalWheel(row: Int, dx: Int32) throws {
    guard case .app(let app) = model.snapshot.entries[row] else {
      throw CocoaError(.coderInvalidValue)
    }
    let frame = try contentFrame(for: app)
    let point = window.convertPoint(toScreen: CGPoint(x: frame.minX + 194, y: frame.midY))
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let event = try XCTUnwrap(
      CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
        wheel1: 0, wheel2: dx, wheel3: 0))
    event.location = CGPoint(x: point.x, y: screen.frame.maxY - point.y)
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    // Queue the event through NSApplication so the production input monitor
    // receives the same windowless scroll events as a mouse or VM.
    NSApp.postEvent(try XCTUnwrap(NSEvent(cgEvent: event)), atStart: false)
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
  private func makeFixture(
    updating: any AppUpdating = AppUpdateService.shared,
    onUpdate: @escaping @Sendable (Int) -> Void = { _ in }
  ) async throws -> (SidebarInputFixture, AppEnvironment) {
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
        source: .appStore, date: nil, releaseNotes: nil,
        updateAction: .builtIn { _ in onUpdate(index) })
      return Latest.App(
        bundle: bundle, update: index < 25 ? .success(update) : nil, isIgnored: false)
    }
    let model = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: apps, filterQuery: nil, settings: settings),
      settings: settings, updating: updating)
    let environment = AppEnvironment(
      settings: settings, updating: updating, updatesListViewModel: model)
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
    try await fixture.clickSearchClearButton()
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
    let search = try XCTUnwrap(
      fixture.accessibilityElements().compactMap { $0.object as? NSTextField }.first)
    let searchFrame = search.convert(search.bounds, to: nil)
    try clickTestWindow(fixture.window, at: CGPoint(x: searchFrame.midX, y: searchFrame.midY))
    try await Task.sleep(for: .milliseconds(50))
    fixture.window.sendEvent(escape)
    try await Task.sleep(for: .milliseconds(100))
    try fixture.press(down: true)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(fixture.selectedRow, 3, "Mouse entry into search must also restore navigation")
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

  func testSidebarScrollbarsAndEdgesKeepRowsInPlace() throws {
    try requireUITests()
    try runApplicationTest {
      let (fixture, _) = try await self.makeFixture()
      defer { fixture.window.close() }
      let app = try XCTUnwrap(fixture.model.snapshot.sections.first?.apps.first)
      let before = try fixture.contentFrame(for: app)
      fixture.scroll.flashScrollers()
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertEqual(try fixture.contentFrame(for: app), before)
      XCTAssertEqual(fixture.scroll.contentSize.width, 308, accuracy: 0.5)
      for (position, delta) in [
        (CGFloat(0), Int32(1000)), (CGFloat.greatestFiniteMagnitude, Int32(-1000)),
      ] {
        let document = try XCTUnwrap(fixture.scroll.documentView)
        let maximum = max(0, document.bounds.height - fixture.scroll.contentSize.height)
        fixture.scroll(to: min(position, maximum))
        try fixture.wheel(dy: delta)
        for _ in 0..<8 {
          try await Task.sleep(for: .milliseconds(16))
          let bounds =
            fixture.scroll.contentView.layer?.presentation()?.bounds
            ?? fixture.scroll.contentView.bounds
          XCTAssertGreaterThanOrEqual(bounds.minY, -0.5)
          XCTAssertLessThanOrEqual(bounds.minY, maximum + 0.5)
        }
      }
      try fixture.wheel(dx: 200, dy: 0)
      try await Task.sleep(for: .milliseconds(50))
      XCTAssertEqual(fixture.scroll.contentView.bounds.minX, 0, accuracy: 0.5)
    }
  }

  func testSidebarSwipesRevealActionsAndExecuteOnlyOnClick() throws {
    try requireUITests()
    try runApplicationTest {
      let calls = Mutex<[Int]>([])
      let queue = UpdateQueue()
      let service = AppUpdateService(queue: queue)
      let (fixture, _) = try await self.makeFixture(updating: service) { index in
        calls.withLock { $0.append(index) }
      }
      defer { fixture.window.close() }
      try fixture.horizontalWheel(row: 3, dx: 180)
      try await Task.sleep(for: .milliseconds(350))
      let bitmap = try await captureWindowBitmap(fixture.window)
      let background = try XCTUnwrap(NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB))
      for title in ["OpenAction", "RevealAction"] {
        let action = try XCTUnwrap(
          fixture.accessibilityElements().first {
            $0.accessibilityLabel() == NSLocalizedString(title, comment: "")
              && $0.accessibilityFrame().intersects(fixture.window.frame)
          })
        let frame = fixture.window.convertFromScreen(action.accessibilityFrame())
        // Both controls must actually be painted, not merely exposed by AX
        // while most of the action strip is still clipped behind the row.
        let color = try XCTUnwrap(
          bitmap.colorAt(
            x: Int((frame.maxX - 5) * 2), y: Int((fixture.window.frame.height - frame.minY - 5) * 2)
          )?
          .usingColorSpace(.deviceRGB))
        let contrast =
          abs(color.redComponent - background.redComponent)
          + abs(color.greenComponent - background.greenComponent)
          + abs(color.blueComponent - background.blueComponent)
        XCTAssertGreaterThan(contrast, 0.3, "Both revealed controls must be fully visible")
      }
      try fixture.horizontalWheel(row: 3, dx: -144)
      try await Task.sleep(for: .milliseconds(350))
      XCTAssertFalse(
        fixture.accessibilityElements().contains {
          ["OpenAction", "RevealAction"].map { NSLocalizedString($0, comment: "") }
            .contains($0.accessibilityLabel() ?? "")
        }, "Reversing the swipe must close both actions")
      try fixture.horizontalWheel(row: 2, dx: -180)
      try await Task.sleep(for: .milliseconds(350))
      XCTAssertTrue(calls.withLock { $0.isEmpty }, "Full swipe must only reveal an action")
      let update = try XCTUnwrap(
        fixture.accessibilityElements().first {
          $0.accessibilityLabel() == NSLocalizedString("UpdateAction", comment: "")
            && $0.accessibilityFrame().intersects(fixture.window.frame)
        })
      let frame = fixture.window.convertFromScreen(update.accessibilityFrame())
      try clickTestWindow(fixture.window, at: CGPoint(x: frame.midX, y: frame.midY))
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertEqual(calls.withLock { $0 }, [1], "The revealed action must target its own row once")
      try fixture.horizontalWheel(row: 3, dx: -100)
      try await Task.sleep(for: .milliseconds(300))
      XCTAssertEqual(calls.withLock { $0 }, [1], "Horizontal scrolling must only reveal an action")
      let wheelUpdate = try XCTUnwrap(
        fixture.accessibilityElements().first {
          $0.accessibilityLabel() == NSLocalizedString("UpdateAction", comment: "")
            && $0.accessibilityFrame().intersects(fixture.window.frame)
        })
      let wheelFrame = fixture.window.convertFromScreen(wheelUpdate.accessibilityFrame())
      try clickTestWindow(fixture.window, at: CGPoint(x: wheelFrame.midX, y: wheelFrame.midY))
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertEqual(calls.withLock { $0 }, [1, 2])
      XCTAssertEqual(fixture.scroll.contentView.bounds.minX, 0, accuracy: 0.5)
    }
  }
}
