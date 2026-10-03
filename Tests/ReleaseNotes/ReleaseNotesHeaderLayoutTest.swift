//
//  ReleaseNotesHeaderLayoutTest.swift
//  Latest Tests
//
//  Created by ertyoii on 11.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-11.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import ScreenCaptureKit
import SwiftUI
import XCTest

@testable import Latest

final class ReleaseNotesHeaderLayoutTest: XCTestCase {
  @MainActor
  func testUnitTestsUseIsolatedApplicationLifecycle() {
    XCTAssertTrue(ApplicationRuntime.isRunningUnitTests)
    if ProcessInfo.processInfo.environment["LATEST_UI_TESTS"] != "1" {
      XCTAssertEqual(NSApp.activationPolicy(), .prohibited)
      XCTAssertFalse(NSApp.isActive, "Background tests must not activate over another app")
    }
  }
  @MainActor
  func testSwiftUIDetailHeaderKeepsFixedProductionGeometry() {
    let app = makeApp(
      name: "Zed",
      version: "1.10.0",
      remoteVersion: "1.10.2",
      updateAction: .external(label: "Zed") { _ in }
    )
    let hostingView = NSHostingView(rootView: ReleaseNotesHeaderView(app: app))
    hostingView.frame = NSRect(x: 0, y: 0, width: VisualMetrics.detailMinWidth, height: 200)
    hostingView.layoutSubtreeIfNeeded()

    XCTAssertEqual(hostingView.fittingSize.height, VisualMetrics.detailHeaderHeight, accuracy: 0.5)
    XCTAssertEqual(VisualMetrics.detailHeaderHeight, 79)
    XCTAssertEqual(VisualMetrics.detailIconSize, 64)
    XCTAssertEqual(VisualMetrics.detailHeaderVerticalPadding, 7.5)
    XCTAssertEqual(VisualMetrics.detailHeaderHorizontalPadding, 24)
    XCTAssertEqual(VisualMetrics.detailMetadataVerticalOffset, -7)
    XCTAssertEqual(VisualMetrics.detailMetadataLineVerticalCorrection, 1)
    XCTAssertEqual(VisualMetrics.detailTitleVerticalCorrection, 0)
    XCTAssertEqual(VisualMetrics.supportStatusHorizontalCorrection, -1)
    XCTAssertEqual(VisualMetrics.detailUpdateButtonWidth, 59)
    XCTAssertEqual(VisualMetrics.detailUpdateButtonHeight, 24)
  }

  @MainActor
  func testOptionalDatePreservesTwoLineHeaderAlignment() throws {
    func render(date: Date?) throws -> NSBitmapImageRep {
      let app = makeApp(name: "Example", version: "1.0", date: date)
      let host = NSHostingView(
        rootView: ReleaseNotesHeaderView(app: app, showsSupportStatus: false))
      host.appearance = NSAppearance(named: .aqua)
      host.frame = NSRect(x: 0, y: 0, width: 460, height: VisualMetrics.detailHeaderHeight)
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      return bitmap
    }

    let twoLines = try render(date: nil)
    let threeLines = try render(date: Date(timeIntervalSince1970: 1_750_000_000))
    XCTAssertEqual(twoLines.pixelsWide, threeLines.pixelsWide)
    XCTAssertEqual(twoLines.pixelsHigh, threeLines.pixelsHigh)
    let scale = CGFloat(twoLines.pixelsWide) / 460
    var changedAboveDate = 0
    var changedBelowVersion = 0
    // Compare the actual title/version pixels, excluding the asynchronously loaded icon.
    for y in 0..<twoLines.pixelsHigh {
      for x in Int(94 * scale)..<Int(260 * scale) {
        if twoLines.colorAt(x: x, y: y) != threeLines.colorAt(x: x, y: y) {
          if CGFloat(y) / scale < 45 {
            changedAboveDate += 1
          } else {
            changedBelowVersion += 1
          }
        }
      }
    }
    XCTAssertEqual(changedAboveDate, 0, "Adding a date must not move the title or version")
    XCTAssertGreaterThan(changedBelowVersion, 0, "The date must remain visible below the version")
  }

  @MainActor
  func testLocationsLabelKeepsOriginalAsymmetricAlignment() {
    XCTAssertEqual(VisualMetrics.locationsLabelOffset, CGSize(width: -2, height: 1))
  }

