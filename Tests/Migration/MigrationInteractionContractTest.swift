//
//  MigrationInteractionContractTest.swift
//  Latest Tests
//
//  Created by ertyoii on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-01.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import Synchronization
import WebKit
import XCTest

@testable import Latest

final class MigrationInteractionContractTest: XCTestCase {
  func testApplicationAppearanceResolvesStoredPreference() {
    XCTAssertNil(ApplicationAppearance.system.appKitAppearanceName)
    XCTAssertEqual(ApplicationAppearance.light.appKitAppearanceName, .aqua)
    XCTAssertEqual(ApplicationAppearance.dark.appKitAppearanceName, .darkAqua)
    XCTAssertEqual(ApplicationAppearance.resolve("dark"), .dark)
    XCTAssertEqual(ApplicationAppearance.resolve("invalid"), .system)
    XCTAssertEqual(ApplicationAppearance.allCases.map(\.title), ["System", "Light", "Dark"])
  }

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

  @MainActor
  func testHelperInstallButtonPresentsRegistrationFailure() async throws {
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
  func testSwiftUIHelperAlertMatchesOriginalSheetPixelsAndSuppression() async throws {
    let stored = AppStoreUpdateSettings.alwaysPerformManualUpdates.active
    AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
    defer { AppStoreUpdateSettings.alwaysPerformManualUpdates.active = stored }
    NSApplication.shared.activate()
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
    window.makeKeyAndOrderFront(nil)
    // SwiftUI's first dialog activates this test host asynchronously. Warm it
    // before capturing the independent AppKit reference so activation matches.
    presenter.present(
      .installHelperNotRegistered, fallbackURL: URL(string: "https://example.com")!, retry: {})
    for _ in 0..<80 {
      if window.attachedSheet != nil { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    try await Task.sleep(for: .milliseconds(600))
    presenter.cancel()
    for _ in 0..<80 {
      if window.attachedSheet == nil { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    try await Task.sleep(for: .milliseconds(100))
    defer { window.close() }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("build/helper-alert-parity", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for dark in [false, true] {
      window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      for error in [InstallHelperError.installHelperNotRegistered, .installHelperRequiresApproval] {
        let original = NSAlert(error: error)
        original.alertStyle = .informational
        original.messageText = NSLocalizedString("UpdateInstallHelperAlert.Title", comment: "")
        original.informativeText = error.errorDescription ?? ""
        original.showsSuppressionButton = true
        original.suppressionButton?.title = NSLocalizedString(
          "UpdateInstallHelperAlert.SuppressionTitle", comment: "")
        original.addButton(
          withTitle: NSLocalizedString(
            error == .installHelperNotRegistered
              ? "UpdateInstallHelperAlert.Primary.InstallHelper"
              : "UpdateInstallHelperAlert.Primary.OpenSettings", comment: ""))
        original.addButton(
          withTitle: NSLocalizedString("UpdateInstallHelperAlert.Secondary.AppStore", comment: ""))
        original.addButton(
          withTitle: NSLocalizedString("UpdateInstallHelperAlert.Cancel", comment: ""))
        original.beginSheetModal(for: window) { _ in }
        original.window.makeKey()
        try await Task.sleep(for: .milliseconds(600))
        let originalFrame = original.window.frame
        let before = try await captureHelperSheet(original.window, parent: window)
        window.endSheet(original.window)
        original.window.orderOut(nil)
        for _ in 0..<80 {
          if window.attachedSheet == nil { break }
          try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNil(window.attachedSheet, "Original sheet must finish dismissal")
        presenter.present(error, fallbackURL: URL(string: "https://example.com")!, retry: {})
        var sheet: NSWindow?
        for _ in 0..<40 {
          sheet = window.attachedSheet
          if let sheet, sheet !== original.window, sheet.isVisible { break }
          try await Task.sleep(for: .milliseconds(25))
        }
        let candidate = try XCTUnwrap(sheet)
        XCTAssertFalse(
          candidate === original.window, "Compare distinct original and SwiftUI sheets")
        candidate.makeKey()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(candidate.frame, originalFrame, "Sheet geometry")
        let after = try await captureHelperSheet(candidate, parent: window)
        let name =
          "\(dark ? "dark" : "light")-\(error == .installHelperNotRegistered ? "install" : "approval")"
        try XCTUnwrap(before.representation(using: .png, properties: [:])).write(
          to: root.appendingPathComponent("\(name)-before.png"))
        try XCTUnwrap(after.representation(using: .png, properties: [:])).write(
          to: root.appendingPathComponent("\(name)-after.png"))
        XCTAssertEqual(after.pixelsWide, before.pixelsWide, name)
        XCTAssertEqual(after.pixelsHigh, before.pixelsHigh, name)
        XCTAssertEqual(try normalizedRGBABytes(after), try normalizedRGBABytes(before), name)
        let buttons = candidate.contentView?.allDescendants().compactMap { $0 as? NSButton } ?? []
        let suppression = try XCTUnwrap(
          buttons.first {
            $0.title == NSLocalizedString("UpdateInstallHelperAlert.SuppressionTitle", comment: "")
          })
        suppression.performClick(nil)
        try await Task.sleep(for: .milliseconds(25))
        let cancel = try XCTUnwrap(
          buttons.first {
            $0.title == NSLocalizedString("UpdateInstallHelperAlert.Cancel", comment: "")
          })
        if dark, error == .installHelperRequiresApproval {
          let escape = try XCTUnwrap(
            NSEvent.keyEvent(
              with: .keyDown, location: .zero,
              modifierFlags: [], timestamp: 0, windowNumber: candidate.windowNumber,
              context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
              isARepeat: false, keyCode: 53))
          candidate.sendEvent(escape)
        } else {
          cancel.performClick(nil)
        }
        for _ in 0..<80 {
          if window.attachedSheet == nil { break }
          try await Task.sleep(for: .milliseconds(25))
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(presenter.isPresented)
        XCTAssertTrue(AppStoreUpdateSettings.alwaysPerformManualUpdates.active)
        presenter.cancel()
        AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
        try await Task.sleep(for: .milliseconds(200))
      }
    }
  }

  @MainActor
  private func captureHelperSheet(_ sheet: NSWindow, parent: NSWindow) async throws
    -> NSBitmapImageRep
  {
    // ScreenCaptureKit groups a sheet with its parent. Capture at the parent's
    // real scale, then crop the sheet's frame without resizing its pixels.
    let bitmap = try await captureWindowBitmap(parent)
    let frame = sheet.frame
    let crop = CGRect(
      x: (frame.minX - parent.frame.minX) * 2,
      y: (parent.frame.maxY - frame.maxY) * 2,
      width: frame.width * 2, height: frame.height * 2)
    return NSBitmapImageRep(cgImage: try XCTUnwrap(bitmap.cgImage?.cropping(to: crop)))
  }

  private func normalizedRGBABytes(_ bitmap: NSBitmapImageRep) throws -> Data {
    let image = try XCTUnwrap(bitmap.cgImage)
    var data = Data(count: bitmap.pixelsWide * bitmap.pixelsHigh * 4)
    try data.withUnsafeMutableBytes { bytes in
      let context = try XCTUnwrap(
        CGContext(
          data: bytes.baseAddress,
          width: bitmap.pixelsWide, height: bitmap.pixelsHigh, bitsPerComponent: 8,
          bytesPerRow: bitmap.pixelsWide * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(
        image, in: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
    }
    return data
  }

  @MainActor
  func testApplicationAppearanceCanReturnFromDarkToSystem() {
    let application = NSApplication.shared
    let originalAppearance = application.appearance
    defer { application.appearance = originalAppearance }

    ApplicationAppearance.dark.apply(to: application)
    XCTAssertEqual(application.appearance?.name, .darkAqua)

    ApplicationAppearance.system.apply(to: application)
    XCTAssertNil(application.appearance)
  }

  @MainActor
  func testGeneralSettingsContentMakesRoomForAppearanceSelector() {
    XCTAssertEqual(SettingsViewModel.Tab.general.contentSize, CGSize(width: 440, height: 255))
  }

  @MainActor
  func testLocalUATFixtureIsOfflinePopulatedAndSelected() throws {
    let environment = AppEnvironment.localUATFixture(
      settings: try isolatedAppListSettings(for: self))
    let apps = environment.updatesListViewModel.snapshot.apps
    XCTAssertEqual(apps.count, 18)
    let firstVisible = try XCTUnwrap(
      environment.updatesListViewModel.snapshot.sections.first?.apps.first)
    let selected = try XCTUnwrap(environment.updatesListViewModel.selectedApp)
    XCTAssertEqual(selected.identifier, firstVisible.identifier)
    XCTAssertTrue(apps.allSatisfy { $0.releaseNotes != nil })
    XCTAssertTrue(apps.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
    XCTAssertEqual(
      Set(apps.map(\.fileURL)).count, apps.count, "UAT must exercise distinct real app icons")
  }

  @MainActor
  func testUpdateProgressAggregatesOverlappingBatches() {
    let service = UpdateCheckingService()
    let coordinator = UpdateCheckCoordinator()

    service.updateCheckerDidStartScanningForApps(coordinator)
    service.updateChecker(coordinator, didStartCheckingApps: 4, generation: 1)
    service.updateChecker(coordinator, didStartCheckingApps: 1, generation: 1)

    XCTAssertTrue(service.isRunning)
    XCTAssertFalse(service.isIndeterminate)
    XCTAssertEqual(service.totalApps, 5)

    service.updateCheckerDidFinishCheckingForUpdates(coordinator, generation: 1)
    XCTAssertTrue(service.isRunning)

    service.updateCheckerDidFinishCheckingForUpdates(coordinator, generation: 1)
    XCTAssertFalse(service.isRunning)
  }

  @MainActor
  func testReplacementBatchDiscardsProgressForCancelledGeneration() {
    let service = UpdateCheckingService()
    let coordinator = UpdateCheckCoordinator()

    service.updateCheckerDidStartScanningForApps(coordinator)
    service.updateChecker(coordinator, didStartCheckingApps: 38, generation: 1)
    service.updateChecker(coordinator, didCheckApp: makeApp(name: "Checked", version: "1"))

    service.updateChecker(coordinator, didStartCheckingApps: 1, generation: 2)

    XCTAssertTrue(service.isRunning)
    XCTAssertEqual(service.checkedApps, 0)
    XCTAssertEqual(service.totalApps, 1)

    service.updateCheckerDidFinishCheckingForUpdates(coordinator, generation: 1)
    XCTAssertTrue(service.isRunning)

    service.updateCheckerDidFinishCheckingForUpdates(coordinator, generation: 2)
    XCTAssertFalse(service.isRunning)
  }

  @MainActor
  func testNativeLocationsTableOwnsSelectionAndRowSemantics() throws {
    let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    let unavailableURL = URL(fileURLWithPath: "/Volumes/Unavailable Apps", isDirectory: true)
    let selection = SelectionBox()
    let view = DirectoryLocationsTable(
      urls: [applicationsURL, unavailableURL],
      selection: Binding(
        get: { selection.url },
        set: { selection.url = $0 }
      ),
      loadDetails: { url in
        DirectoryLocationDetails(
          isReachable: url == applicationsURL,
          appCount: url == applicationsURL ? 38 : 0
        )
      }
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
    let window = NSWindow(
      contentRect: hostingView.bounds,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = hostingView
    window.makeKeyAndOrderFront(nil)
    window.layoutIfNeeded()
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

    let tableView = try XCTUnwrap(hostingView.descendant(of: NSTableView.self))
    XCTAssertEqual(tableView.numberOfRows, 2)
    tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    XCTAssertEqual(selection.url, unavailableURL)

    XCTAssertEqual(
      DirectoryLocationPresentation.accessibilityLabel(
        for: applicationsURL,
        details: DirectoryLocationDetails(isReachable: true, appCount: 38)
      ),
      "/Applications, 38 applications"
    )
    XCTAssertEqual(
      DirectoryLocationPresentation.accessibilityLabel(
        for: unavailableURL,
        details: DirectoryLocationDetails(isReachable: false, appCount: 0)
      ),
      "/Volumes/Unavailable Apps, unavailable, 0 applications"
    )
  }

  @MainActor
  func testSidebarSearchAcceptsTypingClearAndEscapeRestoresTableFocus() async throws {
    // FocusState and the native table settle on separate main-actor turns.
    // Await the actual responder transition rather than a fixed 50-ms delay.
    func waitForFocus(_ condition: () -> Bool) async throws {
      for _ in 0..<100 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    let app = makeApp(name: "Notes", version: "1", remoteVersion: "2")
    let viewModel = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: [app], filterQuery: nil))
    let focusController = SearchFocusController()
    let host = NSHostingView(
      rootView: UpdatesSidebarView(viewModel: viewModel, searchFocusController: focusController))
    host.frame = NSRect(x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: 420)
    let window = NSWindow(
      contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    let table = try XCTUnwrap(host.descendant(of: NSTableView.self))
    XCTAssertTrue(window.makeFirstResponder(table))

    AppCommands(
      updateCheckingService: UpdateCheckingService(),
      updatesListViewModel: viewModel, searchFocusController: focusController
    ).focusSearch()
    try await Task.sleep(for: .milliseconds(100))
    host.layoutSubtreeIfNeeded()
    let search = try XCTUnwrap(host.descendant(of: NSTextField.self))
    XCTAssertTrue(search.currentEditor() === window.firstResponder)

    search.currentEditor()?.insertText("Notes")
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(viewModel.searchQuery, "Notes")

    // Repeating Find while editing must not replace the restoration target.
    focusController.focus()
    try await Task.sleep(for: .milliseconds(50))
    let escape = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil,
        characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
        isARepeat: false, keyCode: 53))
    window.sendEvent(escape)
    try await waitForFocus { window.firstResponder === table }
    XCTAssertTrue(window.firstResponder === table)
    XCTAssertEqual(viewModel.searchQuery, "Notes")

    AppCommands(
      updateCheckingService: UpdateCheckingService(),
      updatesListViewModel: viewModel, searchFocusController: focusController
    ).focusSearch()
    try await waitForFocus { search.currentEditor() === window.firstResponder }
    let searchFrame = search.convert(search.bounds, to: nil)
    let clearLocation = NSPoint(x: searchFrame.maxX + 7, y: searchFrame.midY)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: clearLocation, modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil,
          eventNumber: 0, clickCount: 1, pressure: 1))
      window.sendEvent(event)
    }
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(viewModel.searchQuery, "")
    try await waitForFocus { search.currentEditor() === window.firstResponder }
    XCTAssertTrue(search.currentEditor() === window.firstResponder)
    window.sendEvent(escape)
    try await waitForFocus { window.firstResponder === table }
    XCTAssertTrue(window.firstResponder === table)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type,
          location: NSPoint(x: searchFrame.midX, y: searchFrame.midY), modifierFlags: [],
          timestamp: 0, windowNumber: window.windowNumber, context: nil,
          eventNumber: 0, clickCount: 1, pressure: 1))
      window.sendEvent(event)
    }
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(search.currentEditor() === window.firstResponder)
    window.sendEvent(escape)
    try await waitForFocus { window.firstResponder === table }
    XCTAssertTrue(
      window.firstResponder === table, "Mouse entry must also restore sidebar navigation")
    focusController.focus()
    try await Task.sleep(for: .milliseconds(50))
    search.currentEditor()?.insertText("No matching app")
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(viewModel.snapshot.sections.isEmpty)
    window.sendEvent(escape)
    try await waitForFocus { window.firstResponder === table }
    XCTAssertTrue(
      window.firstResponder === table, "An empty search result must still restore keyboard focus")
  }

  @MainActor
  func testSearchEscapeRestoresReleaseNotesAfterRepeatedFindCommands() async throws {
    let environment = AppEnvironment.localUATFixture(
      settings: try isolatedAppListSettings(for: self))
    let window = try await makeLatestTestWindow(environment: environment, testCase: self)
    let host = try XCTUnwrap(window.contentView)
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    let web = try XCTUnwrap(host.descendant(of: WKWebView.self))
    try await waitForWebContent(web, containing: "Offline acceptance fixture")
    XCTAssertTrue(window.makeFirstResponder(web))
    try await Task.sleep(for: .milliseconds(50))
    environment.commands.focusSearch()
    try await Task.sleep(for: .milliseconds(50))
    let search = try XCTUnwrap(host.descendant(of: NSTextField.self))
    XCTAssertTrue(search.currentEditor() === window.firstResponder)
    environment.commands.focusSearch()
    try await Task.sleep(for: .milliseconds(50))
    let escape = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
        characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
    window.sendEvent(escape)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(
      window.firstResponder === web, "Escape must return to the previously focused release notes")
    let table = try XCTUnwrap(host.descendant(of: NSTableView.self))
    for destination: NSResponder in [table, web, table] {
      XCTAssertTrue(window.makeFirstResponder(destination))
      try await Task.sleep(for: .milliseconds(50))
      environment.commands.focusSearch()
      try await Task.sleep(for: .milliseconds(50))
      window.sendEvent(escape)
      try await Task.sleep(for: .milliseconds(50))
      XCTAssertTrue(
        window.firstResponder === destination,
        "Escape must follow the latest focus destination when switching between list and notes")
    }
  }

  @MainActor
  func testShippingTableArrowMovementSkipsSectionHeaders() throws {
    let (window, table, viewModel) = try makeShippingSidebar()
    defer { window.close() }
    let appRows = viewModel.snapshot.entries.indices.filter {
      if case .app = viewModel.snapshot.entries[$0] { return true }
      return false
    }
    XCTAssertEqual(appRows.count, 2)
    table.selectRowIndexes(IndexSet(integer: appRows[0]), byExtendingSelection: false)
    func pressArrow(keyCode: UInt16, character: String) throws {
      let event = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
          timestamp: 0, windowNumber: window.windowNumber, context: nil,
          characters: character, charactersIgnoringModifiers: character,
          isARepeat: false, keyCode: keyCode
        ))
      window.firstResponder?.keyDown(with: event)
    }
    let cell = try XCTUnwrap(table.view(atColumn: 0, row: appRows[0], makeIfNecessary: true))
    let point = cell.convert(NSPoint(x: 70, y: cell.bounds.midY), to: cell.superview)
    let target = try XCTUnwrap(cell.hitTest(point))
    let location = cell.convert(NSPoint(x: 70, y: cell.bounds.midY), to: nil)
    let mouseDown = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 1))
    let mouseUp = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseUp, location: location, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil,
        eventNumber: 1, clickCount: 1, pressure: 0))
    NSApp.postEvent(mouseUp, atStart: true)
    target.mouseDown(with: mouseDown)
    try pressArrow(keyCode: 125, character: "\u{F701}")
    XCTAssertEqual(table.selectedRow, appRows[1])
    XCTAssertEqual(
      viewModel.selectedApp?.identifier, viewModel.snapshot.sections.last?.apps.first?.identifier)
    try pressArrow(keyCode: 126, character: "\u{F700}")
    XCTAssertEqual(table.selectedRow, appRows[0])
  }

