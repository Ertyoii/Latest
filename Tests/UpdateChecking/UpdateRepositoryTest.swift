//
//  UpdateRepositoryTest.swift
//  Latest Tests
//
//  Structural split from the original implementation.
//

import CryptoKit
import XCTest
@testable import Latest

final class UpdateRepositoryTest: XCTestCase {
	func testRenamedCodexAppDoesNotMatchConsumerChatGPTCask() {
		XCTAssertTrue(UpdateRepository.isLocallyExcludedFromHomebrewMatching("com.openai.codex"))
		XCTAssertFalse(UpdateRepository.isLocallyExcludedFromHomebrewMatching("com.openai.chat"))
	}

	func testRenamedCodexAppUsesItsOfficialSparkleFeed() {
		let feedURL = SparkleFeed.feedURL(
			from: [:],
			bundleIdentifier: "com.openai.codex",
			bundleURL: URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true)
		)

		XCTAssertEqual(
			feedURL?.absoluteString,
			"https://persistent.oaistatic.com/codex-app-prod/appcast.xml"
		)
	}
	func testHomebrewCaskEntryUsesImmediateFallbackWithoutGuessingHomepagePaths() throws {
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

		guard case .genericMetadata(let fallbackHTML) = entry.releaseNotes else {
			return XCTFail("Expected separately classified Homebrew metadata")
		}

		XCTAssertTrue(fallbackHTML.contains("Example App 2.4.1"))
		XCTAssertTrue(fallbackHTML.contains("Notes, tasks &amp; reminders"))
		XCTAssertTrue(fallbackHTML.contains("https://example.com/"))
		XCTAssertFalse(fallbackHTML.contains("https://example.com/changelog"))
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

		guard case .githubRelease(let apiURL, let fallbackHTML) = entry.releaseNotes else {
			return XCTFail("Expected GitHub release notes")
		}

		XCTAssertEqual(apiURL.absoluteString, "https://api.github.com/repos/bitgapp/eqMac/releases/tags/v1.8.15")
		XCTAssertNil(fallbackHTML)
	}

	func testHomebrewCaskEntryDerivesLatestGitHubReleaseFromLatestDownloadURL() throws {
		let json = """
		{
			"token": "example-app",
			"version": "2.4.1",
			"name": ["Example App"],
			"homepage": "https://example.com/",
			"url": "https://github.com/example/example-app/releases/latest/download/Example.zip",
			"artifacts": [{ "app": ["Example App.app"] }],
			"depends_on": { "macos": {} }
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .githubRelease(let apiURL, _) = entry.releaseNotes else {
			return XCTFail("Expected GitHub release notes")
		}

		XCTAssertEqual(apiURL.absoluteString, "https://api.github.com/repos/example/example-app/releases/latest")
		XCTAssertEqual(
			ReleaseNotesProvider.githubReleaseWebURL(fromAPIURL: apiURL)?.absoluteString,
			"https://github.com/example/example-app/releases/latest"
		)
	}

	func testHomebrewCaskEntryDerivesLatestGitHubReleaseFromRepositoryHomepage() throws {
		let json = """
		{
			"token": "example-app",
			"version": "2.4.1",
			"name": ["Example App"],
			"homepage": "https://github.com/example/example-app/",
			"url": "https://downloads.example.com/Example.zip",
			"artifacts": [{ "app": ["Example App.app"] }],
			"depends_on": { "macos": {} }
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .githubRelease(let apiURL, _) = entry.releaseNotes else {
			return XCTFail("Expected GitHub release notes")
		}

		XCTAssertEqual(apiURL.absoluteString, "https://api.github.com/repos/example/example-app/releases/latest")
	}

	func testHomebrewNonAppCaskDoesNotConstructReleaseNotes() throws {
		let json = """
		{
			"token": "example-font",
			"version": { "unexpected": true },
			"name": ["Example Font"],
			"homepage": 42,
			"artifacts": [{ "font": ["Example.ttf"] }],
			"depends_on": "not-app-metadata"
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		XCTAssertTrue(entry.names.isEmpty)
		XCTAssertTrue(entry.version.isEmpty)
		XCTAssertNil(entry.releaseNotes)
	}

	func testHomebrewCaskEntryUsesKnownReleaseNotesCatalogBeforeHomepageGuesses() throws {
		let json = """
		{
			"token": "1password",
			"version": "8.12.22",
			"name": ["1Password"],
			"desc": "Password manager",
			"homepage": "https://1password.com/",
			"url": "https://downloads.1password.com/mac/1Password.zip",
			"artifacts": [
				{
					"app": ["1Password.app"]
				}
			],
			"depends_on": {
				"macos": {}
			}
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML) = entry.releaseNotes else {
			return XCTFail("Expected catalog changelog release notes")
		}

		XCTAssertEqual(urls, [URL(string: "https://releases.1password.com/mac/stable/")!])
		XCTAssertEqual(versionPrefix, "8.12.22")
		XCTAssertFalse(allowsLatestFallback)
		XCTAssertNil(fallbackHTML)
	}
	func testHomebrewCaskEntryUsesObsidianCatalogBeforeGitHubDownloadURL() throws {
		let json = """
		{
			"token": "obsidian",
			"version": "1.12.7",
			"name": ["Obsidian"],
			"desc": "Knowledge base",
			"homepage": "https://obsidian.md/",
			"url": "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.12.7/Obsidian-1.12.7.dmg",
			"artifacts": [
				{
					"app": ["Obsidian.app"]
				}
			],
			"depends_on": {
				"macos": {}
			}
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .changelog(let urls, let versionPrefix, _, _) = entry.releaseNotes else {
			return XCTFail("Expected catalog changelog release notes")
		}

		XCTAssertEqual(urls, [URL(string: "https://obsidian.md/changelog/")!])
		XCTAssertEqual(versionPrefix, "1.12.7")
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

		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, _) = entry.releaseNotes else {
			return XCTFail("Expected changelog release notes")
		}

		XCTAssertEqual(versionPrefix, "3.4")
		XCTAssertTrue(allowsLatestFallback)
		XCTAssertEqual(urls, [URL(string: "https://cursor.com/changelog")!])
	}

	func testHomebrewCaskEntryUsesExactZedStableReleasePage() throws {
		let json = """
		{
			"token": "zed",
			"version": "1.4.4",
			"name": ["Zed"],
			"homepage": "https://zed.dev/",
			"url": "https://zed.dev/api/releases/stable/1.4.4/Zed-aarch64.dmg",
			"artifacts": [
				{
					"app": ["Zed.app"]
				}
			],
			"depends_on": {
				"macos": {}
			}
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, _) = entry.releaseNotes else {
			return XCTFail("Expected changelog release notes")
		}

		XCTAssertEqual(versionPrefix, "1.4.4")
		XCTAssertFalse(allowsLatestFallback)
		XCTAssertEqual(urls, [URL(string: "https://zed.dev/releases/stable/1.4.4")!])
	}

	func testHomebrewCaskEntryUsesExactZedPreviewReleasePage() throws {
		let json = """
		{
			"token": "zed@preview",
			"version": "1.4.5",
			"name": ["Zed Preview"],
			"homepage": "https://zed.dev/",
			"url": "https://zed.dev/api/releases/preview/1.4.5/Zed-aarch64.dmg",
			"artifacts": [
				{
					"app": ["Zed Preview.app"]
				}
			],
			"depends_on": {
				"macos": {}
			}
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, _) = entry.releaseNotes else {
			return XCTFail("Expected changelog release notes")
		}

		XCTAssertEqual(versionPrefix, "1.4.5")
		XCTAssertFalse(allowsLatestFallback)
		XCTAssertEqual(urls, [URL(string: "https://zed.dev/releases/preview/1.4.5")!])
	}

	func testHomebrewCaskEntryProvidesFallbackReleaseNotesWhenNoChangelogExists() throws {
		let json = """
		{
			"token": "expressvpn",
			"version": "14.1.1.13156",
			"name": ["ExpressVPN"],
			"desc": "VPN client for secure & private internet access",
			"artifacts": [
				{
					"uninstall": [
						{
							"quit": "com.express.vpn",
							"delete": "/Applications/ExpressVPN.app"
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

		guard case .genericMetadata(let html) = entry.releaseNotes else {
			return XCTFail("Expected separately classified Homebrew metadata")
		}

		XCTAssertTrue(html.contains("ExpressVPN 14.1.1.13156"))
		XCTAssertTrue(html.contains("secure &amp; private"))
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