  @MainActor
  func testToolbarProgressTrackHasFixedWidthAndClampsItsValue() {
    XCTAssertEqual(ToolbarProgressMetrics.width, 64)
    XCTAssertGreaterThanOrEqual(ToolbarProgressMetrics.leadingPadding, 8)
    XCTAssertEqual(ToolbarProgressMetrics.leadingPadding, ToolbarProgressMetrics.trailingPadding)
    XCTAssertEqual(ToolbarProgressMetrics.normalized(-0.25), 0)
    XCTAssertEqual(ToolbarProgressMetrics.normalized(0.5), 0.5)
    XCTAssertEqual(ToolbarProgressMetrics.normalized(1.25), 1)
    XCTAssertEqual(ToolbarProgressPresentation(isRunning: false, fraction: 0.5), .hidden)
    XCTAssertEqual(ToolbarProgressPresentation(isRunning: true, fraction: nil), .determinate(0))
    XCTAssertEqual(ToolbarProgressPresentation(isRunning: true, fraction: -0.25), .determinate(0))
    XCTAssertEqual(ToolbarProgressPresentation(isRunning: true, fraction: 1.25), .determinate(1))
  }

  @MainActor
  func testToolbarTitleIsVisibleInHostedMainWindow() async throws {
    try requireUITests()
    let environment = AppEnvironment.localUATFixture(
      settings: try isolatedAppListSettings(for: self))
    let window = try await makeLatestTestWindow(
      environment: environment, dark: true, testCase: self)
    let host = try XCTUnwrap(window.contentView)
    defer { window.close() }
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()

    let bitmap = try await captureWindowBitmap(window)
    let scale = CGFloat(bitmap.pixelsWide) / window.frame.width
    let titleStart = VisualMetrics.sidebarIdealWidth + VisualMetrics.detailHeaderHorizontalPadding
    let titleRegion = NSRect(x: titleStart - 4, y: 14, width: 100, height: 26)
    var brightPixels = 0
    var leftmostBrightPixel = bitmap.pixelsWide
    for y in Int(titleRegion.minY * scale)..<Int(titleRegion.maxY * scale) {
      for x in Int(titleRegion.minX * scale)..<Int(titleRegion.maxX * scale) {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
          color.brightnessComponent > 0.55
        else { continue }
        brightPixels += 1
        leftmostBrightPixel = min(leftmostBrightPixel, x)
      }
    }
    XCTAssertGreaterThan(brightPixels, 25, "Updates must be painted in the titlebar")
    XCTAssertLessThan(
      CGFloat(leftmostBrightPixel) / scale, titleStart + 20,
      "The title should align with the detail panel")
  }

  @MainActor
  func testSidebarTableDoesNotShiftItsSelectionTowardTheRight() {
    let scroll = LockedHorizontalScrollView(frame: NSRect(x: 0, y: 0, width: 308, height: 400))
    let table = SwiftUIUpdateTableView(frame: scroll.bounds)
    table.style = .sourceList
    scroll.documentView = table
    for width in [308.0, 360.0] {
      scroll.setFrameSize(NSSize(width: width, height: 400))
      table.setFrameOrigin(NSPoint(x: 4, y: 0))
      table.layout()
      XCTAssertEqual(table.frame.minX, 0)
      XCTAssertEqual(table.frame.maxX, scroll.contentSize.width, accuracy: 0.5)
    }
  }

  @MainActor
  func testMainWindowHasNoFloatingSidebarGlass() throws {
    try requireUITests()
    let environment = AppEnvironment.localUATFixture(
      settings: try isolatedAppListSettings(for: self))
    let hostingView = NSHostingView(rootView: LatestRootView(environment: environment))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 768, height: 516),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    defer { window.close() }
    window.orderFront(nil)

