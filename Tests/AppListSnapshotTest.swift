//
//  AppListSnapshotTest.swift
//  Latest Tests
//
//  Created by Codex on 20.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import XCTest
@testable import Latest

@MainActor
final class AppListSnapshotTest: XCTestCase {

	func testSnapshotPartitionsAppsIntoAvailableInstalledAndIgnoredSections() {
		configureSettings()

		let available = makeApp(name: "Alpha", versionNumber: "1.0", remoteVersionNumber: "2.0")
		let installed = makeApp(name: "Beta", versionNumber: "1.0")
		let ignored = makeApp(name: "Gamma", versionNumber: "1.0", remoteVersionNumber: "2.0", isIgnored: true)

		let snapshot = AppListSnapshot(withApps: [installed, ignored, available], filterQuery: nil)

		XCTAssertEqual(snapshot.entries.count, 6)
		XCTAssertEqual(section(at: 0, in: snapshot)?.numberOfApps, 1)
		XCTAssertEqual(snapshot.app(at: 1)?.name, "Alpha")
		XCTAssertEqual(section(at: 2, in: snapshot)?.numberOfApps, 1)
		XCTAssertEqual(snapshot.app(at: 3)?.name, "Beta")
		XCTAssertEqual(section(at: 4, in: snapshot)?.numberOfApps, 1)
		XCTAssertEqual(snapshot.app(at: 5)?.name, "Gamma")
	}

	func testSnapshotFilterKeepsOnlyMatchingAppsAndSections() {
		configureSettings()

		let alpha = makeApp(name: "Alpha", versionNumber: "1.0", remoteVersionNumber: "2.0")
		let beta = makeApp(name: "Beta", versionNumber: "1.0", remoteVersionNumber: "2.0")

		let snapshot = AppListSnapshot(withApps: [alpha, beta], filterQuery: "alp")

		XCTAssertEqual(snapshot.entries.count, 2)
		XCTAssertEqual(section(at: 0, in: snapshot)?.numberOfApps, 1)
		XCTAssertEqual(snapshot.app(at: 1)?.name, "Alpha")
	}

	func testSnapshotMatchesUpdatedAppByIdentifier() {
		configureSettings()

		let appURL = URL(fileURLWithPath: "/Applications/Snapshot-\(UUID().uuidString).app", isDirectory: true)
		let original = makeApp(name: "Snapshot", versionNumber: "1.0", appURL: appURL)
		let refreshed = makeApp(name: "Snapshot", versionNumber: "1.1", appURL: appURL)
		let snapshot = AppListSnapshot(withApps: [original], filterQuery: nil)

		XCTAssertEqual(snapshot.firstIndex(of: refreshed), snapshot.firstIndex(of: original))
	}

	private func configureSettings() {
		AppListSettings.shared.sortOrder = .name
		AppListSettings.shared.showInstalledUpdates = true
		AppListSettings.shared.showIgnoredUpdates = true
		AppListSettings.shared.includeUnsupportedApps = true
		AppListSettings.shared.includeAppsWithLimitedSupport = true
	}

	private func section(at index: Int, in snapshot: AppListSnapshot) -> AppListSnapshot.Section? {
		guard case .section(let section) = snapshot.entries[index] else { return nil }
		return section
	}

	private func makeApp(
		name: String,
		versionNumber: String,
		remoteVersionNumber: String? = nil,
		isIgnored: Bool = false,
		appURL: URL? = nil
	) -> App {
		let url = appURL ?? URL(fileURLWithPath: "/Applications/\(name)-\(UUID().uuidString).app", isDirectory: true)
		let bundle = App.Bundle(
			version: Version(versionNumber: versionNumber, buildNumber: nil),
			name: name,
			bundleIdentifier: "com.example.\(name.lowercased())",
			fileURL: url,
			source: .sparkle
		)

		let update: Result<App.Update, Error>? = remoteVersionNumber.map { remoteVersionNumber in
			.success(App.Update(
				app: bundle,
				remoteVersion: Version(versionNumber: remoteVersionNumber, buildNumber: nil),
				minimumOSVersion: nil,
				source: .sparkle,
				date: nil,
				releaseNotes: nil,
				updateAction: .external(label: "Test") { _ in }
			))
		}

		return App(bundle: bundle, update: update, isIgnored: isIgnored)
	}

}
