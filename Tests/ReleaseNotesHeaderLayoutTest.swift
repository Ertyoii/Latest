//
//  ReleaseNotesHeaderLayoutTest.swift
//  Latest Tests
//
//  Created by Codex on 11.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import XCTest
@testable import Latest

final class ReleaseNotesHeaderLayoutTest: XCTestCase {
	@MainActor
	func testDisplayedAppSurvivesViewAppearance() {
		let controller = ReleaseNotesViewController()
		controller.loadViewIfNeeded()
		let app = makeApp(name: "Zed", version: "1.10.0", remoteVersion: "1.10.2")

		controller.display(releaseNotesFor: app)
		controller.viewWillAppear()

		XCTAssertEqual(controller.app?.identifier, app.identifier)
		XCTAssertFalse(controller.appInfoBackgroundView.isHidden)
		XCTAssertEqual(controller.appNameTextField.stringValue, "Zed")
	}

	@MainActor
	func testUpdateButtonIsVisibleAndContainedInFixedHeader() {
		let controller = ReleaseNotesViewController()
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 768, height: 516),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = controller
		controller.loadViewIfNeeded()
		controller.display(releaseNotesFor: makeApp(
			name: "Zed",
			version: "1.10.0",
			remoteVersion: "1.10.2",
			updateAction: .external(label: "Zed") { _ in }
		))
		controller.view.layoutSubtreeIfNeeded()
		window.contentView?.layoutSubtreeIfNeeded()

		let buttonFrame = controller.updateButton.convert(controller.updateButton.bounds, to: controller.view)
		let headerFrame = controller.appInfoBackgroundView.convert(
			controller.appInfoBackgroundView.bounds,
			to: controller.view
		)
		let iconFrame = controller.appIconImageView.convert(controller.appIconImageView.bounds, to: controller.view)
		let externalLabelFrame = controller.externalUpdateLabel.convert(
			controller.externalUpdateLabel.bounds,
			to: controller.view
		)
		guard let labelStack = controller.appNameTextField.superview?.superview else {
			XCTFail("Expected the title and version fields to share a vertical stack.")
			return
		}
		let labelStackFrame = labelStack.convert(labelStack.bounds, to: controller.view)
		XCTAssertFalse(controller.updateButton.isHidden)
		XCTAssertEqual(headerFrame.height, VisualMetrics.detailHeaderHeight, accuracy: 0.5)
		XCTAssertEqual(
			headerFrame.maxY - iconFrame.maxY,
			VisualMetrics.detailHeaderVerticalPadding,
			accuracy: 0.5,
			"The app block should have equal space above and below it."
		)
		XCTAssertEqual(
			iconFrame.minY - headerFrame.minY,
			VisualMetrics.detailHeaderVerticalPadding,
			accuracy: 0.5
		)
		XCTAssertEqual(iconFrame.midY, headerFrame.midY, accuracy: 0.5)
		XCTAssertEqual(labelStackFrame.midY, iconFrame.midY, accuracy: 0.5)
		XCTAssertEqual(buttonFrame.midY, iconFrame.midY, accuracy: 0.5)
		XCTAssertTrue(headerFrame.insetBy(dx: -0.5, dy: -0.5).contains(buttonFrame))
		XCTAssertTrue(headerFrame.insetBy(dx: -0.5, dy: -0.5).contains(externalLabelFrame))
		XCTAssertEqual(buttonFrame.width, VisualMetrics.detailUpdateButtonWidth, accuracy: 0.5)
		XCTAssertEqual(buttonFrame.height, VisualMetrics.detailUpdateButtonHeight, accuracy: 0.5)
		XCTAssertEqual(
			headerFrame.maxX - buttonFrame.maxX,
			VisualMetrics.detailHeaderHorizontalPadding,
			accuracy: 0.5,
			"The action must keep a stable trailing inset from the detail border."
		)