    window.layoutIfNeeded()
    hostingView.layoutSubtreeIfNeeded()
    for size in [NSSize(width: 768, height: 516), NSSize(width: 1000, height: 700)] {
      window.setContentSize(size)
      window.layoutIfNeeded()
      hostingView.layoutSubtreeIfNeeded()
      XCTAssertFalse(
        hostingView.descendantGlassEffects().contains {
          $0.bounds.height >= VisualMetrics.mainWindowMinHeight
        },
        "The sidebar must remain attached, without a floating glass surface."
      )
    }
  }

  @MainActor
  func testSectionHeadersNeverAcquireSelectionHighlight() {
    let row = SidebarSectionRowView()
    row.selectionHighlightStyle = .regular
    row.isSelected = true
    XCTAssertEqual(row.selectionHighlightStyle, .none)
    XCTAssertFalse(row.isSelected)
  }

  @MainActor
  func testRefreshButtonHonorsEnabledStateForMouseInput() async throws {
    try requireUITests()
    for enabled in [true, false] {
      var calls = 0
      let host = NSHostingView(
        rootView: RefreshToolbarButton(isEnabled: enabled) { calls += 1 }
          .frame(width: 160, height: 80))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 160, height: 80),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      window.orderFront(nil)
      defer { window.close() }
      try await Task.sleep(for: .milliseconds(100))
      host.layoutSubtreeIfNeeded()
      let down = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: .leftMouseDown,
          location: NSPoint(x: 80, y: 40), modifierFlags: [],
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
      XCTAssertEqual(calls, enabled ? 1 : 0)
    }
  }

  @MainActor
  func testToolbarReloadRoutesThroughAppCommands() {
    let updateChecking = UpdateCheckingCommandSpy()
    let commands = AppCommands(
      updateCheckingService: updateChecking,
      updatesListViewModel: UpdatesListViewModel(),
      searchFocusController: SearchFocusController()
    )

    commands.reload()

    XCTAssertEqual(updateChecking.checkForUpdatesCount, 1)
  }

  @MainActor
  func testUpdateCheckFailureUsesCompactReleaseNotesEmptyState() {
    let bundle = Latest.App.Bundle(
      version: Version(versionNumber: "26.707.51957", buildNumber: nil),
      name: "ChatGPT",
      bundleIdentifier: "com.openai.codex",
      fileURL: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
      source: .sparkle
    )
    let app = Latest.App(
      bundle: bundle, update: .failure(LatestError.updateInfoUnavailable), isIgnored: false)
    let viewModel = ReleaseNotesDetailViewModel()

    viewModel.display(app)

    guard case .message(let message) = viewModel.contentState else {
      return XCTFail(
        "Expected the provider to map update-check failures to a release-notes message.")
    }
    XCTAssertEqual(message.title, NSLocalizedString("ReleaseNotesUnavailableError", comment: ""))
    XCTAssertEqual(
      message.description,
      NSLocalizedString("ReleaseNotesUnavailableErrorFailureReason", comment: ""))
    XCTAssertNotEqual(
      message.description, NSLocalizedString("UpdateInfoUnavailableErrorFailureReason", comment: "")
    )
  }

  func testSparkleChecksHaveABoundedDeadline() {
    XCTAssertGreaterThan(SparkleUpdateCheckerOperation.checkTimeout, 0)
    XCTAssertLessThanOrEqual(SparkleUpdateCheckerOperation.checkTimeout, 10)
  }

  @MainActor
  func testSidebarShowsLongInstalledVersionWithoutTruncationAtIdealWidth() async throws {
    try requireUITests()
    let app = makeApp(name: "Chrome", version: "151.0.7922.109")
    let expectedVersion = try XCTUnwrap(app.localizedVersionInformation?.current)
    let fixture = try await SidebarInputFixture.make(apps: [app], testCase: self)
    defer { fixture.window.close() }
    let bitmap = try await fixture.captureRow(for: app)
    let referenceBitmap = try nativeVersionReference(expectedVersion)
    var missingGlyphPixels = 0
    var glyphPixels = 0
    let backing = try XCTUnwrap(bitmap.colorAt(x: 600, y: 0)?.usingColorSpace(.deviceRGB))
      .redComponent
    for y in 62..<90 {
      for x in 116..<540 {
        let reference = try XCTUnwrap(
          referenceBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        guard reference.alphaComponent > 0.15 else { continue }
        glyphPixels += 1
        // Text and NSTextField may snap coverage to adjacent pixels. Require
        // every native glyph pixel to have matching ink within one pixel.
        var foundInk = false
        for dy in -1...1 {
          for dx in -1...1 {
            let actual = try XCTUnwrap(
              bitmap.colorAt(x: x + dx, y: y + dy)?.usingColorSpace(.deviceRGB))
            if backing - actual.redComponent > 0.08 { foundInk = true }
          }
        }
        if !foundInk { missingGlyphPixels += 1 }
      }
    }
    XCTAssertGreaterThan(
      glyphPixels, 100, "Native text reference must contain the complete version")
    XCTAssertEqual(
      missingGlyphPixels, 0,
      "The installed version must paint every glyph in the complete native reference")
  }

  @MainActor
  func testSidebarTextColorsFollowSelectionEmphasis() throws {
    try requireUITests()
    try runApplicationTest { try await self.checkSidebarTextColorsFollowSelectionEmphasis() }
  }

  @MainActor
  private func checkSidebarTextColorsFollowSelectionEmphasis() async throws {
    let app = makeApp(name: "Discord", version: "0.0.398", remoteVersion: "0.0.399")
    let search = SearchFocusController()
    let fixture = try await SidebarInputFixture.make(
      apps: [app], selected: app, searchFocusController: search, testCase: self)
    defer { fixture.window.close() }
    try await fixture.activate()
    try fixture.click(row: XCTUnwrap(fixture.model.snapshot.firstIndex(of: app)))
    for emphasized in [true, false] {
      if !emphasized {
        // Transfer actual focus within the same production scene. Calling
        // resignKey on a newly opened window did not establish this state.
        search.focus()
        let deadline = ContinuousClock.now + .seconds(1)
        while !(fixture.window.firstResponder is NSTextView) && ContinuousClock.now < deadline {
          try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(fixture.window.firstResponder is NSTextView, "Search must own keyboard focus")
      }
      try await Task.sleep(for: .milliseconds(100))
      let bitmap = try await fixture.captureRow(for: app)
      var expectedGlyphPixels = 0
      let backing = try XCTUnwrap(bitmap.colorAt(x: 440, y: 104)?.usingColorSpace(.sRGB))
      for y in 18..<46 {
        for x in 116..<220 {
          let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
          // The real system label is not absolute black. Check its contrast
          // with the selection fill in one color space, not device-RGB values.
          let contrast =
            emphasized
            ? color.redComponent - backing.redComponent
            : backing.redComponent - color.redComponent
          if contrast > 0.4 {
            expectedGlyphPixels += 1
          }
        }
      }
      if expectedGlyphPixels <= 50 {
        let attachment = XCTAttachment(
          image: NSImage(cgImage: try XCTUnwrap(bitmap.cgImage), size: bitmap.size))
        attachment.name = "production-row-emphasis-\(emphasized)"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
      XCTAssertGreaterThan(
        expectedGlyphPixels, 50, "Incorrect title color with emphasis=\(emphasized)")
    }
  }

  @MainActor
  private func nativeVersionReference(_ version: String) throws -> NSBitmapImageRep {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 308, height: 60))
    host.appearance = NSAppearance(named: .aqua)
    let reference = NSTextField(labelWithString: version)
    reference.font = NSFont.systemFont(ofSize: 11)
    reference.textColor = .secondaryLabelColor
    // NSTextField has 2pt of leading padding relative to the production Text.
    reference.frame = NSRect(x: 56, y: 15, width: 216, height: 14)
    host.addSubview(reference)
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 616, pixelsHigh: 120,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.frame.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return bitmap
  }

  private func makeApp(
    name: String,
    version: String,
    remoteVersion: String? = nil,
    date: Date? = Date(),
    updateAction: Latest.App.Update.Action = .builtIn { _ in }
  ) -> Latest.App {
    let bundle = Latest.App.Bundle(
      version: Version(versionNumber: version, buildNumber: nil),
      name: name,
      bundleIdentifier: "com.example.\(name.replacingOccurrences(of: " ", with: "-"))",
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
      updateAction: updateAction
    )
    return Latest.App(bundle: bundle, update: .success(update), isIgnored: false)
  }

}

@MainActor
private final class UpdateCheckingCommandSpy: UpdateCheckingCommandHandling {
  private(set) var checkForUpdatesCount = 0
  private(set) var updateAllCount = 0

  func checkForUpdates() {
    checkForUpdatesCount += 1
  }

  func updateAll() {
    updateAllCount += 1
  }
}

extension NSView {
  fileprivate func descendantGlassEffects() -> [NSGlassEffectView] {
    subviews.flatMap { view -> [NSGlassEffectView] in
      let current = (view as? NSGlassEffectView).map { [$0] } ?? []
      return current + view.descendantGlassEffects()
    }
  }

}
