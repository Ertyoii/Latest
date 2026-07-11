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
		let availableWidth = UpdateRowView.Layout.availableVersionWidth(
			rowWidth: VisualMetrics.sidebarIdealWidth
		)

		XCTAssertGreaterThanOrEqual(
			availableWidth + 0.5,
			versionWidth,
			"The installed version should use the available row width instead of truncating."
		)
		XCTAssertEqual(UpdateRowView.Layout.trailingWidth, 59)
		XCTAssertEqual(UpdateRowView.Layout.trailingPadding, 6)
	}

	private func makeApp(name: String, version: String, date: Date) -> App {
		let bundle = App.Bundle(
			version: Version(versionNumber: version, buildNumber: nil),
			name: name,
			bundleIdentifier: "com.example.\(name.replacingOccurrences(of: " ", with: "-"))",
			fileURL: URL(fileURLWithPath: "/Applications/\(name).app"),
			source: .appStore
		)
		let update = App.Update(
			app: bundle,
			remoteVersion: Version(versionNumber: version, buildNumber: nil),
			minimumOSVersion: nil,
			source: .appStore,
			date: date,
			releaseNotes: .html(string: "<p>Release notes</p>"),
			updateAction: .builtIn { _ in }
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
