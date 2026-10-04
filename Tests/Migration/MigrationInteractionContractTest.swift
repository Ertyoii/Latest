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
  func testSwiftUIHelperAlertMatchesOriginalSheetPixelsAndSuppression() async throws {
    try requireUITests()
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
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    defer { window.close() }
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
  func testSidebarSearchAcceptsTypingClearAndEscapeRestoresListFocus() throws {
    try requireUITests()
    try runApplicationTest {
      try await self.checkSwiftUISidebarSearch()
    }
  }

  @MainActor
  func testSearchEscapeRestoresReleaseNotesAfterRepeatedFindCommands() throws {
    try requireUITests()
    try runApplicationTest {
      try await self.checkSearchEscapeRestoresReleaseNotesAfterRepeatedFindCommands()
    }
  }

  @MainActor
  private func checkSearchEscapeRestoresReleaseNotesAfterRepeatedFindCommands() async throws {
    let environment = AppEnvironment.localUATFixture(
      settings: try isolatedAppListSettings(for: self))
    let window = try await makeLatestTestWindow(environment: environment, testCase: self)
    let host = try XCTUnwrap(window.contentView)
    defer { window.close() }
    let fixture = try SidebarInputFixture(window: window, model: environment.updatesListViewModel)
    try await fixture.activate()
    func waitForFocus(_ stage: String, _ condition: () -> Bool) async throws {
      for _ in 0..<100 {
        // AppKit may assign its field editor before SwiftUI commits the new
        // responder's key handlers. Require focus to survive a main-loop turn.
        if condition() {
          try await Task.sleep(for: .milliseconds(10))
          if condition() { return }
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      XCTFail(
        "Focus did not settle at \(stage); responder=\(String(describing: window.firstResponder)), key=\(window.isKeyWindow), active=\(NSApp.isActive)"
      )
      throw CocoaError(.coderInvalidValue)
    }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    let web = try XCTUnwrap(host.descendant(of: WKWebView.self))
    try await waitForWebContent(web, containing: "Offline acceptance fixture")
    func focusReleaseNotes() throws {
      let location = web.convert(NSPoint(x: 40, y: 40), to: nil)
      try clickTestWindow(window, at: location)
    }
    try focusReleaseNotes()
    try await waitForFocus("initial release notes") { window.firstResponder === web }
    environment.commands.focusSearch()
    let search = try XCTUnwrap(host.descendant(of: NSTextField.self))
    try await waitForFocus("first Find") { search.currentEditor() === window.firstResponder }
    XCTAssertTrue(search.currentEditor() === window.firstResponder)
    environment.commands.focusSearch()
    // Do not yield after repeated Find: a pending request must not steal focus
    // back after the immediately following Escape.
    XCTAssertTrue(search.currentEditor() === window.firstResponder)
    let escape = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
        characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
    window.sendEvent(escape)
    try await waitForFocus("Escape to release notes") { window.firstResponder === web }
    XCTAssertTrue(
      window.firstResponder === web, "Escape must return to the previously focused release notes")
    for listFocus in [true, false, true] {
      if listFocus { try fixture.focus() } else { try focusReleaseNotes() }
      // SwiftUI commits the click gesture after AppKit sends the mouse events.
      // Let that input finish before issuing the next keyboard command.
      try await Task.sleep(for: .milliseconds(50))
      let destination = window.firstResponder
      environment.commands.focusSearch()
      try await waitForFocus("Find from list=\(listFocus)") {
        search.currentEditor() === window.firstResponder
      }
      window.sendEvent(escape)
      try await waitForFocus("Escape to list=\(listFocus)") {
        window.firstResponder === destination
      }
      XCTAssertTrue(
        window.firstResponder === destination,
        "Escape must follow the latest focus destination when switching between list and notes")
    }
  }

  @MainActor
  func testHeldArrowNavigationKeepsRowsVisibleAndSeparate() throws {
    try requireUITests()
    try runApplicationTest {
      try await self.checkSwiftUISidebarNavigation()
    }
  }

  @MainActor
  func testDetailActionUsesRefreshedAppAtSameURL() async throws {
    try requireUITests()
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
  func testSidebarLayoutTargetsRowsAndExcludesSectionGaps() throws {
    let apps = [
      makeApp(name: "Alpha", version: "1", remoteVersion: "2"),
      makeApp(name: "Beta", version: "1", remoteVersion: "2"),
      makeApp(name: "Gamma", version: "1"),
    ]
    let snapshot = AppListSnapshot(
      withApps: apps, filterQuery: nil, settings: try isolatedAppListSettings(for: self))
    let layout = SidebarLayout(entries: snapshot.entries)
    XCTAssertEqual(layout.contentHeight, 254)
    // 27pt headers, 10pt gaps, and 60pt app rows are independent layout contracts.
    for (y, row) in [(0.0, 0), (37, 1), (96.9, 1), (97, 2), (157, 3), (194, 4), (253.9, 4)] {
      XCTAssertEqual(layout.row(at: y), row)
    }
    for y in [-1.0, 27, 36.9, 184, 193.9, 254, 1_000] {
      XCTAssertNil(layout.row(at: y))
    }
    let filtered = SidebarLayout(entries: snapshot.refiltered(with: "Gamma").entries)
    XCTAssertEqual(filtered.contentHeight, 97)
    XCTAssertEqual(filtered.row(at: 37), 1)
    XCTAssertNil(filtered.row(at: 194), "Filtered layouts must retire the former row positions")
    XCTAssertNil(SidebarLayout(entries: []).row(at: 0))
  }

  @MainActor
  func testSwipeActionsPreserveAvailabilityRules() throws {
    let updatable = makeApp(name: "Discord", version: "1", remoteVersion: "2")
    let installed = makeApp(name: "Cursor", version: "3")
    let policy = SidebarInteractionPolicy()
    let leadingActions: [SidebarInteractionPolicy.Action] = [.open, .revealInFinder]
    let trailingUpdateActions: [SidebarInteractionPolicy.Action] = [.update]

    XCTAssertEqual(policy.swipeActions(for: updatable, edge: .leading), leadingActions)
    XCTAssertEqual(policy.swipeActions(for: updatable, edge: .trailing), trailingUpdateActions)
    XCTAssertEqual(policy.swipeActions(for: installed, edge: .trailing), [])

    let queue = UpdateQueue()
    queue.isSuspended = true
    defer {
      queue.cancelAllOperations()
      queue.isSuspended = false
    }
    queue.addOperation(
      UpdateOperation(
        bundleIdentifier: updatable.bundleIdentifier, appIdentifier: updatable.identifier))
    let queued = SidebarInteractionPolicy(updating: AppUpdateService(queue: queue))
    XCTAssertEqual(queued.swipeActions(for: updatable, edge: .trailing), [])
    XCTAssertEqual(queued.swipeActions(for: updatable, edge: .leading), leadingActions)
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

    let row = UpdateRowView(
      app: app, selection: UpdateRowSelection(),
      date: formatter.string(from: app.updateDate), showsSupportStatus: true,
      updating: AppUpdateService(queue: UpdateQueue()))
    let label = row.accessibilityLabel
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
    try requireUITests()
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

    let html = ReleaseNotesWebDocument.html(for: ReleaseNotesLegacyBridge.content(from: source))
    XCTAssertTrue(html.contains("<strong>"))
    XCTAssertFalse(html.contains("background-color"))
    XCTAssertFalse(html.contains("22px"))

    let hostingView = NSHostingView(
      rootView: ReleaseNotesWebView(text: ReleaseNotesLegacyBridge.content(from: source)))
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
    try requireUITests()
    let firstApp = makeApp(name: "First app", version: "1", remoteVersion: "2")
    let secondApp = makeApp(name: "Second app", version: "3", remoteVersion: "4")
    let short = ReleaseNotesContent(string: "Short release notes")
    let long = ReleaseNotesContent(
      string: Array(repeating: "Long release notes", count: 150)
        .joined(separator: "\n"))
    let host = NSHostingView(
      rootView: ReleaseNotesDetailSurface(app: firstApp, contentState: .text(long)))
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
    _ = try await web.evaluateJavaScript(
      """
      window.rendererReuseMarker = 42;
      var range = document.createRange();
      range.selectNodeContents(document.querySelector('main'));
      window.getSelection().removeAllRanges(); window.getSelection().addRange(range);
      """)
    // Held arrows change the header while the previous notes remain displayed.
    host.rootView = ReleaseNotesDetailSurface(app: secondApp, contentState: .text(long))
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    let marker = try await web.evaluateJavaScript("window.rendererReuseMarker") as? Int
    XCTAssertEqual(marker, 42, "Unchanged notes must not reload the page")
    let retainedScroll = try await web.evaluateJavaScript("window.scrollY") as? Double
    XCTAssertEqual(retainedScroll, scrolled, "Header selection must preserve notes scroll position")
    let retainedSelection =
      try await web.evaluateJavaScript("window.getSelection().toString()") as? String
    XCTAssertEqual(retainedSelection, long.string, "Header selection must preserve text selection")
    // A different selection can have identical text. Its new content identity
    // must still reset scroll while the same content object above stays loaded.
    host.rootView = ReleaseNotesDetailSurface(
      app: secondApp, contentState: .text(ReleaseNotesContent(string: long.string)))
    host.layoutSubtreeIfNeeded()
    var reloaded = false
    for _ in 0..<100 {
      reloaded =
        (try await web.evaluateJavaScript("typeof window.rendererReuseMarker === 'undefined'")
          as? Bool) == true
      if reloaded { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTAssertTrue(reloaded, "Distinct notes with equal text must reload the page")
    let equalTextScroll = try await web.evaluateJavaScript("window.scrollY") as? Double
    XCTAssertEqual(equalTextScroll, 0)
    host.rootView = ReleaseNotesDetailSurface(app: secondApp, contentState: .loading)
    host.layoutSubtreeIfNeeded()
    XCTAssertTrue(host.descendant(of: WKWebView.self) === web)
    host.rootView = ReleaseNotesDetailSurface(app: secondApp, contentState: .text(short))
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
    let html = ReleaseNotesWebDocument.html(for: ReleaseNotesLegacyBridge.content(from: text))
    XCTAssertTrue(html.contains("&lt;script&gt;"))
    XCTAssertFalse(html.contains("<script>"))
    XCTAssertFalse(html.contains("href=\"javascript:"))
    XCTAssertTrue(html.contains("default-src 'none'"))
  }

  func testReleaseNotesSerializationPreservesUnicodeAndSharesLinkPolicy() {
    let source = ReleaseNotesContent(string: "<&>\"\t👩🏽‍💻 e\u{301} 中文")
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
    try requireUITests()
    let app = makeApp(name: "Example", version: "1")
    let suite = "SidebarSupport.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppListSettings(userDefaults: defaults)
    settings.showInstalledUpdates = true
    let store = AppDataStore(userDefaults: defaults)
    _ = store.set(appBundle: app.bundle)
    let model = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: [app], filterQuery: nil, settings: settings),
      settings: settings, appProvider: store)
    model.startObserving()
    defer { model.stopObserving() }
    let environment = AppEnvironment(settings: settings, updatesListViewModel: model)
    let window = try await makeLatestTestWindow(environment: environment, testCase: self)
    defer { window.close() }
    let fixture = try SidebarInputFixture(window: window, model: model)
    for visible in [true, false, true] {
      settings.includeAppsWithLimitedSupport = visible
      settings.includeUnsupportedApps = visible
      try await Task.sleep(for: .milliseconds(150))
      let bitmap = try await fixture.captureRow(for: app)
      var greenPixels = 0
      // Only the production status control, excluding the application's icon.
      for y in 35..<83 {
        for x in 502..<555 {
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
      XCTAssertEqual(model.snapshot.apps.map(\.identifier), [app.identifier])
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
  func testKeyboardSelectionCancelsStaleNotesAndRetriesWhenReturning() async throws {
    let provider = ReleaseNotesProviderProbe()
    let model = ReleaseNotesDetailViewModel(releaseNotesProvider: provider)
    let first = makeApp(name: "First", version: "1", remoteVersion: "2")
    let second = makeApp(name: "Second", version: "3", remoteVersion: "4")
    model.display(first)
    model.display(second, waitForSelectionToSettle: true)
    provider.completeRequest(at: 0, with: .success(ReleaseNotesContent(string: "Stale notes")))
    guard case .message(.noSelection) = model.contentState else {
      return XCTFail("A pending keyboard selection must reject the previous request's result")
    }
    model.display(first, waitForSelectionToSettle: true)
    let deadline = ContinuousClock.now + .seconds(1)
    while provider.requests.count < 2 && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(provider.requests.count, 2, "Returning must retry the cancelled request")
    guard provider.requests.count == 2 else { return }
    XCTAssertTrue(provider.requests[1].app === first)
    let notes = ReleaseNotesContent(string: "Current notes")
    provider.completeRequest(at: 1, with: .success(notes))
    let refreshed = makeApp(name: "First", version: "1", remoteVersion: "2")
    model.display(refreshed)
    XCTAssertTrue(model.app === refreshed, "Equivalent notes must not suppress refreshed metadata")
    XCTAssertEqual(provider.requests.count, 2, "A completed result with the same key can be reused")
    guard case .text(let displayed) = model.contentState else {
      return XCTFail("Expected current notes")
    }
    XCTAssertTrue(displayed === notes)
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

    let firstText = ReleaseNotesContent(string: "First release notes")
    provider.completeRequest(at: 0, with: .success(firstText))
    guard case .text(let displayedText) = viewModel.contentState else {
      return XCTFail("Expected release notes text.")
    }
    XCTAssertEqual(displayedText.string, firstText.string)

    viewModel.display(secondApp)
    XCTAssertEqual(provider.requests.count, 2)
    provider.completeRequest(at: 0, with: .success(ReleaseNotesContent(string: "Stale text")))
    guard case .text(let textAfterStaleCompletion) = viewModel.contentState else {
      return XCTFail("A stale request must not replace the current detail state.")
    }
    XCTAssertEqual(textAfterStaleCompletion.string, firstText.string)

    provider.completeRequest(at: 1, with: .success(ReleaseNotesContent(string: "  \n")))
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
