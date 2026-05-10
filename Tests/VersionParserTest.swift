//
//  VersionParserTest.swift
//  Latest Tests
//
//  Created by Max Langer on 29.11.23.
//  Copyright © 2023 Max Langer. All rights reserved.
//

import XCTest
@testable import Latest


final class VersionParserTest: XCTestCase {

	func testBuildNumberParsing() {
		XCTAssertEqual(VersionParser.parse(buildNumber: "1234"), "1234")
		XCTAssertEqual(VersionParser.parse(buildNumber: "IU-1234"), "1234")
		XCTAssertEqual(VersionParser.parse(buildNumber: "WS-1234"), "1234")
		XCTAssertEqual(VersionParser.parse(buildNumber: "1.2/1234"), "1234")
		XCTAssertEqual(VersionParser.parse(buildNumber: "1.2 (r1234)"), "1234")
		XCTAssertEqual(VersionParser.parse(buildNumber: "ab-1234"), "ab-1234")
	}
	
	func testVersionNumberParsing() {
		XCTAssertEqual(VersionParser.parse(versionNumber: "1234"), "1234")
		XCTAssertEqual(VersionParser.parse(versionNumber: "v1234"), "1234")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2.3.4"), "1.2.3.4")
		XCTAssertEqual(VersionParser.parse(versionNumber: "Build 1234"), "1234")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2.3 (r1234)"), "1.2.3")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2.3.osx14"), "1.2.3")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2-HEAD-123abc"), "1.2")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2-stable.123abc"), "1.2")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2-latest"), "1.2")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2-release"), "1.2")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2-demo"), "1.2")
	}

	func testCombinedVersionNumberParsing() {
		XCTAssertEqual(VersionParser.parse(combinedVersionNumber: "1234"), Version(versionNumber: "1234", buildNumber: nil))
		XCTAssertEqual(VersionParser.parse(combinedVersionNumber: "1234,321"), Version(versionNumber: "1234", buildNumber: "321"))
		XCTAssertEqual(VersionParser.parse(combinedVersionNumber: "1.2.3.4,321ABC,70"), Version(versionNumber: "1.2.3.4", buildNumber: "321ABC"))
		XCTAssertEqual(VersionParser.parse(combinedVersionNumber: "2.2.1-763"), Version(versionNumber: "2.2.1", buildNumber: "763"))
	}
	
	func testEmptyVersionParsing() {
		XCTAssertNil(VersionParser.parse(buildNumber: ""))
		XCTAssertNil(VersionParser.parse(versionNumber: ""))
		
		XCTAssertEqual(VersionParser.parse(combinedVersionNumber: ""), Version(versionNumber: nil, buildNumber: nil))
	}

	func testHomebrewCaskEntryDoesNotUseMetadataAsReleaseNotes() throws {
		let json = """
		{
			"token": "example-app",
			"version": "2.4.1",
			"name": ["Example App"],
			"desc": "Notes, tasks & reminders",
			"homepage": "https://example.com",
			"depends_on": {
				"macos": {
					">=": ["13.0"]
				}
			},
			"artifacts": [
				{
					"app": ["Example App.app"]
				}
			]
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		XCTAssertNil(entry.releaseNotes)
	}

	func testHomebrewCaskEntryKeepsBundleIdentifiersWhenAppArtifactExists() throws {
		let json = """
		{
			"token": "example-app",
			"version": "2.4.1",
			"artifacts": [
				{
					"app": ["Example App.app"]
				},
				{
					"zap": [
						{
							"trash": [
								"~/Library/Preferences/com.example.app.plist"
							],
							"delete": [
								"~/Library/Application Support/com.example.helper"
							]
						}
					]
				}
			],
			"depends_on": {
				"macos": {}
			}
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		XCTAssertEqual(entry.names, ["Example App.app"])
		XCTAssertTrue(entry.bundleIdentifiers.contains("com.example.app"))
		XCTAssertTrue(entry.bundleIdentifiers.contains("com.example.helper"))
		XCTFalse(entry.requiresBundleIdentifierMatch)
	}

	func testHomebrewCaskEntryUsesNameStanzaForPkgInstalledApps() throws {
		let json = """
		{
			"token": "garmin-express",
			"name": ["Garmin Express"],
			"version": "7.28.0",
			"artifacts": [
				{
					"uninstall": [
						{
							"quit": ["com.garmin.renu.client"]
						}
					]
				},
				{
					"pkg": ["Install Garmin Express.pkg"]
				}
			],
			"depends_on": {
				"macos": {}
			}
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		XCTAssertEqual(entry.names, ["Garmin Express.app"])
		XCTEqual(entry.bundleIdentifiers, ["com.garmin.renu.client"])
		XCTTrue(entry.requiresBundleIdentifierMatch)
	}

	func testHomebrewRepositoryPrefersStableCaskAfterIdentifierMatch() throws {
		let stable = try homebrewEntry(token: "telegram-desktop", bundleIdentifier: "com.tdesktop.Telegram")
		let beta = try homebrewEntry(token: "telegram-desktop@beta", bundleIdentifier: "com.tdesktop.Telegram")
		let other = try homebrewEntry(token: "telegram", bundleIdentifier: "ru.keepcoder.Telegram")

		let entry = UpdateRepository.preferredEntry(from: [other, stable, beta], for: "com.tdesktop.Telegram")

		XCTAssertEqual(entry?.token, "telegram-desktop")
	}

	func testHomebrewRepositoryPrefersShortestStableCaskWhenIdentifierMatchesMultipleEntries() throws {
		let stable = try homebrewEntry(token: "zoom", bundleIdentifier: "us.zoom.xos")
		let admin = try homebrewEntry(token: "zoom-for-it-admins", bundleIdentifier: "us.zoom.xos")

		let entry = UpdateRepository.preferredEntry(from: [admin, stable], for: "us.zoom.xos")

		XCTAssertEqual(entry?.token, "zoom")
	}

	func testMarkdownReleaseNotesAreRenderedAsRichTextLists() throws {
		let markdown = """
		## IINA 1.4.2

		### New

		* * Added gapless audio playback options, #5433.
		* The system media keys are now configurable, #5933.
		"""

		let string = try ReleaseNotesMarkup.attributedString(from: markdown, baseURL: nil).get()

		XCTAssertTrue(string.string.contains("IINA 1.4.2"))
		XCTAssertTrue(string.string.contains("Added gapless audio playback options"))
		XCTAssertFalse(string.string.contains("* Added"))
		XCTAssertFalse(string.string.contains("•        •"))
	}
	
}

final class BundleCollectorTest: XCTestCase {

	func testCollectsAppUsingDisplayNameWhenBundleNameIsMissing() throws {
		let directory = try makeTemporaryDirectory()
		let appURL = try makeAppBundle(
			named: "Display Name Only",
			in: directory,
			info: [
				"CFBundleDisplayName": "Display Name Only",
				"CFBundleExecutable": "Display Name Only",
				"CFBundleIdentifier": "com.example.display-name-only",
				"CFBundleShortVersionString": "1.2.3",
				"CFBundleVersion": "123"
			]
		)

		let bundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

		XCTAssertEqual(bundle.name, "Display Name Only")
	}

	func testCollectsAppUsingBuildVersionWhenShortVersionIsMissing() throws {
		let directory = try makeTemporaryDirectory()
		let appURL = try makeAppBundle(
			named: "Build Version Only",
			in: directory,
			info: [
				"CFBundleName": "Build Version Only",
				"CFBundleExecutable": "Build Version Only",
				"CFBundleIdentifier": "com.example.build-version-only",
				"CFBundleVersion": "456"
			]
		)

		let bundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

		XCTAssertEqual(bundle.version.buildNumber, "456")
		XCTAssertNil(bundle.version.versionNumber)
	}

	private func makeTemporaryDirectory() throws -> URL {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		addTeardownBlock {
			try? FileManager.default.removeItem(at: directory)
		}
		return directory
	}

	private func makeAppBundle(named name: String, in directory: URL, info: [String: String]) throws -> URL {
		let appURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
		let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
		let plistURL = contentsURL.appendingPathComponent("Info.plist")

		try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
		let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
		try data.write(to: plistURL)

		return appURL
	}

}

private func homebrewEntry(token: String, bundleIdentifier: String) throws -> UpdateRepository.Entry {
	let json = """
	{
		"token": "\(token)",
		"version": "1.0",
		"artifacts": [
			{
				"app": ["Example App.app"]
			},
			{
				"zap": [
					{
						"trash": [
							"~/Library/Preferences/\(bundleIdentifier).plist"
						]
					}
				]
			}
		],
		"depends_on": {
			"macos": {}
		}
	}
	"""

	return try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))
}
