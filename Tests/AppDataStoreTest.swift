//
//  AppDataStoreTest.swift
//  Latest Tests
//
//  Created by Codex on 19.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import XCTest
@testable import Latest

final class AppDataStoreTest: XCTestCase {

	func testSingleBundleRefreshPreservesUpdateState() {
		let store = AppDataStore()
		let appURL = URL(fileURLWithPath: "/Applications/Indexed-\(UUID().uuidString).app", isDirectory: true)
		let initialBundle = makeBundle(versionNumber: "1.0", at: appURL)
		let remoteVersion = Version(versionNumber: "2.0", buildNumber: nil)

		_ = store.set(appBundles: [initialBundle])
		_ = store.set(.success(makeUpdate(for: initialBundle, remoteVersion: remoteVersion)), for: initialBundle)

		let refreshedBundle = makeBundle(versionNumber: "1.1", at: appURL)
		let refreshedApp = store.set(appBundle: refreshedBundle)

		XCTAssertEqual(refreshedApp.version.versionNumber, "1.1")
		XCTAssertEqual(refreshedApp.remoteVersion, remoteVersion)
	}

	private func makeBundle(versionNumber: String, at url: URL) -> App.Bundle {
		App.Bundle(
			version: Version(versionNumber: versionNumber, buildNumber: nil),
			name: "Indexed",
			bundleIdentifier: "com.example.indexed.\(url.deletingPathExtension().lastPathComponent)",
			fileURL: url,
			source: .sparkle
		)
	}

	private func makeUpdate(for bundle: App.Bundle, remoteVersion: Version) -> App.Update {
		App.Update(
			app: bundle,
			remoteVersion: remoteVersion,
			minimumOSVersion: nil,
			source: .sparkle,
			date: nil,
			releaseNotes: nil,
			updateAction: .external(label: "Test") { _ in }
		)
	}

}