		_ = window
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
	}

	@MainActor
	func testMainWindowChromeRemovesToolbarSeparator() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 768, height: 516),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		let toolbar = NSToolbar(identifier: "test.toolbar")
		window.toolbar = toolbar

		MainWindowChrome.configure(
			window,
			commands: AppEnvironment().commands,
			refreshIsEnabled: true
		)

		XCTAssertEqual(window.titlebarSeparatorStyle, .none)
		XCTAssertNotNil(window.toolbar)
	}

	@MainActor
	func testSidebarToggleToolbarItemIsRepurposedAsRefresh() {
		let target = MainToolbarRefreshTarget(commands: AppEnvironment().commands)
		let item = NSToolbarItem(itemIdentifier: .toggleSidebar)

		MainWindowChrome.repurposeSidebarToggleItem(item, target: target)

		XCTAssertEqual(item.itemIdentifier, .toggleSidebar)
		XCTAssertEqual(item.label, "Check for Updates")
		XCTAssertTrue(item.target === target)
		XCTAssertEqual(item.action, #selector(MainToolbarRefreshTarget.reload(_:)))
		XCTAssertNotNil(item.image)
		let button = try? XCTUnwrap(item.view as? MainToolbarRefreshButton)
		XCTAssertNotNil(button)
		XCTAssertEqual(button?.accessibilityLabel(), "Check for Updates")
	}

	@MainActor
	func testSwiftUIPrivateSidebarToggleIsRecognizedByResponderAction() {
		let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("SwiftUI.NavigationSidebar"))
		item.action = NSSelectorFromString("toggleSidebar:")

		XCTAssertTrue(MainWindowChrome.isSidebarToggleItem(item))
	}

	@MainActor
	func testSidebarGlassUsesWindowConcentricCornerRadius() {
		let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 768, height: 516))
		let sidebarGlass = NSGlassEffectView(
			frame: NSRect(
				x: 8,
				y: 8,
				width: VisualMetrics.sidebarIdealWidth,
				height: VisualMetrics.mainWindowMinHeight - (VisualMetrics.sidebarGlassInset * 2)
			)
		)
		let compactGlass = NSGlassEffectView(
			frame: NSRect(x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: 40)
		)
		rootView.addSubview(sidebarGlass)
		rootView.addSubview(compactGlass)

		MainWindowChrome.configureSidebarGlassSurface(in: rootView)

		XCTAssertEqual(sidebarGlass.cornerRadius, VisualMetrics.sidebarGlassCornerRadius)
		XCTAssertNotEqual(compactGlass.cornerRadius, VisualMetrics.sidebarGlassCornerRadius)
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
		let controller = ReleaseNotesViewController()
		controller.loadViewIfNeeded()
		let bundle = App.Bundle(
			version: Version(versionNumber: "26.707.51957", buildNumber: nil),
			name: "ChatGPT",
			bundleIdentifier: "com.openai.codex",
			fileURL: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
			source: .sparkle
		)
		let app = App(bundle: bundle, update: .failure(LatestError.updateInfoUnavailable), isIgnored: false)

		controller.display(releaseNotesFor: app)

		let labels = controller.view.descendantTextFields().map(\.stringValue)
		XCTAssertTrue(labels.contains(NSLocalizedString("ReleaseNotesUnavailableError", comment: "")))
		XCTAssertTrue(labels.contains(NSLocalizedString("ReleaseNotesUnavailableErrorFailureReason", comment: "")))
		XCTAssertFalse(labels.contains(NSLocalizedString("UpdateInfoUnavailableErrorFailureReason", comment: "")))
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
	func testDatedHeaderTextAlignsAndStaysInsideIconBounds() {
		let controller = ReleaseNotesViewController()
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 768, height: 516),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = controller
		controller.loadViewIfNeeded()
		controller.viewWillAppear()

		let date = Date(timeIntervalSince1970: 1_750_000_000)
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .long
		dateFormatter.timeStyle = .none
		let dateString = dateFormatter.string(from: date)
		controller.display(releaseNotesFor: makeApp(name: "Latest Dev", version: "0.33", date: date))
		controller.view.layoutSubtreeIfNeeded()
		window.contentView?.layoutSubtreeIfNeeded()

		let textFields = controller.view.descendantTextFields()
		guard let nameField = textFields.first(where: { $0.stringValue == "Latest Dev" }),
			  let versionField = textFields.first(where: { $0.stringValue == "Version: 0.33" }),
			  let dateField = textFields.first(where: { $0.stringValue == dateString })
		else {
			XCTFail("Expected app name, version, and date text fields in the release notes header.")
			return
		}
		guard let iconView = controller.view.descendantImageViews().first(where: { $0.frame.width == 64 && $0.frame.height == 64 }) else {
			XCTFail("Expected a 64pt app icon in the release notes header.")
			return
		}

		let nameFrame = nameField.convert(nameField.bounds, to: controller.view)
		let versionFrame = versionField.convert(versionField.bounds, to: controller.view)
		let dateFrame = dateField.convert(dateField.bounds, to: controller.view)
		let iconFrame = iconView.convert(iconView.bounds, to: controller.view)

		XCTAssertEqual(nameFrame.minX, versionFrame.minX, accuracy: 0.5)
		XCTAssertEqual(nameFrame.minX, dateFrame.minX, accuracy: 0.5)
		XCTAssertGreaterThanOrEqual(nameFrame.minY, iconFrame.minY - 0.5)
		XCTAssertLessThanOrEqual(nameFrame.maxY, iconFrame.maxY + 0.5)
		XCTAssertGreaterThanOrEqual(dateFrame.minY, iconFrame.minY - 0.5)
		XCTAssertLessThanOrEqual(dateFrame.maxY, iconFrame.maxY + 0.5)

		_ = window
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
		updateAction: App.Update.Action = .builtIn { _ in }
	) -> App {
		let bundle = App.Bundle(
			version: Version(versionNumber: version, buildNumber: nil),
			name: name,
			bundleIdentifier: "com.example.\(name.replacingOccurrences(of: " ", with: "-"))",
			fileURL: URL(fileURLWithPath: "/Applications/\(name).app"),
			source: .appStore
		)
		let update = App.Update(
			app: bundle,
			remoteVersion: Version(versionNumber: remoteVersion ?? version, buildNumber: nil),
			minimumOSVersion: nil,
			source: .appStore,
			date: date,
			releaseNotes: .html(string: "<p>Release notes</p>"),
			updateAction: updateAction
		)
		return App(bundle: bundle, update: .success(update), isIgnored: false)
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
