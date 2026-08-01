//
//  ReleaseNotesHeaderLayoutTest.swift
//  Latest Tests
//
//  Created by Codex on 11.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

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
	func testUpdateActionKeepsOriginalDrawingMetrics() throws {
		XCTAssertEqual(UpdateActionVisualStyle.capsuleHorizontalInset, 0.25)
		XCTAssertEqual(UpdateActionVisualStyle.progressDiameter, 20)
		XCTAssertEqual(UpdateActionVisualStyle.progressLineWidth, 2.5)
		XCTAssertEqual(UpdateActionVisualStyle.pauseBarSize, CGSize(width: 2, height: 8))
		XCTAssertEqual(UpdateActionVisualStyle.pauseBarSpacing, 2)

		let background = try XCTUnwrap(UpdateButton.Style.backgroundColor.usingColorSpace(.sRGB))
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
	func testSwiftUIRefreshToolbarButtonRunsActionAndExposesAccessibilityContract() {
		var invocationCount = 0
		let button = RefreshToolbarButton(isEnabled: true) {
			invocationCount += 1
		}

		XCTAssertTrue(button.isEnabled)
		XCTAssertEqual(RefreshToolbarButton.accessibilityIdentifier, "toolbar.refresh")
		XCTAssertEqual(RefreshToolbarButton.accessibilityLabel, "Check for Updates")
		XCTAssertNotNil(NSImage(
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
	func testMainWindowSidebarVisibilityIsLockedOpen() {
		let visibility = MainWindowSidebarPolicy.columnVisibility
		XCTAssertEqual(visibility.wrappedValue, .all)

		visibility.wrappedValue = .detailOnly
		XCTAssertEqual(visibility.wrappedValue, .all)
	}

	@MainActor
	func testSidebarCustomSelectionUsesCompensatedInsets() {
		XCTAssertLessThan(
			LegacyUpdateRowContentView.Layout.selectionLeadingInset,
			LegacyUpdateRowContentView.Layout.selectionTrailingInset,
			"The source-list cell extends farther toward the divider, so only its trailing inset needs compensation."
		)
		XCTAssertEqual(LegacyUpdateRowContentView.Layout.selectionLeadingInset, 0)
		XCTAssertEqual(LegacyUpdateRowContentView.Layout.selectionTrailingInset, 24)
		XCTAssertEqual(LegacyUpdateRowContentView.Layout.selectionCornerRadius, 12)
	}

	@MainActor
	func testSidebarCustomSelectionUsesTextColorForColoredBackground() throws {
		let row = LegacyUpdateRowContentView(
			frame: NSRect(x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: VisualMetrics.appRowHeight)
		)
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .none
		let app = makeApp(name: "Discord", version: "0.0.398", remoteVersion: "0.0.399")

		row.update(app: app, isSelected: true, drawsSelectionBackground: true, filterQuery: nil, dateFormatter: dateFormatter)

		let fields = row.descendantTextFields()
		let nameField = try XCTUnwrap(fields.first(where: { $0.stringValue == "Discord" }))
		let titleColor = try XCTUnwrap(
			nameField.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
		)
		XCTAssertEqual(titleColor, .alternateSelectedControlTextColor)
		for field in fields where field !== nameField {
			XCTAssertEqual(field.textColor, .alternateSelectedControlTextColor)
		}
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
		let app = Latest.App(bundle: bundle, update: .failure(LatestError.updateInfoUnavailable), isIgnored: false)
		let viewModel = ReleaseNotesDetailViewModel()

		viewModel.display(app)

		guard case .message(let message) = viewModel.contentState else {
			return XCTFail("Expected the provider to map update-check failures to a release-notes message.")
		}
		XCTAssertEqual(message.title, NSLocalizedString("ReleaseNotesUnavailableError", comment: ""))
		XCTAssertEqual(message.description, NSLocalizedString("ReleaseNotesUnavailableErrorFailureReason", comment: ""))
		XCTAssertNotEqual(message.description, NSLocalizedString("UpdateInfoUnavailableErrorFailureReason", comment: ""))
	}

	func testSparkleChecksHaveABoundedDeadline() {
		XCTAssertGreaterThan(SparkleUpdateCheckerOperation.checkTimeout, 0)
		XCTAssertLessThanOrEqual(SparkleUpdateCheckerOperation.checkTimeout, 10)
	}

	@MainActor
	func testSidebarDateAndStatusAlignWithTextRows() throws {
		let row = LegacyUpdateRowContentView(frame: NSRect(x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: VisualMetrics.appRowHeight))
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .none
		let app = makeApp(name: "ChatGPT", version: "26.707.51957")

		row.update(app: app, isSelected: false, drawsSelectionBackground: false, filterQuery: nil, dateFormatter: dateFormatter)
		row.layoutSubtreeIfNeeded()

		let fields = row.descendantTextFields()
		let nameField = try XCTUnwrap(fields.first(where: { $0.stringValue == "ChatGPT" }))
		let versionField = try XCTUnwrap(fields.first(where: { $0.stringValue.contains("26.707.51957") }))
		let dateField = try XCTUnwrap(fields.first(where: { $0.stringValue == dateFormatter.string(from: app.updateDate) }))
		let statusView = try XCTUnwrap(row.descendantImageViews().first(where: { $0.frame.size == NSSize(width: 16, height: 16) }))

		let nameFrame = nameField.convert(nameField.bounds, to: row)
		let dateFrame = dateField.convert(dateField.bounds, to: row)
		let nameBaseline = nameFrame.maxY - nameField.firstBaselineOffsetFromTop
		let dateBaseline = dateFrame.maxY - dateField.firstBaselineOffsetFromTop
		let versionFrame = versionField.convert(versionField.bounds, to: row)
		let statusFrame = statusView.convert(statusView.bounds, to: row)

		XCTAssertEqual(dateBaseline, nameBaseline, accuracy: 0.5)
		XCTAssertEqual(statusFrame.midY, versionFrame.midY, accuracy: 0.5)
	}

	@MainActor
	func testSidebarShowsLongInstalledVersionWithoutTruncationAtIdealWidth() {
		let date = Date()
		let app = makeApp(name: "Codex", version: "26.623.101652", date: date)
		guard let expectedVersion = app.localizedVersionInformation?.current else {
			XCTFail("Expected the installed version field in the update row.")
			return
		}
		let versionWidth = (expectedVersion as NSString).size(
			withAttributes: [.font: NSFont.systemFont(ofSize: 11)]
		).width
		let availableWidth = LegacyUpdateRowContentView.Layout.availableVersionWidth(
			rowWidth: VisualMetrics.sidebarIdealWidth
		)

		XCTAssertGreaterThanOrEqual(
			availableWidth + 0.5,
			versionWidth,
			"The installed version should use the available row width instead of truncating."
		)
		XCTAssertEqual(LegacyUpdateRowContentView.Layout.trailingWidth, 59)
		XCTAssertEqual(LegacyUpdateRowContentView.Layout.rightInset, 32)
	}

	private func makeApp(
		name: String,
		version: String,
		remoteVersion: String? = nil,
		date: Date = Date(),
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

private extension NSView {
	func descendantTextFields() -> [NSTextField] {
		subviews.flatMap { view -> [NSTextField] in
			let current = (view as? NSTextField).map { [$0] } ?? []
			return current + view.descendantTextFields()
		}
	}

	func descendantImageViews() -> [NSImageView] {
		subviews.flatMap { view -> [NSImageView] in
			let current = (view as? NSImageView).map { [$0] } ?? []
			return current + view.descendantImageViews()
		}
	}
}
