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
import SwiftUI
import XCTest

@testable import Latest

final class ReleaseNotesHeaderLayoutTest: XCTestCase {
  func testUnitTestsUseIsolatedApplicationLifecycle() {
    XCTAssertTrue(ApplicationRuntime.isRunningUnitTests)
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
  func testUpdateActionKeepsOriginalDrawingMetrics() throws {
    XCTAssertEqual(UpdateActionVisualStyle.capsuleHorizontalInset, 0.25)
    XCTAssertEqual(UpdateActionVisualStyle.progressDiameter, 20)
    XCTAssertEqual(UpdateActionVisualStyle.progressLineWidth, 2.5)
    XCTAssertEqual(UpdateActionVisualStyle.pauseBarSize, CGSize(width: 2, height: 8))
    XCTAssertEqual(UpdateActionVisualStyle.pauseBarSpacing, 2)

    let background = try XCTUnwrap(UpdateActionVisualStyle.backgroundColor.usingColorSpace(.sRGB))
    XCTAssertEqual(background.redComponent, 0.9488552213, accuracy: 0.0001)
    XCTAssertEqual(background.greenComponent, 0.9487094283, accuracy: 0.0001)
    XCTAssertEqual(background.blueComponent, 0.9693081975, accuracy: 0.0001)
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
    XCTAssertNotEqual(
      ToolbarProgressMetrics.determinateIdentity,
      ToolbarProgressMetrics.indeterminateIdentity
    )
    XCTAssertEqual(ToolbarProgressPresentation(isRunning: false, fraction: 0.5), .hidden)
    XCTAssertEqual(ToolbarProgressPresentation(isRunning: true, fraction: nil), .indeterminate)
    XCTAssertEqual(ToolbarProgressPresentation(isRunning: true, fraction: -0.25), .determinate(0))
    XCTAssertEqual(ToolbarProgressPresentation(isRunning: true, fraction: 1.25), .determinate(1))
  }

  @MainActor
  func testMainWindowConfigurationUsesPublicWindowBehaviorWithoutMutatingContent() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 768, height: 516),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    let sentinelView = NSView(frame: NSRect(x: 8, y: 8, width: 40, height: 40))
    let contentView = try XCTUnwrap(window.contentView)
    contentView.addSubview(sentinelView)
    let subviewsBeforeConfiguration = contentView.subviews

    MainWindowConfiguration.apply(to: window)

    XCTAssertEqual(window.titlebarSeparatorStyle, .none)
    XCTAssertEqual(contentView.subviews, subviewsBeforeConfiguration)
    XCTAssertTrue(contentView.subviews.contains { $0 === sentinelView })
  }

  @MainActor
  func testToolbarTitleStaysAlignedAndCleansUp() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 768, height: 516),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.toolbar = NSToolbar(identifier: "title-test")
    defer { window.close() }
    let accessor = ToolbarTitleView()
    let content = try XCTUnwrap(window.contentView)
    accessor.frame = content.bounds
    accessor.autoresizingMask = [.width, .height]
    content.addSubview(accessor)
    for width in [768.0, 1000.0] {
      window.setContentSize(NSSize(width: width, height: 516))
      window.layoutIfNeeded()
      accessor.updateTitle()
      let title = try XCTUnwrap(
        accessor.subviews.compactMap { $0 as? NSTextField }.first {
          $0.accessibilityIdentifier() == "toolbar.title"
        })
      XCTAssertEqual(title.stringValue, "Updates")
      XCTAssertEqual(
        title.convert(title.bounds, to: nil).minX,
        VisualMetrics.sidebarIdealWidth + VisualMetrics.detailHeaderHorizontalPadding)
      XCTAssertNil(title.hitTest(.zero))
    }
    accessor.removeTitle()
    XCTAssertFalse(accessor.subviews.contains { $0.accessibilityIdentifier() == "toolbar.title" })
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
    let search = try XCTUnwrap(
      hostingView.descendantTextFields().compactMap { $0 as? NSSearchField }.first)
    XCTAssertTrue(search.isEditable)
    XCTAssertTrue(search.isSelectable)
    search.stringValue = "Notes"
    search.sendAction(search.action, to: search.target)
    XCTAssertEqual(environment.updatesListViewModel.searchQuery, "Notes")

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
  func testSwiftUIRefreshToolbarButtonRunsActionAndExposesAccessibilityContract() {
    var invocationCount = 0
    let button = RefreshToolbarButton(isEnabled: true) {
      invocationCount += 1
    }

    XCTAssertTrue(button.isEnabled)
    XCTAssertEqual(RefreshToolbarButton.accessibilityIdentifier, "toolbar.refresh")
    XCTAssertEqual(RefreshToolbarButton.accessibilityLabel, "Check for Updates")
    XCTAssertNotNil(
      NSImage(
        systemSymbolName: RefreshToolbarButton.systemImageName,
        accessibilityDescription: RefreshToolbarButton.accessibilityLabel
      ))
    button.performAction()
    XCTAssertEqual(invocationCount, 1)
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
  func testSidebarShowsLongInstalledVersionWithoutTruncationAtIdealWidth() throws {
    let app = makeApp(name: "Chrome", version: "151.0.7922.109")
    let expectedVersion = try XCTUnwrap(app.localizedVersionInformation?.current)
    let row = AppKitUpdateRowContentView(
      frame: NSRect(
        x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: VisualMetrics.appRowHeight))
    row.update(app: app, isSelected: false, filterQuery: nil, dateFormatter: DateFormatter())
    row.layoutSubtreeIfNeeded()
    let field = try XCTUnwrap(
      row.descendantTextFields().first { $0.stringValue == expectedVersion })
    XCTAssertFalse(field.isHidden)
    XCTAssertGreaterThanOrEqual(field.bounds.width + 0.5, field.intrinsicContentSize.width)
  }

  @MainActor
  func testAppKitSidebarTextColorsFollowSelectionEmphasis() throws {
    let row = AppKitUpdateRowContentView(
      frame: NSRect(
        x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: VisualMetrics.appRowHeight)
    )
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .short
    dateFormatter.timeStyle = .none
    let app = makeApp(name: "Discord", version: "0.0.398", remoteVersion: "0.0.399")

    row.update(app: app, isSelected: true, filterQuery: nil, dateFormatter: dateFormatter)
    row.backgroundStyle = .emphasized

    let fields = row.descendantTextFields()
    let nameField = try XCTUnwrap(fields.first(where: { $0.stringValue == "Discord" }))
    let activeTitleColor = try XCTUnwrap(
      nameField.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil)
        as? NSColor
    )
    XCTAssertEqual(activeTitleColor, .alternateSelectedControlTextColor)
    for field in fields where field !== nameField {
      XCTAssertEqual(field.textColor, .alternateSelectedControlTextColor)
    }

    row.backgroundStyle = .normal

    let inactiveTitleColor = try XCTUnwrap(
      nameField.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil)
        as? NSColor
    )
    XCTAssertEqual(inactiveTitleColor, .labelColor)
    for field in fields where field !== nameField {
      XCTAssertEqual(field.textColor, .secondaryLabelColor)
    }
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

  fileprivate func descendantTextFields() -> [NSTextField] {
    subviews.flatMap { view -> [NSTextField] in
      let current = (view as? NSTextField).map { [$0] } ?? []
      return current + view.descendantTextFields()
    }
  }

  fileprivate func descendantImageViews() -> [NSImageView] {
    subviews.flatMap { view -> [NSImageView] in
      let current = (view as? NSImageView).map { [$0] } ?? []
      return current + view.descendantImageViews()
    }
  }
}
