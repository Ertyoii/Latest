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
	func testSidebarGlassAccessorConfiguresOnlyItsNearestGlassAncestor() {
		XCTAssertEqual(
			VisualMetrics.sidebarGlassCornerRadius,
			VisualMetrics.mainWindowCornerRadius - VisualMetrics.sidebarGlassInset
		)
		let outerGlass = NSGlassEffectView()
		outerGlass.cornerRadius = 7
		let innerGlass = NSGlassEffectView()
		innerGlass.cornerRadius = 8
		let container = NSView()
		let accessor = SidebarGlassGeometryConfigurationView(
			cornerRadius: VisualMetrics.sidebarGlassCornerRadius,
			leadingLayoutInset: VisualMetrics.sidebarGlassLeadingLayoutInset
		)

		outerGlass.addSubview(innerGlass)
		innerGlass.addSubview(container)
		container.addSubview(accessor)

		XCTAssertTrue(accessor.configureNearestGlassAncestor())
		XCTAssertEqual(innerGlass.cornerRadius, VisualMetrics.sidebarGlassCornerRadius)
		XCTAssertEqual(outerGlass.cornerRadius, 7, "The accessor must not alter unrelated glass ancestors.")
	}

	@MainActor
	func testSidebarGlassAccessorCompensatesTheWindowFacingLeadingInset() {
		let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: 316, height: 548))
		let glass = NSGlassEffectView()
		glass.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(glass)

		let leading = glass.leadingAnchor.constraint(
			equalTo: wrapper.leadingAnchor,
			constant: VisualMetrics.sidebarGlassInset
		)
		let trailing = glass.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor)
		let equalBreadth = wrapper.widthAnchor.constraint(
			equalTo: glass.widthAnchor,
			constant: VisualMetrics.sidebarGlassInset
		)
		equalBreadth.priority = NSLayoutConstraint.Priority(999.99)
		NSLayoutConstraint.activate([leading, trailing, equalBreadth])

		let accessor = SidebarGlassGeometryConfigurationView(
			cornerRadius: VisualMetrics.sidebarGlassCornerRadius,
			leadingLayoutInset: VisualMetrics.sidebarGlassLeadingLayoutInset
		)
		glass.contentView = accessor

		XCTAssertTrue(accessor.configureNearestGlassAncestor())
		XCTAssertEqual(leading.constant, VisualMetrics.sidebarGlassLeadingLayoutInset)
		XCTAssertEqual(equalBreadth.constant, VisualMetrics.sidebarGlassLeadingLayoutInset)
		XCTAssertEqual(trailing.constant, 0)
	}

	@MainActor
	func testSidebarGlassAccessorDoesNothingOutsideAGlassSurface() {
		let container = NSView()
		let accessor = SidebarGlassGeometryConfigurationView(
			cornerRadius: VisualMetrics.sidebarGlassCornerRadius,
			leadingLayoutInset: VisualMetrics.sidebarGlassLeadingLayoutInset
		)
		container.addSubview(accessor)

		XCTAssertFalse(accessor.configureNearestGlassAncestor())
	}

	@MainActor
	func testProductionSidebarGlassUsesWindowConcentricRadius() throws {
		let environment = AppEnvironment.localUATFixture()
		let hostingView = NSHostingView(rootView: LatestRootView(environment: environment))
		hostingView.frame = NSRect(
			x: 0,
			y: 0,
			width: VisualMetrics.mainWindowDefaultWidth,
			height: VisualMetrics.mainWindowDefaultHeight
		)
		let window = NSWindow(
			contentRect: hostingView.bounds,
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = hostingView
		defer { window.close() }

		window.orderFront(nil)
		let sidebarGlass = try XCTUnwrap(
			waitForValue {
				window.layoutIfNeeded()
				hostingView.layoutSubtreeIfNeeded()
				return hostingView.descendantGlassEffects().first(where: {
					$0.containsDescendant(of: SidebarGlassGeometryConfigurationView.self) &&
						abs(
							$0.bounds.width -
								(VisualMetrics.sidebarIdealWidth - VisualMetrics.sidebarGlassLeadingCompensation)
						) < 0.5 &&
						$0.bounds.height >= VisualMetrics.mainWindowMinHeight &&
						$0.cornerRadius == VisualMetrics.sidebarGlassCornerRadius
				})
			}
		)
		let glassRectInWindow = sidebarGlass.convert(sidebarGlass.bounds, to: nil)
		let contentBounds = try XCTUnwrap(window.contentView).bounds
		let leadingInset = glassRectInWindow.minX - contentBounds.minX
		let visibleLeadingInset = leadingInset - VisualMetrics.sidebarGlassLeadingCompensation
		let bottomInset = glassRectInWindow.minY - contentBounds.minY
		let topInset = contentBounds.maxY - glassRectInWindow.maxY

		XCTAssertEqual(leadingInset, VisualMetrics.sidebarGlassLeadingLayoutInset, accuracy: 0.5)
		XCTAssertEqual(visibleLeadingInset, VisualMetrics.sidebarGlassInset, accuracy: 0.5)
		XCTAssertEqual(bottomInset, VisualMetrics.sidebarGlassInset, accuracy: 0.5)
		XCTAssertEqual(topInset, VisualMetrics.sidebarGlassInset, accuracy: 0.5)
		XCTAssertEqual(sidebarGlass.cornerRadius, VisualMetrics.sidebarGlassCornerRadius)
		XCTAssertEqual(
			visibleLeadingInset + sidebarGlass.cornerRadius,
			VisualMetrics.mainWindowCornerRadius,
			accuracy: 0.5
		)
		XCTAssertEqual(
			bottomInset + sidebarGlass.cornerRadius,
			VisualMetrics.mainWindowCornerRadius,
			accuracy: 0.5
		)
		XCTAssertEqual(
			topInset + sidebarGlass.cornerRadius,
			VisualMetrics.mainWindowCornerRadius,
			accuracy: 0.5
		)

		window.setContentSize(NSSize(width: 900, height: 640))
		XCTAssertTrue(waitForCondition {
			window.layoutIfNeeded()
			hostingView.layoutSubtreeIfNeeded()
			let glassRect = sidebarGlass.convert(sidebarGlass.bounds, to: nil)
			guard let contentBounds = window.contentView?.bounds else { return false }
			return abs(
				glassRect.minX - contentBounds.minX - VisualMetrics.sidebarGlassLeadingLayoutInset
			) < 0.5 &&
				abs(glassRect.minY - contentBounds.minY - VisualMetrics.sidebarGlassInset) < 0.5 &&
				sidebarGlass.cornerRadius == VisualMetrics.sidebarGlassCornerRadius
		})

		let resizedGlassRect = sidebarGlass.convert(sidebarGlass.bounds, to: nil)
		let resizedContentBounds = try XCTUnwrap(window.contentView).bounds
		XCTAssertEqual(
			resizedGlassRect.minX - resizedContentBounds.minX,
			VisualMetrics.sidebarGlassLeadingLayoutInset,
			accuracy: 0.5
		)
		XCTAssertEqual(
			resizedGlassRect.minY - resizedContentBounds.minY,
			VisualMetrics.sidebarGlassInset,
			accuracy: 0.5
		)
		XCTAssertEqual(sidebarGlass.cornerRadius, VisualMetrics.sidebarGlassCornerRadius)
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
	func testMainWindowSidebarIsVisibleByDefault() {
		XCTAssertEqual(MainWindowSidebarPolicy.defaultVisibility, .all)
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
	func testSidebarShowsLongInstalledVersionWithoutTruncationAtIdealWidth() {
		let date = Date()
		let app = makeApp(name: "Chrome", version: "151.0.7922.109", date: date)
		guard let expectedVersion = app.localizedVersionInformation?.current else {
			XCTFail("Expected the installed version field in the update row.")
			return
		}
		let versionWidth = (expectedVersion as NSString).size(
			withAttributes: [.font: NSFont.systemFont(ofSize: 11)]
		).width
		let availableWidth = AppKitUpdateRowContentView.Layout.availableVersionWidth(
			rowWidth: VisualMetrics.sidebarIdealWidth
		)

		XCTAssertGreaterThanOrEqual(
			availableWidth + 0.5,
			versionWidth,
			"The installed version should use the available row width instead of truncating."
		)
		XCTAssertEqual(AppKitUpdateRowContentView.Layout.trailingWidth, 59)
		XCTAssertEqual(AppKitUpdateRowContentView.Layout.rightInset, 32)
	}

	@MainActor
	func testAppKitSidebarTextColorsFollowSelectionEmphasis() throws {
		let row = AppKitUpdateRowContentView(
			frame: NSRect(x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: VisualMetrics.appRowHeight)
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
			nameField.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
		)
		XCTAssertEqual(activeTitleColor, .alternateSelectedControlTextColor)
		for field in fields where field !== nameField {
			XCTAssertEqual(field.textColor, .alternateSelectedControlTextColor)
		}

		row.backgroundStyle = .normal

		let inactiveTitleColor = try XCTUnwrap(
			nameField.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
		)
		XCTAssertEqual(inactiveTitleColor, .labelColor)
		for field in fields where field !== nameField {
			XCTAssertEqual(field.textColor, .secondaryLabelColor)
		}
	}

	@MainActor
	func testSidebarSelectionStaysNeutralWhenWindowBecomesKey() {
		let row = StableSelectionTableRowView()
		row.isSelected = true
		row.isEmphasized = true

		XCTAssertTrue(row.isSelected)
		XCTAssertFalse(row.isEmphasized)
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

	@MainActor
	private func waitForValue<Value>(
		timeout: TimeInterval = 1,
		pollInterval: TimeInterval = 0.01,
		_ value: () -> Value?
	) -> Value? {
		let deadline = Date(timeIntervalSinceNow: timeout)
		repeat {
			if let value = value() {
				return value
			}
			RunLoop.main.run(until: min(deadline, Date(timeIntervalSinceNow: pollInterval)))
		} while Date() < deadline

		return value()
	}

	@MainActor
	private func waitForCondition(
		timeout: TimeInterval = 1,
		pollInterval: TimeInterval = 0.01,
		_ condition: () -> Bool
	) -> Bool {
		waitForValue(timeout: timeout, pollInterval: pollInterval) {
			condition() ? true : nil
		} ?? false
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
	func containsDescendant<ViewType: NSView>(of type: ViewType.Type) -> Bool {
		if self is ViewType { return true }
		return subviews.contains { $0.containsDescendant(of: type) }
	}

	func descendantGlassEffects() -> [NSGlassEffectView] {
		subviews.flatMap { view -> [NSGlassEffectView] in
			let current = (view as? NSGlassEffectView).map { [$0] } ?? []
			return current + view.descendantGlassEffects()
		}
	}

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