  @MainActor
  func testHeldArrowNavigationKeepsRowsVisibleAndSeparate() async throws {
    let settings = try isolatedAppListSettings(for: self)
    let apps = (0..<40).map {
      makeApp(name: String(format: "App %02d", $0), version: "1", remoteVersion: "2")
    }
    let viewModel = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: apps, filterQuery: nil, settings: settings),
      settings: settings)
    let host = NSHostingView(
      rootView: UpdatesSidebarView(
        viewModel: viewModel, searchFocusController: SearchFocusController()))
    host.frame = NSRect(x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: 420)
    let window = NSWindow(
      contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(100))
    let table = try XCTUnwrap(host.descendant(of: NSTableView.self))
    let scroll = try XCTUnwrap(table.enclosingScrollView)
    table.selectRowIndexes(IndexSet(integer: 10), byExtendingSelection: false)
    table.scrollRowToVisible(10)
    window.makeFirstResponder(table)
    try await Task.sleep(for: .milliseconds(100))
    func presentedY() -> CGFloat {
      scroll.contentView.layer?.presentation()?.bounds.minY ?? scroll.contentView.bounds.minY
    }
    func press(_ key: UInt16) throws {
      let character = key == 125 ? "\u{F701}" : "\u{F700}"
      let event = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, characters: character, charactersIgnoringModifiers: character,
          isARepeat: true, keyCode: key))
      window.sendEvent(event)
    }
    try press(125)
    XCTAssertEqual(table.selectedRow, 11, "Selection must respond immediately.")
    XCTAssertTrue(viewModel.isKeyboardSelection, "Held arrows must coalesce release-note requests.")
    XCTAssertTrue(table.visibleRect.contains(table.rect(ofRow: 11)))
    var positions = [presentedY()]
    var largestOverlap: CGFloat = 0
    func paintedRow(_ index: Int) -> NSRect {
      var rect = table.rect(ofRow: index)
      if let layer = table.rowView(atRow: index, makeIfNecessary: false)?.layer {
        rect.origin.y += (layer.presentation()?.position.y ?? layer.position.y) - layer.position.y
      }
      return rect
    }
    for index in 0..<24 {
      try await Task.sleep(for: .milliseconds(8))
      positions.append(presentedY())
      largestOverlap = max(
        largestOverlap,
        paintedRow(table.selectedRow - 1).maxY - paintedRow(table.selectedRow).minY)
      if index == 3 { try press(125) }
    }
    XCTAssertLessThanOrEqual(
      largestOverlap, 0.5, "Selection must not cover the preceding row's version lines.")
    XCTAssertEqual(table.selectedRow, 12)
    XCTAssertEqual(viewModel.selectedApp?.identifier, apps[11].identifier)
    XCTAssertTrue(
      zip(positions, positions.dropFirst()).allSatisfy { $1 >= $0 - 0.5 },
      "Held Down must not restore an obsolete scroll position.")
    XCTAssertTrue(
      table.visibleRect.contains(table.rect(ofRow: 12)), "The final selected row must be visible.")

    // Reversing toward a row already in view stops the pending forward scroll.
    try press(125)
    try await Task.sleep(for: .milliseconds(16))
    try press(126)
    XCTAssertEqual(table.selectedRow, 12)
    let reversedPosition = presentedY()
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(
      presentedY(), reversedPosition, accuracy: 0.5,
      "Changing direction must not keep moving toward the previous selection.")

    // Programmatic navigation must remain stable after the keyboard event.
    try press(125)
    table.scrollRowToVisible(1)
    let interruptedPosition = scroll.contentView.bounds.origin.y
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(scroll.contentView.bounds.origin.y, interruptedPosition, accuracy: 0.5)

    // Filtering must not leave the viewport beyond rows that disappeared.
    table.selectRowIndexes(IndexSet(integer: 10), byExtendingSelection: false)
    table.scrollRowToVisible(10)
    try press(125)
    viewModel.setSearchQuery("App 00")
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(table.numberOfRows, 2)
    XCTAssertEqual(scroll.contentView.bounds.origin.y, 0, accuracy: 0.5)
    XCTAssertEqual(viewModel.selectedApp?.identifier, apps[0].identifier)
  }

  @MainActor
  func testDetailActionUsesRefreshedAppAtSameURL() async throws {
    let calls = Mutex([0, 0])
    let bundle = makeApp(name: "Example", version: "1").bundle
    let apps = ["2", "3"].enumerated().map { index, version in
      App(
        bundle: bundle,
        update: .success(
          App.Update(
            app: bundle,
            remoteVersion: Version(versionNumber: version, buildNumber: nil),
            minimumOSVersion: nil, source: .sparkle, date: nil, releaseNotes: nil,
            updateAction: .external(label: "Vendor") { _ in calls.withLock { $0[index] += 1 } })),
        isIgnored: false)
    }
    let host = NSHostingView(rootView: ReleaseNotesHeaderView(app: apps[0]))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 79),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    for app in apps {
      host.rootView = ReleaseNotesHeaderView(app: app)
      try await Task.sleep(for: .milliseconds(150))
      host.layoutSubtreeIfNeeded()
      let down = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: .leftMouseDown,
          location: NSPoint(x: 406.5, y: 46.5), modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
      let up = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: .leftMouseUp,
          location: down.locationInWindow, modifierFlags: [], timestamp: down.timestamp + 0.05,
          windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1,
          pressure: 0))
      NSApp.postEvent(up, atStart: false)
      window.sendEvent(down)
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(calls.withLock { $0[0] }, 1, "The old app's action must be retired")
    XCTAssertEqual(calls.withLock { $0[1] }, 1, "Use the refreshed app at the same URL")
  }

  @MainActor
  func testContextMenuPrefersClickedRowAndFallsBackToSelection() throws {
    let selectedApp = makeApp(name: "Discord", version: "1", remoteVersion: "2")
    let clickedApp = makeApp(name: "Cursor", version: "3")
    let snapshot = AppListSnapshot(withApps: [selectedApp, clickedApp], filterQuery: nil)
    let policy = SidebarInteractionPolicy(entries: snapshot.entries)
    let selectedRow = try XCTUnwrap(snapshot.firstIndex(of: selectedApp))
    let clickedRow = try XCTUnwrap(snapshot.firstIndex(of: clickedApp))
    let sectionRow = try XCTUnwrap(
      snapshot.entries.indices.first(where: policy.isSectionHeader(row:)))

    XCTAssertTrue(policy.targetApp(clickedRow: clickedRow, selectedRow: selectedRow) === clickedApp)
    XCTAssertTrue(
      policy.targetApp(clickedRow: sectionRow, selectedRow: selectedRow) === selectedApp)
    XCTAssertTrue(policy.targetApp(clickedRow: -1, selectedRow: selectedRow) === selectedApp)
  }

  @MainActor
  func testSwipeActionsPreserveAvailabilityRules() throws {
    let updatable = makeApp(name: "Discord", version: "1", remoteVersion: "2")
    let installed = makeApp(name: "Cursor", version: "3")
    let snapshot = AppListSnapshot(withApps: [updatable, installed], filterQuery: nil)
    let policy = SidebarInteractionPolicy(entries: snapshot.entries)
    let updatableRow = try XCTUnwrap(snapshot.firstIndex(of: updatable))
    let installedRow = try XCTUnwrap(snapshot.firstIndex(of: installed))
    let leadingActions: [SidebarInteractionPolicy.Action] = [.open, .revealInFinder]
    let trailingUpdateActions: [SidebarInteractionPolicy.Action] = [.update]

    XCTAssertEqual(policy.swipeActions(for: updatableRow, edge: .leading), leadingActions)
    XCTAssertEqual(policy.swipeActions(for: updatableRow, edge: .trailing), trailingUpdateActions)
    XCTAssertEqual(policy.swipeActions(for: installedRow, edge: .trailing), [])
  }

  @MainActor
  func testSidebarRowBuildsACombinedVoiceOverLabel() throws {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let app = makeApp(
      name: "Discord",
      version: "1",
      remoteVersion: "2",
      date: Date(timeIntervalSince1970: 1_750_000_000)
    )

    let row = UpdateRowHostingCell(frame: NSRect(x: 0, y: 0, width: 308, height: 60))
    row.update(app: app, isSelected: false, filterQuery: nil, dateFormatter: formatter)
    let label = try XCTUnwrap(row.accessibilityLabel())
    XCTAssertTrue(label.contains("Discord"))
    XCTAssertTrue(label.contains("1"))
    XCTAssertTrue(label.contains("2"))
    XCTAssertTrue(label.contains("2025-06-15"))
    XCTAssertTrue(label.contains(NSLocalizedString("UpdateAction", comment: "")))
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

  @MainActor
  func testReleaseNotesTextPreservesRichTextSelectionCopyAndAccessibility() async throws {
    let source = NSMutableAttributedString(string: "Bold link\tbody\nSecond paragraph")
    let fullRange = NSRange(location: 0, length: source.length)
    let linkRange = (source.string as NSString).range(of: "link")
    let originalParagraphStyle = NSMutableParagraphStyle()
    originalParagraphStyle.firstLineHeadIndent = 32
    originalParagraphStyle.headIndent = 24
    originalParagraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: 48)]
    source.addAttributes(
      [
        .font: NSFont.boldSystemFont(ofSize: 22),
        .backgroundColor: NSColor.systemYellow,
        .shadow: NSShadow(),
        .paragraphStyle: originalParagraphStyle,
      ], range: fullRange)
    source.addAttribute(.link, value: URL(string: "https://example.com/release")!, range: linkRange)

    let html = ReleaseNotesWebDocument.html(for: source)
    XCTAssertTrue(html.contains("<strong>"))
    XCTAssertFalse(html.contains("background-color"))
    XCTAssertFalse(html.contains("22px"))

    let hostingView = NSHostingView(rootView: ReleaseNotesWebView(text: source))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    defer { window.close() }
    window.orderFront(nil)
    hostingView.layoutSubtreeIfNeeded()
    let web = try XCTUnwrap(hostingView.descendant(of: WKWebView.self))
    try await waitForWebContent(web, containing: "Second paragraph")
    let href = try await web.evaluateJavaScript("document.querySelector('a').href") as? String
    XCTAssertEqual(href, "https://example.com/release")
    let selection =
      try await web.evaluateJavaScript(
        """
        var range = document.createRange(); range.selectNodeContents(document.querySelector('main'));
        window.getSelection().removeAllRanges(); window.getSelection().addRange(range);
        window.getSelection().toString();
        """) as? String
    XCTAssertEqual(selection, source.string.replacingOccurrences(of: "\t", with: " "))
    XCTAssertFalse(web.configuration.websiteDataStore.isPersistent)
    XCTAssertFalse(web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    XCTAssertFalse(web.allowsBackForwardNavigationGestures)
    XCTAssertFalse(web.allowsMagnification)
  }

  @MainActor
  func testReleaseNotesWebViewReusesRendererAndResetsScrollOnSelection() async throws {
    let short = NSAttributedString(string: "Short release notes")
    let long = NSAttributedString(
      string: Array(repeating: "Long release notes", count: 150)
        .joined(separator: "\n"))
    let host = NSHostingView(
      rootView: ReleaseNotesDetailSurface(app: nil, contentState: .text(long)))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    let web = try XCTUnwrap(host.descendant(of: WKWebView.self))
    try await waitForWebContent(web, containing: "Long release notes")
    _ = try await web.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight)")
    let scrolled = try await web.evaluateJavaScript("window.scrollY") as? Double
    XCTAssertGreaterThan(scrolled ?? 0, 0)
    _ = try await web.evaluateJavaScript("window.rendererReuseMarker = 42")
    host.rootView = ReleaseNotesDetailSurface(app: nil, contentState: .text(long))
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    let marker = try await web.evaluateJavaScript("window.rendererReuseMarker") as? Int
    XCTAssertEqual(marker, 42, "Unchanged notes must not reload the page")
    host.rootView = ReleaseNotesDetailSurface(app: nil, contentState: .loading)
    host.layoutSubtreeIfNeeded()
    XCTAssertTrue(host.descendant(of: WKWebView.self) === web)
    host.rootView = ReleaseNotesDetailSurface(app: nil, contentState: .text(short))
    window.setContentSize(NSSize(width: 360, height: 280))
    host.layoutSubtreeIfNeeded()
    try await waitForWebContent(web, containing: "Short release notes")
    XCTAssertTrue(host.descendant(of: WKWebView.self) === web)
    let top = try await web.evaluateJavaScript("window.scrollY") as? Double
    XCTAssertEqual(top, 0)
    let overflow =
      try await web.evaluateJavaScript(
        "document.documentElement.scrollWidth > window.innerWidth") as? Bool
    XCTAssertEqual(overflow, false)
  }

  func testReleaseNotesWebDocumentEscapesMarkupAndRejectsScriptLinks() {
    let text = NSMutableAttributedString(string: "<script>alert('x')</script> & notes")
    text.addAttribute(.link, value: "javascript:alert(1)", range: NSRange(location: 0, length: 8))
    let html = ReleaseNotesWebDocument.html(for: text)
    XCTAssertTrue(html.contains("&lt;script&gt;"))
    XCTAssertFalse(html.contains("<script>"))
    XCTAssertFalse(html.contains("href=\"javascript:"))
    XCTAssertTrue(html.contains("default-src 'none'"))
  }

  func testReleaseNotesSerializationPreservesUnicodeAndSharesLinkPolicy() {
    let source = NSAttributedString(string: "<&>\"\t👩🏽‍💻 e\u{301} 中文")
    let html = ReleaseNotesWebDocument.html(for: source)
    XCTAssertTrue(html.contains("&lt;&amp;&gt;&quot; 👩🏽‍💻 e\u{301} 中文"))
    for scheme in ["https", "http", "mailto"] {
      let link = "\(scheme):example.com"
      XCTAssertEqual(ReleaseNotesWebDocument.externalURL(link)?.absoluteString, link)
      XCTAssertEqual(ReleaseNotesWebDocument.externalURL(URL(string: link))?.absoluteString, link)
    }
    for link in ["javascript:alert(1)", "file:///etc/hosts", "data:text/html,test", "/relative"] {
      XCTAssertNil(ReleaseNotesWebDocument.externalURL(link))
    }
    XCTAssertNil(ReleaseNotesWebDocument.externalURL(nil))
  }

  @MainActor
  func testSidebarSupportPreferenceUpdatesExistingRows() async throws {
    let app = makeApp(name: "Example", version: "1")
    let model = UpdatesListViewModel(snapshot: AppListSnapshot(withApps: [app], filterQuery: nil))
    let host = NSHostingView(
      rootView: UpdatesTableBridge(viewModel: model, showsSupportStatusOverride: true))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 308, height: 400),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    let table = try XCTUnwrap(host.descendant(of: NSTableView.self))
    let row = try XCTUnwrap(model.snapshot.firstIndex(of: app))
    let cell = try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: true))
    for visible in [true, false, true] {
      host.rootView = UpdatesTableBridge(viewModel: model, showsSupportStatusOverride: visible)
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(100))
      let bitmap = try await captureWindowBitmap(window)
      let cellFrame = cell.convert(cell.bounds, to: nil)
      var greenPixels = 0
      for y in max(
        0, Int((window.frame.height - cellFrame.maxY) * 2))..<min(
          bitmap.pixelsHigh, Int((window.frame.height - cellFrame.minY) * 2))
      {
        for x in max(0, Int(cellFrame.minX * 2))..<min(bitmap.pixelsWide, Int(cellFrame.maxX * 2)) {
          let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
          if color.greenComponent - max(color.redComponent, color.blueComponent) > 0.2 {
            greenPixels += 1
          }
        }
      }
      if visible {
        XCTAssertGreaterThan(greenPixels, 20, "Supported app must paint the support dot")
      } else {
        XCTAssertEqual(greenPixels, 0, "Disabling support indicators must remove the painted dot")
      }
      XCTAssertTrue(table.view(atColumn: 0, row: row, makeIfNecessary: false) === cell)
    }
  }

  @MainActor
  private func waitForWebContent(_ web: WKWebView, containing text: String) async throws {
    let deadline = Date(timeIntervalSinceNow: 10)
    while Date() < deadline {
      if let body = try? await web.evaluateJavaScript("document.body.innerText") as? String,
        body.contains(text), !web.isLoading
      {
        return
      }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTFail("WebKit did not render expected content: \(text)")
  }

  @MainActor
  func testUpdateActionPresentationCoversEveryOperationState() {
    let updatable = makeApp(name: "Discord", version: "1", remoteVersion: "2")
    let installed = makeApp(name: "Cursor", version: "3")

    XCTAssertEqual(UpdateActionPresentation.make(for: updatable, progressState: .none), .update)
    XCTAssertEqual(UpdateActionPresentation.make(for: installed, progressState: .none), .open)
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .pending))
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .initializing))
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .installing))
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .cancelling))

    guard
      case .progress(let downloadFraction, let downloadStatus) = UpdateActionPresentation.make(
        for: updatable,
        progressState: .downloading(loadedSize: 25, totalSize: 100)
      )
    else {
      return XCTFail("Expected the download state to produce determinate progress.")
    }
    XCTAssertEqual(downloadFraction, 0.1875, accuracy: 0.0001)
    XCTAssertFalse(downloadStatus.isEmpty)

    guard
      case .progress(let extractionFraction, let extractionStatus) = UpdateActionPresentation.make(
        for: updatable,
        progressState: .extracting(progress: 0.5)
      )
    else {
      return XCTFail("Expected the extraction state to produce determinate progress.")
    }
    XCTAssertEqual(extractionFraction, 0.875, accuracy: 0.0001)
    XCTAssertFalse(extractionStatus.isEmpty)

    let error = NSError(
      domain: "LatestMigration", code: 7,
      userInfo: [
        NSLocalizedDescriptionKey: "The update failed"
      ])
    XCTAssertEqual(
      UpdateActionPresentation.make(for: updatable, progressState: .error(error)),
      .failed("The update failed")
    )
  }

  @MainActor
  func testRapidSelectionRequestsNotesOnlyForTheSettledApp() async throws {
    let provider = ReleaseNotesProviderProbe()
    let viewModel = ReleaseNotesDetailViewModel(releaseNotesProvider: provider)
    let first = makeApp(name: "Discord", version: "1", remoteVersion: "2")
    let second = makeApp(name: "Cursor", version: "3", remoteVersion: "4")

    viewModel.display(first, waitForSelectionToSettle: true)
    // The user's held keys repeat about every 83ms. Back-to-back calls hid
    // notes work that started between real repeat events.
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertTrue(provider.requests.isEmpty, "Held navigation must not fetch each passing row")
    viewModel.display(second, waitForSelectionToSettle: true)
    XCTAssertTrue(viewModel.app === second, "The header must follow selection immediately")
    XCTAssertTrue(provider.requests.isEmpty, "Passing a row must not start expensive notes work")
    let deadline = ContinuousClock.now + .seconds(1)
    while provider.requests.isEmpty && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(provider.requests.count, 1)
    XCTAssertTrue(provider.requests.last?.app === second)

    viewModel.display(first, waitForSelectionToSettle: true)
    viewModel.display(nil)
    try await Task.sleep(for: .milliseconds(250))
    XCTAssertEqual(provider.requests.count, 1, "Clearing selection must cancel queued notes work")
    guard case .message(let message) = viewModel.contentState else {
      return XCTFail("Expected no-selection content")
    }
    XCTAssertEqual(message, .noSelection)
  }

  @MainActor
  func testDetailViewModelOwnsLoadingSuccessEmptyErrorAndStaleRequestStates() async throws {
    let provider = ReleaseNotesProviderProbe()
    let viewModel = ReleaseNotesDetailViewModel(releaseNotesProvider: provider)
    let firstApp = makeApp(name: "Discord", version: "1", remoteVersion: "2")
    let secondApp = makeApp(name: "Cursor", version: "3", remoteVersion: "4")

    viewModel.display(firstApp)
    XCTAssertEqual(provider.requests.count, 1)
    try await Task.sleep(for: .milliseconds(230))
    guard case .loading = viewModel.contentState else {
      return XCTFail("Expected delayed loading state.")
    }

    let firstText = NSAttributedString(string: "First release notes")
    provider.completeRequest(at: 0, with: .success(firstText))
    guard case .text(let displayedText) = viewModel.contentState else {
      return XCTFail("Expected release notes text.")
    }
    XCTAssertEqual(displayedText.string, firstText.string)

    viewModel.display(secondApp)
    XCTAssertEqual(provider.requests.count, 2)
    provider.completeRequest(at: 0, with: .success(NSAttributedString(string: "Stale text")))
    guard case .text(let textAfterStaleCompletion) = viewModel.contentState else {
      return XCTFail("A stale request must not replace the current detail state.")
    }
    XCTAssertEqual(textAfterStaleCompletion.string, firstText.string)

    provider.completeRequest(at: 1, with: .success(NSAttributedString(string: "  \n")))
    guard case .message(let emptyMessage) = viewModel.contentState else {
      return XCTFail("Expected an empty release note response to become an unavailable message.")
    }
    XCTAssertEqual(emptyMessage.description, LatestError.releaseNotesUnavailable.failureReason)

    let thirdApp = makeApp(name: "Zed", version: "5", remoteVersion: "6")
    viewModel.display(thirdApp)
    provider.completeRequest(at: 2, with: .failure(LatestError.updateInfoUnavailable))
    guard case .message(let errorMessage) = viewModel.contentState else {
      return XCTFail("Expected provider failures to become detail messages.")
    }
    XCTAssertEqual(errorMessage.title, LatestError.updateInfoUnavailable.localizedDescription)
    XCTAssertEqual(errorMessage.description, LatestError.updateInfoUnavailable.failureReason)

    viewModel.display(nil)
    guard case .message(let noSelectionMessage) = viewModel.contentState else {
      return XCTFail("Expected the no-selection message.")
    }
    XCTAssertEqual(noSelectionMessage, .noSelection)
  }

  @MainActor
  func testShippingMenuValidatesSelectedAppActions() throws {
    let (window, table, viewModel) = try makeShippingSidebar()
    defer { window.close() }
    let menu = try XCTUnwrap(table.menu)
    for (row, entry) in viewModel.snapshot.entries.enumerated() {
      guard case .app(let app) = entry else { continue }
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      menu.update()
      let updateItem = try XCTUnwrap(
        menu.items.first { $0.action == NSSelectorFromString("updateApp:") })
      let ignoreItem = try XCTUnwrap(
        menu.items.first { $0.action == NSSelectorFromString("ignoreApp:") })
      let unignoreItem = try XCTUnwrap(
        menu.items.first { $0.action == NSSelectorFromString("unignoreApp:") })
      XCTAssertEqual(updateItem.isEnabled, app.updateAvailable)
      XCTAssertEqual(ignoreItem.isHidden, app.isIgnored)
      XCTAssertEqual(unignoreItem.isHidden, !app.isIgnored)
    }
  }

  @MainActor
  private func makeShippingSidebar() throws -> (NSWindow, NSTableView, UpdatesListViewModel) {
    let apps = [
      makeApp(name: "Discord", version: "1", remoteVersion: "2"),
      makeApp(name: "Cursor", version: "3"),
    ]
    let viewModel = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: apps, filterQuery: nil))
    let host = NSHostingView(
      rootView: UpdatesSidebarView(
        viewModel: viewModel, searchFocusController: SearchFocusController()))
    host.frame = NSRect(x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: 420)
    let window = NSWindow(
      contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    let table = try XCTUnwrap(host.descendant(of: NSTableView.self))
    XCTAssertTrue(table is SwiftUIUpdateTableView)
    return (window, table, viewModel)
  }

  private func assertWaiting(
    _ presentation: UpdateActionPresentation,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard case .waiting(let status) = presentation else {
      return XCTFail("Expected a waiting presentation.", file: file, line: line)
    }
    XCTAssertFalse(status.isEmpty, file: file, line: line)
  }

  @MainActor
  private func makeApp(
    name: String,
    version: String,
    remoteVersion: String? = nil,
    date: Date = Date(timeIntervalSince1970: 1_750_000_000)
  ) -> Latest.App {
    let bundle = Latest.App.Bundle(
      version: Version(versionNumber: version, buildNumber: nil),
      name: name,
      bundleIdentifier: "com.example.\(name.lowercased())",
      fileURL: URL(fileURLWithPath: "/Applications/\(name).app"),
      source: .appStore
    )
    let update = Latest.App.Update(
      app: bundle,
      remoteVersion: Version(versionNumber: remoteVersion ?? version, buildNumber: nil),
      minimumOSVersion: nil,
      source: .appStore,
      date: date,
      releaseNotes: .html(string: "<p>Release notes</p>"),
      updateAction: .builtIn { _ in }
    )
    return Latest.App(bundle: bundle, update: .success(update), isIgnored: false)
  }
}

@MainActor
private final class SelectionBox {
  var url: URL?
}

@MainActor
private final class ReleaseNotesProviderProbe: ReleaseNotesProviding {
  private(set) var requests: [(app: Latest.App, completion: ReleaseNotesProvider.Completion)] = []

  func releaseNotes(
    for app: Latest.App,
    with completion: @escaping ReleaseNotesProvider.Completion
  ) {
    requests.append((app, completion))
  }

  func completeRequest(at index: Int, with result: ReleaseNotesProvider.ReleaseNotes) {
    requests[index].completion(result)
  }
}

extension NSView {
  fileprivate func descendant<ViewType: NSView>(of type: ViewType.Type) -> ViewType? {
    if let match = self as? ViewType {
      return match
    }
    return subviews.lazy.compactMap { $0.descendant(of: type) }.first
  }

  fileprivate func allDescendants() -> [NSView] {
    subviews + subviews.flatMap { $0.allDescendants() }
  }
}

@MainActor
private final class HelperRegistrationFixture: InstallHelperServicing {
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
