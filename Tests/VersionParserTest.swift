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

	func testHomebrewCaskEntryUsesHomepageChangelogCandidatesWithoutMetadataAsNotes() throws {
		let json = """
		{
			"token": "example-app",
			"version": "2.4.1",
			"name": ["Example App"],
			"desc": "Notes, tasks & reminders",
			"homepage": "https://example.com/",
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

		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback) = entry.releaseNotes else {
			return XCTFail("Expected changelog release notes")
		}

		XCTAssertEqual(versionPrefix, "2.4")
		XCTAssertFalse(allowsLatestFallback)
		XCTAssertEqual(urls.first?.absoluteString, "https://example.com/changelog")
		XCTAssertFalse(urls.map(\.absoluteString).contains("Notes, tasks & reminders"))
	}

	func testHomebrewCaskEntryDerivesGitHubReleaseNotesFromDownloadURL() throws {
		let json = """
		{
			"token": "eqmac",
			"version": "1.8.15",
			"name": ["eqMac"],
			"homepage": "https://eqmac.app/",
			"url": "https://github.com/bitgapp/eqMac/releases/download/v1.8.15/eqMac.dmg",
			"artifacts": [
				{
					"app": ["eqMac.app"]
				}
			],
			"depends_on": {
				"macos": {}
			}
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .githubRelease(let apiURL) = entry.releaseNotes else {
			return XCTFail("Expected GitHub release notes")
		}

		XCTAssertEqual(apiURL.absoluteString, "https://api.github.com/repos/bitgapp/eqMac/releases/tags/v1.8.15")
	}

	func testHomebrewCaskEntryUsesCursorChangelogSource() throws {
		let json = """
		{
			"token": "cursor",
			"version": "3.4.16,abcdef",
			"name": ["Cursor"],
			"homepage": "https://www.cursor.com/",
			"url": "https://downloads.cursor.com/production/abcdef/darwin/arm64/Cursor-darwin-arm64.zip",
			"artifacts": [
				{
					"app": ["Cursor.app"]
				}
			],
			"depends_on": {
				"macos": {}
			}
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback) = entry.releaseNotes else {
			return XCTFail("Expected changelog release notes")
		}

		XCTAssertEqual(versionPrefix, "3.4")
		XCTAssertTrue(allowsLatestFallback)
		XCTAssertEqual(urls, [URL(string: "https://cursor.com/changelog")!])
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
		XCTAssertFalse(entry.requiresBundleIdentifierMatch)
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
		XCTAssertEqual(entry.bundleIdentifiers, ["com.garmin.renu.client"])
		XCTAssertTrue(entry.requiresBundleIdentifierMatch)
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

	func testReleaseNotesMarkupKeepsOnlyRelevantVersionSection() throws {
		let changelog = """
		eqMac Changelog
		v1.8.15 - AirPods loop fix
		- Fixed AirPods causing eqMac to go into a device swap loop and freezing
		v1.8.14 - Device Routing fixes
		- Fixed Output Device routing issues introduced in v1.8.13
		"""

		let string = try ReleaseNotesMarkup.attributedString(from: changelog, baseURL: nil, relevantVersion: "1.8.15").get()

		XCTAssertTrue(string.string.contains("AirPods loop fix"))
		XCTAssertFalse(string.string.contains("Device Routing fixes"))
	}

	func testReleaseNotesMarkupExtractsFirstSectionFromVersionlessChangelog() throws {
		let changelog = """
		Changelog
		May 13, 2026
		Development environments for cloud agents
		Agents can now configure environments.
		May 11, 2026
		Cursor in Microsoft Teams
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantText(from: changelog, version: "3.4", allowFirstSectionFallback: true))

		XCTAssertTrue(text.contains("Development environments"))
		XCTAssertFalse(text.contains("Cursor in Microsoft Teams"))
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

	func testBundleModificationDateUsesContentsWhenPackageRootHasArchiveTimestamp() throws {
		let directory = try makeTemporaryDirectory()
		let appURL = try makeAppBundle(
			named: "Archive Timestamp",
			in: directory,
			info: [
				"CFBundleName": "Archive Timestamp",
				"CFBundleExecutable": "Archive Timestamp",
				"CFBundleIdentifier": "com.example.archive-timestamp",
				"CFBundleVersion": "1"
			]
		)
			let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
			let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
			let archiveTimestamp = Date(timeIntervalSince1970: 315504000)
			let contentsTimestamp = Date(timeIntervalSince1970: 1_778_179_586)

			try setModificationDate(archiveTimestamp, for: appURL)
			try setModificationDate(contentsTimestamp, for: contentsURL)
			try setModificationDate(contentsTimestamp, for: infoPlistURL)

		let bundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

		XCTAssertEqual(bundle.modificationDate, contentsTimestamp)
	}

	func testCollectingUpdatedBundleReadsCurrentInfoPlistVersions() throws {
		let directory = try makeTemporaryDirectory()
		let appURL = try makeAppBundle(
			named: "Updated In Place",
			in: directory,
			info: [
				"CFBundleName": "Updated In Place",
				"CFBundleExecutable": "Updated In Place",
				"CFBundleIdentifier": "com.example.updated-in-place",
				"CFBundleShortVersionString": "1.2.3",
				"CFBundleVersion": "123"
			]
		)

		let oldBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))
		XCTAssertEqual(oldBundle.version.versionNumber, "1.2.3")
		XCTAssertEqual(oldBundle.version.buildNumber, "123")

		try writeInfoPlist(
			forAppAt: appURL,
			info: [
				"CFBundleName": "Updated In Place",
				"CFBundleExecutable": "Updated In Place",
				"CFBundleIdentifier": "com.example.updated-in-place",
				"CFBundleShortVersionString": "1.2.5",
				"CFBundleVersion": "125"
			]
		)

		let updatedBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))
		XCTAssertEqual(updatedBundle.version.versionNumber, "1.2.5")
		XCTAssertEqual(updatedBundle.version.buildNumber, "125")
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

		try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
		try writeInfoPlist(forAppAt: appURL, info: info)

		return appURL
	}

	private func writeInfoPlist(forAppAt appURL: URL, info: [String: String]) throws {
		let plistURL = appURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
		let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
		try data.write(to: plistURL)
	}

	private func setModificationDate(_ date: Date, for url: URL) throws {
		try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
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
