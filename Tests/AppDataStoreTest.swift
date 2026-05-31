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

final class AppDirectoryTest: XCTestCase {

	func testRefreshRecollectsBundleVersionFromDisk() throws {
		let directoryURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directoryURL) }

		let appURL = directoryURL.appendingPathComponent("Refreshable.app", isDirectory: true)
		try writeAppBundle(at: appURL, versionNumber: "1.0")

		let initialCollection = expectation(description: "Initial collection")
		let directory = AppDirectory(url: directoryURL) {
			initialCollection.fulfill()
		}
		wait(for: [initialCollection], timeout: 2)

		XCTAssertEqual(directory.bundles.first?.version.versionNumber, "1.0")

		try writeAppBundle(at: appURL, versionNumber: "1.1")

		let refreshedCollection = expectation(description: "Refreshed collection")
		directory.refresh {
			refreshedCollection.fulfill()
		}
		wait(for: [refreshedCollection], timeout: 2)

		XCTAssertEqual(directory.bundles.first?.version.versionNumber, "1.1")
	}

	private func writeAppBundle(at url: URL, versionNumber: String) throws {
		let contentsURL = url.appendingPathComponent("Contents", isDirectory: true)
		try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

		let information: [String: Any] = [
			"CFBundleIdentifier": "com.example.refreshable",
			"CFBundleName": "Refreshable",
			"CFBundleShortVersionString": versionNumber,
			"CFBundleVersion": "1",
			"SUFeedURL": "https://example.com/appcast.xml"
		]
		let data = try PropertyListSerialization.data(fromPropertyList: information, format: .xml, options: 0)
		try data.write(to: contentsURL.appendingPathComponent("Info.plist"), options: .atomic)
	}

}
