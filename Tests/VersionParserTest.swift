//
//  VersionParserTest.swift
//  Latest Tests
//
//  Created by Max Langer on 29.11.23.
//  Copyright © 2023 Max Langer. All rights reserved.
//

import CryptoKit
import XCTest
@testable import Latest


final class VersionParserTest: XCTestCase {
	func testRenamedCodexAppDoesNotMatchConsumerChatGPTCask() {
		XCTAssertTrue(UpdateRepository.isLocallyExcludedFromHomebrewMatching("com.openai.codex"))
		XCTAssertFalse(UpdateRepository.isLocallyExcludedFromHomebrewMatching("com.openai.chat"))
	}

	func testRenamedCodexAppUsesItsOfficialSparkleFeed() {
		let feedURL = Sparke.feedURL(
			from: [:],
			bundleIdentifier: "com.openai.codex",
			bundleURL: URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true)
		)

		XCTAssertEqual(
			feedURL?.absoluteString,
			"https://persistent.oaistatic.com/codex-app-prod/appcast.xml"
		)
	}

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

	func testReleaseNotesSourceCatalogUsesBetterDisplayGitHubReleaseAPI() throws {
		let bundle = App.Bundle(
			version: Version(versionNumber: "4.3.3", buildNumber: "50020"),
			name: "BetterDisplay",
			bundleIdentifier: "pro.betterdisplay.BetterDisplay",
			fileURL: URL(fileURLWithPath: "/Applications/BetterDisplay.app", isDirectory: true),
			source: .sparkle
		)

		guard case .githubRelease(let apiURL, let fallbackHTML) = ReleaseNotesSourceCatalog.releaseNotes(
			for: bundle,
			remoteVersion: Version(versionNumber: "4.3.4", buildNumber: "50021")
		) else {
			return XCTFail("Expected BetterDisplay GitHub release API")
		}

		XCTAssertEqual(apiURL.absoluteString, "https://api.github.com/repos/waydabber/BetterDummy/releases/tags/v4.3.4")
		XCTAssertTrue(fallbackHTML?.contains("BetterDisplay 4.3.4") == true)
	}

	func testReleaseNotesSourceCatalogNormalizesBetterDisplaySparkleReleaseNotesLink() throws {
		let bundle = App.Bundle(
			version: Version(versionNumber: "4.3.3", buildNumber: "50020"),
			name: "BetterDisplay",
			bundleIdentifier: "pro.betterdisplay.BetterDisplay",
			fileURL: URL(fileURLWithPath: "/Applications/BetterDisplay.app", isDirectory: true),
			source: .sparkle
		)

		guard case .githubRelease(let apiURL, let fallbackHTML) = ReleaseNotesSourceCatalog.releaseNotes(
			forSparkleReleaseNotesURL: URL(string: "https://waydabber.github.io/BetterDisplay/changelog.html?tag=v4.3.4")!,
			bundle: bundle,
			remoteVersion: Version(versionNumber: "4.3.4", buildNumber: "50021")
		) else {
			return XCTFail("Expected BetterDisplay appcast link to resolve to its backing GitHub release")
		}

		XCTAssertEqual(apiURL.absoluteString, "https://api.github.com/repos/waydabber/BetterDummy/releases/tags/v4.3.4")
		XCTAssertTrue(fallbackHTML?.contains("BetterDisplay 4.3.4") == true)
	}

	func testReleaseNotesSourceCatalogUsesTelegramDesktopChangelog() throws {
		let json = """
		{
			"token": "telegram-desktop",
			"version": "6.9.2",
			"name": ["Telegram"],
			"homepage": "https://desktop.telegram.org/",
			"url": "https://updates.tdesktop.com/tmac/tsetup.6.9.2.dmg",
			"artifacts": [
				{
					"app": ["Telegram.app"]
				}
			],
			"depends_on": {
				"macos": {}
			}
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML) = entry.releaseNotes else {
			return XCTFail("Expected Telegram Desktop changelog")
		}

		XCTAssertEqual(urls.map(\.absoluteString), ["https://raw.githubusercontent.com/telegramdesktop/tdesktop/dev/changelog.txt"])
		XCTAssertEqual(versionPrefix, "6.9.2")
		XCTAssertFalse(allowsLatestFallback)
		XCTAssertNil(fallbackHTML)
	}

	func testReleaseNotesSourceCatalogUsesDockerDesktopMarkdownSource() throws {
		let json = """
		{
			"token": "docker-desktop",
			"version": "4.77.0,228796",
			"name": ["Docker"],
			"homepage": "https://www.docker.com/products/docker-desktop/",
			"url": "https://desktop.docker.com/mac/main/arm64/228796/Docker.dmg",
			"artifacts": [
				{
					"app": ["Docker.app"]
				}
			],
			"depends_on": {
				"macos": {}
			}
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML) = entry.releaseNotes else {
			return XCTFail("Expected Docker Desktop changelog release notes")
		}

		XCTAssertEqual(urls, [URL(string: "https://docs.docker.com/desktop/release-notes.md")!])
		XCTAssertEqual(versionPrefix, "4.77.0")
		XCTAssertFalse(allowsLatestFallback)
		XCTAssertNil(fallbackHTML)
	}

	func testReleaseNotesSourceCatalogUsesChromeReleaseBlog() throws {
		let json = """
		{
			"token": "google-chrome",
			"version": "149.0.7827.115",
			"name": ["Google Chrome"],
			"homepage": "https://www.google.com/chrome/",
			"url": "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg",
			"artifacts": [
				{
					"app": ["Google Chrome.app"]
				}
			],
			"depends_on": {
				"macos": {}
			}
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML) = entry.releaseNotes else {
			return XCTFail("Expected Chrome release blog notes")
		}

		XCTAssertEqual(urls, [URL(string: "https://chromereleases.googleblog.com/")!])
		XCTAssertEqual(versionPrefix, "149.0.7827.115")
		XCTAssertFalse(allowsLatestFallback)
		XCTAssertNil(fallbackHTML)
	}

	func testReleaseNotesSourceCatalogDoesNotUseNotionProductReleases() {
		let releaseNotes = ReleaseNotesSourceCatalog.releaseNotes(
			forHomebrewToken: "notion",
			version: Version(versionNumber: "7.21.0", buildNumber: nil)
		)

		XCTAssertNil(releaseNotes)
	}

	func testReleaseNotesSourceCatalogUsesBrunoGitHubReleaseForBundle() throws {
		let bundle = App.Bundle(
			version: Version(versionNumber: "3.4.1", buildNumber: nil),
			name: "Bruno",
			bundleIdentifier: "com.usebruno.app",
			fileURL: URL(fileURLWithPath: "/Applications/Bruno.app", isDirectory: true),
			source: .sparkle
		)

		guard case .githubRelease(let apiURL, let fallbackHTML) = ReleaseNotesSourceCatalog.releaseNotes(
			for: bundle,
			remoteVersion: Version(versionNumber: "3.4.2", buildNumber: nil)
		) else {
			return XCTFail("Expected Bruno GitHub release notes")
		}

		XCTAssertEqual(apiURL.absoluteString, "https://api.github.com/repos/usebruno/bruno/releases/tags/v3.4.2")
		XCTAssertNil(fallbackHTML)
	}

	func testElectronReleaseNotesSourceReadsGitHubProviderConfiguration() {
		let configuration = """
		provider: github
		owner: example-org
		repo: example-app
		updaterCacheDirName: example-updater
		"""

		XCTAssertEqual(
			ElectronReleaseNotesSource.githubReleaseAPIURL(from: configuration)?.absoluteString,
			"https://api.github.com/repos/example-org/example-app/releases/latest"
		)
		XCTAssertNil(
			ElectronReleaseNotesSource.githubReleaseAPIURL(
				from: "provider: generic\nurl: https://updates.example.com"
			)
		)
	}

	func testReleaseNotesSourceCatalogUsesBundledElectronUpdaterConfiguration() throws {
		let appURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("Electron-\(UUID().uuidString).app", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: appURL) }

		let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
		try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
		let configuration = "provider: github\nowner: example-org\nrepo: desktop-client\n"
		try Data(configuration.utf8).write(to: resourcesURL.appendingPathComponent("app-update.yml"))

		let bundle = App.Bundle(
			version: Version(versionNumber: "1.0", buildNumber: nil),
			name: "Uncatalogued Electron App",
			bundleIdentifier: "com.example.uncatalogued-electron",
			fileURL: appURL,
			source: .none
		)
		let remoteVersion = Version(versionNumber: "2.0", buildNumber: nil)

		guard case .githubRelease(let apiURL, let fallbackHTML) = ReleaseNotesSourceCatalog.releaseNotes(
			for: bundle,
			remoteVersion: remoteVersion
		) else {
			return XCTFail("Expected Electron GitHub release notes")
		}

		XCTAssertEqual(apiURL.absoluteString, "https://api.github.com/repos/example-org/desktop-client/releases/latest")
		XCTAssertNil(fallbackHTML)
	}

	func testReleaseNotesSourceCatalogCoversPopularNonGitHubApps() throws {
		let version = Version(versionNumber: "4.46.96", buildNumber: nil)
		let expectedURLs = [
			"microsoft-edge": "https://learn.microsoft.com/en-us/deployedge/microsoft-edge-relnote-stable-channel",
			"raycast": "https://www.raycast.com/changelog",
			"slack": "https://slack.com/release-notes/mac",
			"warp": "https://docs.warp.dev/changelog"
		]

		for (token, expectedURL) in expectedURLs {
			guard case .changelog(let urls, let versionPrefix, _, _) = ReleaseNotesSourceCatalog.releaseNotes(
				forHomebrewToken: token,
				version: version
			) else {
				return XCTFail("Expected catalog changelog for \(token)")
			}
			XCTAssertEqual(urls.map(\.absoluteString), [expectedURL])
			XCTAssertEqual(versionPrefix, "4.46.96")
		}
	}

	func testEveryCatalogHomebrewTokenProducesAConcreteRoute() {
		let version = Version(versionNumber: "2026.1.4", buildNumber: "261.26222.59")
		let tokens = ReleaseNotesSourceCatalog.catalogHomebrewTokens

		XCTAssertGreaterThanOrEqual(tokens.count, 55)
		for token in tokens {
			XCTAssertNotNil(
				ReleaseNotesSourceCatalog.releaseNotes(
					forHomebrewToken: token,
					version: version
				),
				"Missing release-note route for \(token)"
			)
		}
	}

	func testReleaseNotesSourceCatalogUsesGhosttySourceMarkdown() throws {
		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, _) = ReleaseNotesSourceCatalog.releaseNotes(
			forHomebrewToken: "ghostty",
			version: Version(versionNumber: "1.3.1", buildNumber: nil)
		) else {
			return XCTFail("Expected Ghostty changelog release notes")
		}

		XCTAssertEqual(urls, [URL(string: "https://raw.githubusercontent.com/ghostty-org/website/main/docs/install/release-notes/1-3-1.mdx")!])
		XCTAssertEqual(versionPrefix, "1.3.1")
		XCTAssertFalse(allowsLatestFallback)
	}

	func testReleaseNotesSourceCatalogUsesObsidianChangelog() throws {
		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML) = ReleaseNotesSourceCatalog.releaseNotes(
			forHomebrewToken: "obsidian",
			version: Version(versionNumber: "1.12.7", buildNumber: nil)
		) else {
			return XCTFail("Expected Obsidian changelog release notes")
		}

		XCTAssertEqual(urls, [URL(string: "https://obsidian.md/changelog/")!])
		XCTAssertEqual(versionPrefix, "1.12.7")
		XCTAssertFalse(allowsLatestFallback)
		XCTAssertNil(fallbackHTML)
	}

	func testReleaseNotesSourceCatalogUsesVersionedJetBrainsWhatsNewPage() throws {
		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, _) = ReleaseNotesSourceCatalog.releaseNotes(
			forHomebrewToken: "intellij-idea",
			version: Version(versionNumber: "2026.1.4", buildNumber: "261.26222.65")
		) else {
			return XCTFail("Expected JetBrains What's New release notes")
		}

		XCTAssertEqual(urls, [URL(string: "https://www.jetbrains.com/idea/whatsnew/2026-1/")!])
		XCTAssertEqual(versionPrefix, "2026.1")
		XCTAssertFalse(allowsLatestFallback)
	}

	func testReleaseNotesSourceCatalogUsesRogueAmoebaProductHistory() throws {
		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, _) = ReleaseNotesSourceCatalog.releaseNotes(
			forHomebrewToken: "audio-hijack",
			version: Version(versionNumber: "4.5.9", buildNumber: nil)
		) else {
			return XCTFail("Expected Rogue Amoeba release notes")
		}

		XCTAssertEqual(urls.first?.host, "rogueamoeba.com")
		XCTAssertEqual(URLComponents(url: try XCTUnwrap(urls.first), resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "Audio Hijack")
		XCTAssertEqual(versionPrefix, "4.5.9")
		XCTAssertFalse(allowsLatestFallback)
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

	@MainActor
	func testOffMainReleaseNotesPreparationPreservesRenderedOutput() async throws {
		let markup = """
		<h2>Version 2.4.1</h2>
		<ul>
			<li>Improved update discovery performance.</li>
			<li>Fixed release note selection.</li>
		</ul>
		<h2>Version 2.4.0</h2>
		<p>Older release details.</p>
		"""

		let synchronous = try ReleaseNotesMarkup.attributedString(
			from: markup,
			baseURL: URL(string: "https://example.com/changelog"),
			relevantVersion: "2.4.1"
		).get()
		let preparedOffMain = try await ReleaseNotesMarkup.attributedStringByPreparingOffMain(
			from: markup,
			baseURL: URL(string: "https://example.com/changelog"),
			relevantVersion: "2.4.1"
		).get()

		XCTAssertEqual(preparedOffMain.string, synchronous.string)
	}

	func testMarkdownReleaseNotesStripFrontMatterAndInlineMarkup() throws {
		let markdown = """
		---
		title: Ghostty 1.3.1
		description: |-
		  Release notes for Ghostty 1.3.1, released on March 13, 2026.
		---
		Ghostty 1.3.1 includes changes from
		**15 contributors** over **100 commits**. This is a patch release
		focused on fixing regressions introduced in 1.3.0, especially on macOS.
		**Highlights
		macOS Mouse Selection Bugs Fixed**
		PRs: GH-11276
		"""

		let string = try ReleaseNotesMarkup.attributedString(from: markdown, baseURL: nil, relevantVersion: "1.3.1").get()

		XCTAssertTrue(string.string.contains("Ghostty 1.3.1 includes changes"))
		XCTAssertTrue(string.string.contains("15 contributors over 100 commits"))
		XCTAssertTrue(string.string.contains("macOS Mouse Selection Bugs Fixed"))
		XCTAssertFalse(string.string.contains("title:"))
		XCTAssertFalse(string.string.contains("description:"))
		XCTAssertFalse(string.string.contains("**"))
		XCTAssertFalse(string.string.contains("---"))

		let compactMarkdown = "--- title: Ghostty 1.3.1 description: |- Release notes for Ghostty 1.3.1, released on March 13, 2026. --- Ghostty 1.3.1 includes changes from **15 contributors** over **100 commits**. This is a patch release focused on fixing regressions introduced in 1.3.0."
		let compactString = try ReleaseNotesMarkup.attributedString(from: compactMarkdown, baseURL: nil, relevantVersion: "1.3.1").get()
		XCTAssertTrue(compactString.string.hasPrefix("Ghostty 1.3.1 includes changes"))
		XCTAssertFalse(compactString.string.contains("title:"))
		XCTAssertFalse(compactString.string.contains("---"))

		let missingOpeningDelimiterMarkdown = """
		title: Ghostty 1.3.1
		description: |-
		Release notes for Ghostty 1.3.1, released on March 13, 2026.
		---
		Ghostty 1.3.1 includes changes from
		**15 contributors** over **100 commits**.
		"""
		let missingOpeningString = try ReleaseNotesMarkup.attributedString(from: missingOpeningDelimiterMarkdown, baseURL: nil, relevantVersion: "1.3.1").get()
		XCTAssertTrue(missingOpeningString.string.hasPrefix("Ghostty 1.3.1 includes changes"))
		XCTAssertFalse(missingOpeningString.string.contains("description:"))
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

	func testReleaseNotesMarkupKeepsOnlyCurrentReleaseFromHTMLHistory() throws {
		let html = """
		<h2>AppCleaner 3.6.8 - 4 July, 2023</h2>
		<ul>
			<li>New app icon.</li>
			<li>Allow searching for related files of system apps.</li>
		</ul>
		<h2>AppCleaner 3.6.7 - 9 Dec, 2022</h2>
		<ul>
			<li>Fixed a bug causing SmartDelete to crash.</li>
		</ul>
		"""

		let string = try ReleaseNotesMarkup.attributedString(from: html, baseURL: nil, relevantVersion: "3.6.8").get()

		XCTAssertTrue(string.string.contains("AppCleaner 3.6.8"))
		XCTAssertTrue(string.string.contains("New app icon"))
		XCTAssertFalse(string.string.contains("AppCleaner 3.6.7"))
		XCTAssertFalse(string.string.contains("SmartDelete"))
	}

	func testReleaseNotesMarkupRejectsVersionOnlyAndLinkOnlyText() throws {
		XCTAssertThrowsError(try ReleaseNotesMarkup.attributedString(from: "v3.4.2", baseURL: nil, relevantVersion: "3.4.2").get())
		XCTAssertThrowsError(try ReleaseNotesMarkup.attributedString(from: "<a href=\"https://example.com/details\">Details</a><br><a href=\"https://example.com/history\">Recent version history</a>", baseURL: nil, relevantVersion: "0.95").get())
		XCTAssertThrowsError(try ReleaseNotesMarkup.attributedString(from: "1.12.7 https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/", baseURL: nil, relevantVersion: "1.12.7").get())
	}

	func testReleaseNotesMarkupPreservesPlainTextChangelogLineBreaks() throws {
		let changelog = """
		3.6 May 29, 2026
		Auto-review Run Mode
		Auto-review is a new run mode that allows Cursor to work for longer.
		Configure your run mode in Settings > Cursor Settings > Agents > Run Mode.
		3.5 May 20, 2026
		Shared Canvases
		"""

		let string = try ReleaseNotesMarkup.attributedString(from: changelog, baseURL: nil, relevantVersion: "3.6").get()

		XCTAssertTrue(string.string.contains("3.6 May 29, 2026\nAuto-review Run Mode"))
		XCTAssertFalse(string.string.contains("3.5 May 20, 2026"))
	}

	func testReleaseNotesMarkupSeparatesCompactedSparkleChangelogText() throws {
		let changelog = "3.6 May 29, 2026 · Changelog Auto-review Run Mode Auto-review is a new run mode that allows Cursor to work for longer with fewer approval prompts and safer execution. Configure your run mode in Settings > Cursor Settings > Agents > Run Mode."

		let string = try ReleaseNotesMarkup.attributedString(from: changelog, baseURL: nil, relevantVersion: "3.6").get()

		XCTAssertTrue(string.string.contains("3.6 May 29, 2026 · Changelog\nAuto-review Run Mode\nAuto-review is a new run mode"))
	}

	func testReleaseNotesMarkupDeduplicatesRepeatedLeadingVersionTitle() throws {
		let markdown = """
		IINA 1.4.3
		IINA 1.4.3
		IINA 1.4.3 fixes important security issues and regressions.
		Bug Fixes
		- Fix a security issue.
		"""

		let string = try ReleaseNotesMarkup.attributedString(from: markdown, baseURL: nil, relevantVersion: "1.4.3").get()

		XCTAssertFalse(string.string.contains("IINA 1.4.3\nIINA 1.4.3\nIINA 1.4.3 fixes"))
		XCTAssertTrue(string.string.contains("IINA 1.4.3\nFixes important security issues and regressions."))
	}

	func testReleaseNotesMarkupRejectsNavigationPageNoise() throws {
		let html = """
		<html><head><title>The AI workspace that works for you. | Notion Product</title></head>
		<body>
		<nav>Notion Your AI workspace</nav>
		<p>-</p><p>Notion Calendar</p><p>-</p><p>Notion Mail</p><p>-</p>
		<p>Notion AI AI tools for work</p><p>-</p>
		<p>Agents Automate busywork</p><p>-</p>
		<p>AI Meeting Notes Perfectly written by AI</p><p>-</p>
		<p>Enterprise Search Find answers instantly</p><p>-</p>
		<p>Knowledge Base Centralize your knowledge</p><p>-</p>
		<p>Docs Simple and powerful</p><p>-</p>
		<p>Projects Manage any project</p>
		</body></html>
		"""

		XCTAssertThrowsError(try ReleaseNotesMarkup.attributedString(from: html, baseURL: URL(string: "https://www.notion.so/product")!, relevantVersion: "7.19").get())
	}

	func testReleaseNotesMarkupRejectsMojibakeText() throws {
		let gibberish = """
		Ñù¢x¿ëÆIw±¥ûs]z|².6 ç°^éÉ"st0Æñqd7wßZú¼üä,õ0!GéØ9cL=x16ãè³Ø´ÙÀ è på°7ÆgÝ².4,±ø}¿ õù±¯¾üiàpípjòÎ½c Ëp¾;µ¼,á{ÝVyÃ(ä¤Ç¶xs´i;»||
		³HxåÿXèÕõ%ÍÁ÷9 óke  ˜&ó¼öU#êÒùñÛà¸}Òäwö¦¾¶Ex2EöòËÕÿÚüæ8Å/xÜcDøþéõ@ãÚ
		"""

		XCTAssertThrowsError(try ReleaseNotesMarkup.attributedString(from: gibberish, baseURL: nil, relevantVersion: "5.80.6").get())
	}

	func testReleaseNotesMarkupKeepsShortControlTextBelowMojibakeThreshold() {
		let shortControlText = String(repeating: "\u{1}", count: 20)

		XCTAssertFalse(ReleaseNotesMarkup.looksLikeBinaryOrMojibakeText(shortControlText))
	}

	func testReleaseNotesMarkupSeparatesHTMLChangelogHeadings() throws {
		let html = """
		<a href="/changelog/3-6">3.6 May 29, 2026</a> · <a href="/changelog">Changelog</a><h1>Auto-review Run Mode</h1>
		<p>Auto-review is a new run mode that allows Cursor to work for longer.</p>
		<a href="/changelog/3-5">3.5 May 20, 2026</a><h1>Shared Canvases</h1>
		"""

		let string = try ReleaseNotesMarkup.attributedString(from: html, baseURL: URL(string: "https://cursor.com/changelog")!, relevantVersion: "3.6").get()

		XCTAssertTrue(string.string.contains("Changelog\nAuto-review Run Mode"))
		XCTAssertFalse(string.string.contains("Shared Canvases"))
	}

	func testReleaseNotesMarkupUsesCursorVersionHeadingBeforeBodyMention() throws {
		let changelog = """
		Changelog
		Jun 10, 2026
		Bugbot is now over 3x faster
		Available in Cursor 3.7+ and on cursor.com/agents.
		3.7 Jun 5, 2026
		Design Mode Improvements
		With Design Mode in the Cursor browser, you can click, draw, or describe changes by voice.
		3.6 May 29, 2026
		Auto-review Run Mode
		Auto-review is a new run mode that allows Cursor to work for longer.
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantText(from: changelog, version: "3.7", allowFirstSectionFallback: true))

		XCTAssertTrue(text.hasPrefix("3.7 Jun 5, 2026"))
		XCTAssertTrue(text.contains("Design Mode Improvements"))
		XCTAssertFalse(text.contains("Available in Cursor 3.7+"))
		XCTAssertFalse(text.contains("Auto-review Run Mode"))
	}

	func testReleaseNotesMarkupStopsCursorSectionAtNextDatedEntry() throws {
		let changelog = """
		3.7 Jun 5, 2026 · Changelog
		Design Mode Improvements
		With Design Mode in the Cursor browser, you can click, draw, or describe changes by voice.
		Jun 4, 2026 · Changelog
		Custom agent modes
		Custom agent modes let you define reusable instruction sets.
		Jun 3, 2026 · Changelog
		Background agents
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantText(from: changelog, version: "3.7", allowFirstSectionFallback: true))

		XCTAssertTrue(text.hasPrefix("3.7 Jun 5, 2026"))
		XCTAssertTrue(text.contains("Design Mode Improvements"))
		XCTAssertFalse(text.contains("Custom agent modes"))
		XCTAssertFalse(text.contains("Background agents"))
	}

	func testReleaseNotesMarkupExtractsFirstReleaseNotesURLFromStubText() throws {
		let text = "1.12.7 https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/"
		let url = try XCTUnwrap(ReleaseNotesMarkup.firstReleaseNotesURL(in: text, baseURL: nil))

		XCTAssertEqual(url.absoluteString, "https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/")
	}

	func testReleaseNotesMarkupExtractsChromeDesktopReleaseFromBlog() throws {
		let html = """
		<h2>Chrome for Android Update</h2>
		<p>Thursday, June 11, 2026</p>
		<p>Chrome 149 (149.0.7827.114) for Android is available.</p>
		<h2>Stable Channel Update for Desktop</h2>
		<p>Thursday, June 11, 2026</p>
		<p>The Stable channel has been updated to 149.0.7827.114/.115 for Windows and Mac and 149.0.7827.114 for Linux, which will roll out over the coming days/weeks.</p>
		<p>Security Fixes and Rewards</p>
		<p>This update includes 28 security fixes.</p>
		<p>Critical CVE-2026-12007: Use after free in Core.</p>
		<p>Google Chrome</p>
		<h2>Extended Stable Updates for Desktop</h2>
		<p>The Extended Stable channel has been updated to 148.0.7778.265 for Windows and Mac.</p>
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantChangelogText(
			fromHTML: html,
			version: "149.0.7827.115",
			pageURL: URL(string: "https://chromereleases.googleblog.com/")!,
			allowFirstSectionFallback: false
		))

		XCTAssertTrue(text.contains("Stable channel has been updated"))
		XCTAssertTrue(text.contains("28 security fixes"))
		XCTAssertFalse(text.contains("Android is available"))
		XCTAssertFalse(text.contains("Extended Stable channel"))
	}

	func testReleaseNotesMarkupExtractsChromeDesktopReleaseFromBloggerTemplate() throws {
		let html = """
		<div class='post'>
		<h2 class='title'>Chrome for Android Update</h2>
		<div class='post-content'>
		<script type='text/template'>
		<p>Chrome 149 (149.0.7827.114) for Android is available.</p>
		<div>Android releases contain the same security fixes as their corresponding <a href="https://chromereleases.googleblog.com/2026/06/stable-channel-update-for-desktop.html">Desktop releases</a> (Windows &amp; Mac: 149.0.7827.114/115, Linux: 149.0.7872.114) unless otherwise noted.</div>
		</script>
		</div>
		</div>
		<div class='post'>
		<h2 class='title'>Stable Channel Update for Desktop</h2>
		<div class='post-content'>
		<script type='text/template'>
		<p>The Stable channel has been updated to 149.0.7827.114/.115 for Windows and Mac and 149.0.7827.114 for Linux, which will roll out over the coming days/weeks.</p>
		<p>Security Fixes and Rewards</p>
		<p>This update includes 28 security fixes.</p>
		<p>Critical CVE-2026-12007: Use after free in Core.</p>
		</script>
		</div>
		</div>
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantChangelogText(
			fromHTML: html,
			version: "149.0.7827.115",
			pageURL: URL(string: "https://chromereleases.googleblog.com/")!,
			allowFirstSectionFallback: false
		))

		XCTAssertTrue(text.contains("Stable Channel Update for Desktop"))
		XCTAssertTrue(text.contains("28 security fixes"))
		XCTAssertFalse(text.contains("Android releases contain"))
	}

	func testReleaseNotesMarkupExtractsZedReleaseWithoutNavigationChrome() throws {
		let html = """
		<article>
		<p>Versions</p>
		<p>1.6.3</p>
		<p>1.5.5</p>
		<p>Version : 1.6.3</p>
		<p>Platform : macOS</p>
		<p>Trusted by world-class developers and industry leading teams</p>
		<h1>1.6.3</h1>
		<p>Jun 10, 2026</p>
		<p>macOS</p>
		<p>Loading...</p>
		<p>Windows</p>
		<p>Loading...</p>
		<p>Linux</p>
		<p>Loading...</p>
		<p>This week's release includes the ability to open a Git diff for a single file in its own dedicated tab from the Git panel.</p>
		<h2>Features</h2>
		<h3>AI</h3>
		<ul><li>Agent: Added a way to share skills via links.</li></ul>
		</article>
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantChangelogText(
			fromHTML: html,
			version: "1.6.3",
			pageURL: URL(string: "https://zed.dev/releases/stable/1.6.3")!,
			allowFirstSectionFallback: false
		))

		XCTAssertTrue(text.hasPrefix("1.6.3"))
		XCTAssertTrue(text.contains("This week's release includes"))
		XCTAssertTrue(text.contains("Agent: Added a way to share skills via links."))
		XCTAssertFalse(text.contains("Trusted by world-class developers"))
		XCTAssertFalse(text.contains("Version :"))
		XCTAssertFalse(text.contains("Loading"))
	}

	func testReleaseNotesMarkupExtractsZoomReleaseSectionWithoutVersionMatrix() throws {
		let html = """
		<article>
		<h1>Release notes for the Zoom Workplace app</h1>
		<h2>Released</h2>
		<h3>May 18, 2026</h3>
		<p>Note: This release was originally scheduled for May 11, but was delayed by one week.</p>
		<h4>Full versions</h4>
		<p>Windows</p><p>macOS</p><p>Linux</p><p>Android*</p>
		<p>7.0.5 (38856)</p><p>7.0.5 (81138)</p><p>7.0.5 (3034)</p><p>7.0.5 (40164)</p>
		<p>*The mobile releases require additional approval from their respective app stores.</p>
		<h4>New, enhanced, and changed features</h4>
		<p>Type Feature title Description Platforms</p>
		<p>General features</p>
		<p>New or enhanced feature Show or hide icon labels in the navigation bar Users can hide text labels on navigation bar app icons.</p>
		<p>Windows</p><p>macOS</p><p>Linux</p>
		<p>New or enhanced feature Support automatic sign-in when joining a meeting from a web browser Users who are signed into the Zoom web portal can be signed into the app during join flow.</p>
		<p>Windows</p><p>macOS</p><p>Linux</p>
		<h3>April 29, 2026</h3>
		<p>Older release details.</p>
		</article>
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantChangelogText(
			fromHTML: html,
			version: "7.0.5",
			pageURL: URL(string: "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222")!,
			allowFirstSectionFallback: false
		))

		XCTAssertTrue(text.hasPrefix("Zoom 7.0.5"))
		XCTAssertTrue(text.contains("May 18, 2026"))
		XCTAssertTrue(text.contains("Show or hide icon labels"))
		XCTAssertTrue(text.contains("Support automatic sign-in"))
		XCTAssertFalse(text.contains("Full versions"))
		XCTAssertFalse(text.contains("7.0.5 (38856)"))
		XCTAssertFalse(text.contains("Type Feature title Description Platforms"))
		XCTAssertFalse(text.contains("Older release details"))
	}

	func testReleaseNotesMarkupExtractsZoomReleaseSectionFromStructuredArticleBody() throws {
		let articleBody = """
		<p>Zoom provides up-to-date release notes for the Zoom Workplace app.</p>
		<h2>Released</h2>
		<h3>May 18, 2026</h3>
		<p><strong>Note</strong>: This release was originally scheduled for May 11, but was delayed by one week.</p>
		<h4>Full versions</h4>
		<article>
		<table><thead><tr><th>Windows</th><th>macOS</th><th>Linux</th><th>Android*</th></tr></thead>
		<tbody><tr><td>7.0.5 (38856)</td><td>7.0.5 (81138)</td><td>7.0.5 (3034)</td><td>7.0.5 (40164)</td></tr></tbody></table>
		</article>
		<p>*The mobile releases require additional approval from their respective app stores.</p>
		<h4>New, enhanced, and changed features</h4>
		<table><thead><tr><th>Type</th><th>Feature title</th><th>Description</th><th>Platforms</th></tr></thead>
		<tbody><tr><td>New or enhanced feature</td><td>Show or hide icon labels in the navigation bar</td><td>Users can hide text labels on navigation bar app icons in the Zoom Workplace desktop app.</td><td>Windows <br />macOS <br />Linux</td></tr></tbody></table>
		<h4>Resolved issues</h4>
		<table><tbody><tr><td>Minor bug fixes</td><td>Windows <br />macOS <br />Linux</td></tr></tbody></table>
		<h3>April 29, 2026</h3>
		<p>Older release details.</p>
		"""
		let jsonData = try JSONSerialization.data(withJSONObject: [
			"@context": "https://schema.org",
			"@type": "TechArticle",
			"articleBody": articleBody
		])
		let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
		let html = """
		<html>
		<head><script type="application/ld+json">\(json)</script></head>
		<body>
		<p>Windows</p><p>macOS</p><p>Linux</p><p>Android*</p>
		<p>7.0.5 (38856)</p><p>7.0.5 (81138)</p><p>7.0.5 (3034)</p><p>7.0.5 (40164)</p>
		</body>
		</html>
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantChangelogText(
			fromHTML: html,
			version: "7.0.5",
			pageURL: URL(string: "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222")!,
			allowFirstSectionFallback: false
		))

		XCTAssertTrue(text.hasPrefix("Zoom 7.0.5"))
		XCTAssertTrue(text.contains("May 18, 2026"))
		XCTAssertTrue(text.contains("Show or hide icon labels"))
		XCTAssertTrue(text.contains("Minor bug fixes"))
		XCTAssertFalse(text.contains("7.0.5 (38856)"))
		XCTAssertFalse(text.contains("Older release details"))

		let renderedText = try ReleaseNotesMarkup.attributedString(
			from: text,
			baseURL: URL(string: "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222")!,
			relevantVersion: "7.0.5"
		).get().string
		XCTAssertTrue(renderedText.contains("Show or hide icon labels"))
		XCTAssertTrue(renderedText.contains("Minor bug fixes"))
	}

	func testReleaseNotesProviderBuildsGitHubWebURLFromAPIURL() throws {
		let apiURL = URL(string: "https://api.github.com/repos/usebruno/bruno/releases/tags/v3.4.2")!
		let webURL = try XCTUnwrap(ReleaseNotesProvider.githubReleaseWebURL(fromAPIURL: apiURL))

		XCTAssertEqual(webURL.absoluteString, "https://github.com/usebruno/bruno/releases/tag/v3.4.2")
	}

	func testReleaseNotesProviderExtractsGitHubReleaseBodyHTML() throws {
		let html = """
		<main>
			<div data-test-selector="body-content" class="markdown-body tmp-my-3">
				<ul>
					<li>Fix possible crash in OpenGL init.</li>
					<li>Fix display of rich messages without text.</li>
				</ul>
				<div><p>Nested note stays in the release body.</p></div>
			</div>
			<div class="Box-footer">Assets 11</div>
		</main>
		"""

		let body = try XCTUnwrap(ReleaseNotesProvider.githubReleaseBodyHTML(fromHTML: html))
		let string = try ReleaseNotesMarkup.attributedString(
			from: body,
			baseURL: URL(string: "https://github.com/telegramdesktop/tdesktop/releases/tag/v6.9.2")!,
			relevantVersion: "6.9.2"
		).get()

		XCTAssertTrue(string.string.contains("Fix possible crash in OpenGL init."))
		XCTAssertTrue(string.string.contains("Nested note stays in the release body."))
		XCTAssertFalse(string.string.contains("Assets 11"))
	}

	func testReleaseNotesProviderExtractsLinkedNotesFromGitHubReleaseBody() throws {
		let html = """
		<div data-test-selector="body-content" class="markdown-body tmp-my-3">
			<p><a href="https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/">https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/</a></p>
		</div>
		"""

		let body = try XCTUnwrap(ReleaseNotesProvider.githubReleaseBodyHTML(fromHTML: html))
		let url = try XCTUnwrap(ReleaseNotesMarkup.firstReleaseNotesURL(in: body, baseURL: URL(string: "https://github.com/obsidianmd/obsidian-releases/releases/tag/v1.12.7")!))

		XCTAssertEqual(url.absoluteString, "https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/")
		XCTAssertThrowsError(try ReleaseNotesMarkup.attributedString(from: body, baseURL: nil, relevantVersion: "1.12.7").get())
	}

	func testReleaseNotesMarkupExtractsVersionedArticleFrom1PasswordPage() throws {
		let html = """
		<section class="c-updates">
			<article class="c-updates__release">
				<header>
					<time>June 2 2026</time>
					<h6>1Password for Mac 8.12.22</h6>
				</header>
				<div class="c-updates__content">
					<ul>
						<li>We&rsquo;ve improved the scrolling experience to better match typical macOS scrolling behavior.</li>
					</ul>
				</div>
			</article>
			<article class="c-updates__release">
				<header>
					<time>May 20 2026</time>
					<h6>1Password for Mac 8.12.21</h6>
				</header>
				<div class="c-updates__content">
					<ul><li>Older release notes should not be included.</li></ul>
				</div>
			</article>
		</section>
		"""

		let article = try XCTUnwrap(ReleaseNotesMarkup.releaseContentHTML(
			fromHTML: html,
			version: "8.12.22",
			pageURL: URL(string: "https://releases.1password.com/mac/stable/")!
		))
		let string = try ReleaseNotesMarkup.attributedString(
			from: article,
			baseURL: URL(string: "https://releases.1password.com/mac/stable/")!,
			relevantVersion: "8.12.22"
		).get()

		XCTAssertTrue(string.string.contains("1Password for Mac 8.12.22"))
		XCTAssertTrue(string.string.contains("improved the scrolling experience"))
		XCTAssertFalse(string.string.contains("Older release notes"))
	}

	func testReleaseNotesMarkupPrefersObsidianDesktopChangelogLink() throws {
		let html = """
		<a href="/changelog/2026-03-23-mobile-v1.12.7/">1.12.7 Mobile</a>
		<p>Includes all new features and bug fixes up to <a href="/changelog/2026-03-23-desktop-v1.12.7/">Obsidian Desktop v1.12.7</a>.</p>
		<a href="/changelog/2026-03-23-desktop-v1.12.7/">1.12.7 Desktop</a>
		"""

		let url = try XCTUnwrap(ReleaseNotesMarkup.linkedChangelogURL(
			fromHTML: html,
			version: "1.12.7",
			pageURL: URL(string: "https://obsidian.md/changelog/")!
		))

		XCTAssertEqual(url.absoluteString, "https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/")
	}

	func testReleaseNotesMarkupPrefersObsidianDesktopArticle() throws {
		let html = """
		<article>
			<h2>1.12.7 Mobile</h2>
			<p>Includes all new features and bug fixes up to Obsidian Desktop v1.12.7.</p>
		</article>
		<article>
			<h2>1.12.7 Desktop</h2>
			<h3>Improvements</h3>
			<p>The Obsidian Installer is now bundled with a new binary file for using the CLI.</p>
		</article>
		"""

		let article = try XCTUnwrap(ReleaseNotesMarkup.releaseContentHTML(
			fromHTML: html,
			version: "1.12.7",
			pageURL: URL(string: "https://obsidian.md/changelog/")!
		))
		let string = try ReleaseNotesMarkup.attributedString(
			from: article,
			baseURL: URL(string: "https://obsidian.md/changelog/")!,
			relevantVersion: "1.12.7"
		).get()

		XCTAssertTrue(string.string.contains("1.12.7 Desktop"))
		XCTAssertTrue(string.string.contains("Obsidian Installer"))
		XCTAssertFalse(string.string.contains("1.12.7 Mobile"))
	}

	func testReleaseNotesMarkupPrefersObsidianDesktopPlainTextSection() throws {
		let text = """
		Changelog
		June 9, 2026
		1.13.1 Mobile
		Includes all new features and bug fixes up to Obsidian Desktop v1.13.1.
		Improvements
		- Settings pages now have enough padding to scroll fully into view.
		June 9, 2026
		1.13.1 Desktop
		Improvements
		- Sliders now show a permanent label with the current value.
		No longer broken
		- Fixed choppy horizontal scrolling when sidebar tabs overflow.
		May 28, 2026
		1.13.0 Desktop
		Older notes should not be included.
		"""

		let relevantText = try XCTUnwrap(ReleaseNotesMarkup.relevantChangelogText(
			fromHTML: text,
			version: "1.13.1",
			pageURL: URL(string: "https://obsidian.md/changelog/")!,
			allowFirstSectionFallback: false
		))

		XCTAssertTrue(relevantText.contains("1.13.1 Desktop"))
		XCTAssertTrue(relevantText.contains("Sliders now show"))
		XCTAssertFalse(relevantText.contains("1.13.1 Mobile"))
		XCTAssertFalse(relevantText.contains("Older notes"))
	}

	func testReleaseNotesMarkupDoesNotUseObsidianIndexTypesetAsRelease() throws {
		let html = """
		<div class="typeset">
			<h2>1.13.1 Mobile</h2>
			<p>Includes all new features and bug fixes up to Obsidian Desktop v1.13.1.</p>
			<h2>1.13.1 Desktop</h2>
			<p>Sliders now show a permanent label with the current value.</p>
		</div>
		"""

		XCTAssertNil(ReleaseNotesMarkup.releaseContentHTML(
			fromHTML: html,
			version: "1.13.1",
			pageURL: URL(string: "https://obsidian.md/changelog/")!
		))

		XCTAssertNotNil(ReleaseNotesMarkup.releaseContentHTML(
			fromHTML: html,
			version: "1.13.1",
			pageURL: URL(string: "https://obsidian.md/changelog/2026-06-09-desktop-v1.13.1/")!
		))
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

	func testReleaseNotesMarkupSkipsVersionNavigationWhenFindingRelevantSection() throws {
		let changelog = """
		Versions
		• 1.4.4 • 1.4.3 • 1.4.2 • 1.3.7 • 1.3.6 • 1.3.5
		May 2026
		1.4.4
		May 28, 2026
		macOS
		- Fixed an issue where using GPT models would return an error.
		1.4.3
		May 28, 2026
		- Fixed GitHub Copilot Chat showing an empty model dropdown.
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantText(from: changelog, version: "1.4.4", allowFirstSectionFallback: false))

		XCTAssertFalse(text.contains("1.4.3 • 1.4.2"))
		XCTAssertTrue(text.contains("Fixed an issue where using GPT models"))
		XCTAssertFalse(text.contains("empty model dropdown"))
	}

	func testReleaseNotesMarkupSkipsZedVersionSidebarList() throws {
		let html = """
		<nav>
			<h2>Versions</h2>
			<a href="/releases/stable/1.6.3">1.6.3</a>
			<a href="/releases/stable/1.5.5">1.5.5</a>
			<a href="/releases/stable/1.5.4">1.5.4</a>
			<h2>Versions</h2>
			<a href="/releases/stable/1.6.3">1.6.3</a>
			<a href="/releases/stable/1.5.5">1.5.5</a>
			<a href="/releases/stable/1.5.4">1.5.4</a>
		</nav>
		<main>
			<h2>June 2026</h2>
			<p>* * *</p>
			<h2>1.6.3</h2>
			<p>Jun 10, 2026</p>
			<p>macOS</p>
			<p>Loading…</p>
			<p>Windows</p>
			<p>Loading...</p>
			<p>Linux</p>
			<p>This week's release includes the ability to open a Git diff for a single file.</p>
			<h3>Features</h3>
			<ul>
				<li>Agent: Added a way to share skills via links.</li>
			</ul>
			<h2>1.5.5</h2>
			<p>Jun 09, 2026</p>
			<ul>
				<li>Older release note.</li>
			</ul>
		</main>
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantChangelogText(fromHTML: html, version: "1.6.3", pageURL: URL(string: "https://zed.dev/releases/stable/1.6.3")!, allowFirstSectionFallback: false))

		XCTAssertTrue(text.hasPrefix("1.6.3"))
		XCTAssertTrue(text.contains("This week's release includes"))
		XCTAssertTrue(text.contains("Agent: Added a way to share skills"))
		XCTAssertFalse(text.contains("Versions"))
		XCTAssertFalse(text.contains("Loading"))
		XCTAssertFalse(text.contains("Older release note"))
	}

	func testReleaseNotesMarkupExtractsZedReleasePayloadBeforeVersionNavigation() throws {
		let html = """
		<div>Versions</div>
		<a href="/releases/stable/1.4.4">1.4.4</a>
		<a href="/releases/stable/1.4.3">1.4.3</a>
		<script>self.__next_f.push([1,"[[\\"$\\",\\"$L105\\",\\"Zed-aarch64.dmg\\",{\\"release\\":{\\"version\\":\\"1.4.4\\",\\"description\\":\\"- copilot: Fixed an issue where using GPT models would return an error in `invalid_request_body` ([#57979](https://github.com/zed-industries/zed/pull/57979))\\\\r\\\\n\\\\r\\\\n\\",\\"assets\\":[\\"Zed-aarch64.dmg\\"],\\"published_at\\":\\"2026-05-28T20:55:02.000Z\\",\\"channelType\\":\\"stable\\",\\"isLatest\\":true},\\"asset\\":\\"Zed-aarch64.dmg\\"}]]"])</script>
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.zedReleaseText(fromHTML: html, version: "1.4.4", pageURL: URL(string: "https://zed.dev/releases/stable/1.4.4")!))

		XCTAssertTrue(text.contains("invalid_request_body"))
		XCTAssertFalse(text.contains(#"\r"#))
		XCTAssertFalse(text.contains(#"\n"#))
		XCTAssertFalse(text.contains("1.4.3"))
		XCTAssertFalse(text.contains("Versions"))
	}

	func testReleaseNotesMarkupIgnoresZedReactServerDescriptionReference() throws {
		let html = """
		<script>self.__next_f.push([1,"[[\\"$\\",\\"$L105\\",\\"Zed-aarch64.dmg\\",{\\"release\\":{\\"version\\":\\"1.6.3\\",\\"description\\":\\"$106\\",\\"assets\\":[\\"Zed-aarch64.dmg\\"],\\"published_at\\":\\"2026-06-10T18:33:08.000Z\\",\\"channelType\\":\\"stable\\",\\"isLatest\\":true},\\"asset\\":\\"Zed-aarch64.dmg\\"}]]"])</script>
		<main>
			<p>Version : 1.6.3</p>
			<p>Platform : macOS</p>
			<p>Trusted by world-class developers and industry leading teams</p>
		</main>
		<script>self.__next_f.push([1,"106:T4b60,"])</script>
		<script>self.__next_f.push([1,"This week's release includes the ability to open a Git diff for a single file.\\r\\n\\r\\n## Features\\r\\n\\r\\n- Agent: Added a way to share skills via links.\\r\\n"])</script>
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.zedReleaseText(fromHTML: html, version: "1.6.3", pageURL: URL(string: "https://zed.dev/releases/stable/1.6.3")!))

		XCTAssertTrue(text.hasPrefix("This week's release"))
		XCTAssertTrue(text.contains("Agent: Added a way to share skills"))
		XCTAssertFalse(text.contains("$106"))
		XCTAssertFalse(text.contains("Version : 1.6.3"))
	}

	func testReleaseNotesMarkupExtractsRelevantSectionFromHTMLWithoutRendering() throws {
		let html = """
		<html>
		<head>
			<script>window.versions = ["1.4.3"];</script>
		</head>
		<body>
			<h2>1.4.4</h2>
			<p>Fixed &amp; improved<br>Added &#33; support</p>
			<h2>1.4.3</h2>
			<p>Previous release</p>
		</body>
		</html>
		"""

		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantChangelogText(fromHTML: html, version: "1.4.4", pageURL: URL(string: "https://example.com/changelog")!, allowFirstSectionFallback: false))

		XCTAssertTrue(text.contains("Fixed & improved"))
		XCTAssertTrue(text.contains("Added ! support"))
		XCTAssertFalse(text.contains("Previous release"))
		XCTAssertFalse(text.contains("window.versions"))
	}

	@MainActor
	func testReleaseNotesProviderInvalidatesCacheWhenReleaseNoteSourceChanges() async throws {
		let provider = ReleaseNotesProvider()
		let oldApp = makeReleaseNotesApp(html: "<p>Old release notes with bug fixes.</p>")
		let refreshedApp = makeReleaseNotesApp(html: "<p>Fresh release notes with improvements.</p>")

		let oldNotes = try await releaseNotes(for: oldApp, provider: provider)
		let refreshedNotes = try await releaseNotes(for: refreshedApp, provider: provider)

		XCTAssertTrue(oldNotes.string.contains("Old release notes"))
		XCTAssertTrue(refreshedNotes.string.contains("Fresh release notes"))
		XCTAssertFalse(refreshedNotes.string.contains("Old release notes"))
	}

	@MainActor
	func testReleaseNotesProviderRejectsDownloadLikeReleaseNotesURL() async {
		let provider = ReleaseNotesProvider()
		let app = makeReleaseNotesApp(releaseNotes: .url(url: URL(string: "https://example.com/Thunder.dmg")!))
		let expectation = expectation(description: "release notes completion")
		var capturedError: Error?

		provider.releaseNotes(for: app) { result in
			if case .failure(let error) = result {
				capturedError = error
			}
			expectation.fulfill()
		}

		await fulfillment(of: [expectation], timeout: 1)

		guard let error = capturedError as? LatestError,
		      case .releaseNotesUnavailable = error else {
			return XCTFail("Expected downloadable release note URLs to be rejected before the web loader.")
		}
	}

	@MainActor
	private func releaseNotes(for app: App, provider: ReleaseNotesProvider) async throws -> NSAttributedString {
		var result: ReleaseNotesProvider.ReleaseNotes?
		let expectation = expectation(description: "release notes completion")
		provider.releaseNotes(for: app) { notes in
			result = notes
			expectation.fulfill()
		}
		// HTML-to-attributed-string conversion can briefly exceed one second on a
		// busy debug XCTest host even though it runs fully off the network.
		await fulfillment(of: [expectation], timeout: 3)

		return try XCTUnwrap(result).get()
	}

	private func makeReleaseNotesApp(html: String) -> App {
		makeReleaseNotesApp(releaseNotes: .html(string: html))
	}

	private func makeReleaseNotesApp(releaseNotes: App.Update.ReleaseNotes) -> App {
		let bundle = App.Bundle(
			version: Version(versionNumber: "1.4.2", buildNumber: nil),
			name: "Zed",
			bundleIdentifier: "dev.zed.Zed",
			fileURL: URL(fileURLWithPath: "/Applications/Zed.app", isDirectory: true),
			source: .homebrew
		)
		let update = App.Update(
			app: bundle,
			remoteVersion: Version(versionNumber: "1.4.4", buildNumber: nil),
			minimumOSVersion: nil,
			source: .homebrew,
			date: nil,
			releaseNotes: releaseNotes,
			updateAction: .external(label: "Zed") { _ in }
		)

		return App(bundle: bundle, update: .success(update), isIgnored: false)
	}

}

final class BundleCollectorTest: XCTestCase {
	func testRenamedCodexBundleUsesCatalogedSparkleSource() throws {
		let directory = try makeTemporaryDirectory()
		let appURL = try makeAppBundle(
			named: "ChatGPT",
			in: directory,
			info: [
				"CFBundleName": "ChatGPT",
				"CFBundleExecutable": "ChatGPT",
				"CFBundleIdentifier": "com.openai.codex",
				"CFBundleShortVersionString": "26.707.51957",
				"CFBundleVersion": "5175"
			]
		)

		let bundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

		XCTAssertEqual(bundle.source, .sparkle)
	}

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

	func testCollectingUnchangedBundleReusesCachedMetadata() throws {
		let directory = try makeTemporaryDirectory()
		let appURL = try makeAppBundle(
			named: "Cached In Place",
			in: directory,
			info: [
				"CFBundleName": "Cached In Place",
				"CFBundleExecutable": "Cached In Place",
				"CFBundleIdentifier": "com.example.cached-in-place",
				"CFBundleShortVersionString": "1.2.3",
				"CFBundleVersion": "123"
			]
		)

		let firstBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))
		let secondBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

		XCTAssertTrue(firstBundle === secondBundle)
	}

	func testCollectingBundleWithUpdatedModificationDateRefreshesCachedMetadata() throws {
		let directory = try makeTemporaryDirectory()
		let appURL = try makeAppBundle(
			named: "Updated Metadata",
			in: directory,
			info: [
				"CFBundleName": "Updated Metadata",
				"CFBundleExecutable": "Updated Metadata",
				"CFBundleIdentifier": "com.example.updated-metadata",
				"CFBundleShortVersionString": "1.2.3",
				"CFBundleVersion": "123"
			]
		)

		let firstBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))
		let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
		let newerTimestamp = Date(timeIntervalSince1970: floor(firstBundle.modificationDate.timeIntervalSince1970) + 60)
		try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
		try setModificationDate(newerTimestamp, for: resourcesURL)

		let updatedBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

		XCTAssertFalse(firstBundle === updatedBundle)
		XCTAssertEqual(updatedBundle.modificationDate.timeIntervalSince1970, newerTimestamp.timeIntervalSince1970, accuracy: 0.001)
	}

	func testCollectBundlesSkipsAppsInsideExcludedSubfolders() throws {
		let directory = try makeTemporaryDirectory()
		let excludedDirectory = directory.appendingPathComponent("Setapp", isDirectory: true)

		_ = try makeAppBundle(
			named: "Excluded App",
			in: excludedDirectory,
			info: [
				"CFBundleName": "Excluded App",
				"CFBundleExecutable": "Excluded App",
				"CFBundleIdentifier": "com.example.excluded-app",
				"CFBundleShortVersionString": "1.0",
				"CFBundleVersion": "100"
			]
		)
		_ = try makeAppBundle(
			named: "Visible App",
			in: directory,
			info: [
				"CFBundleName": "Visible App",
				"CFBundleExecutable": "Visible App",
				"CFBundleIdentifier": "com.example.visible-app",
				"CFBundleShortVersionString": "1.0",
				"CFBundleVersion": "100"
			]
		)

		let bundles = BundleCollector.collectBundles(at: directory)

		XCTAssertEqual(Set(bundles.map(\.name)), ["Visible App"])
	}

}

final class ReleaseNotesPipelineTest: XCTestCase {

	func testCurrentBetterDisplayRegressionUsesVersionedGitHubRelease() throws {
		let bundle = App.Bundle(
			version: Version(versionNumber: "4.3.4", buildNumber: nil),
			name: "BetterDisplay",
			bundleIdentifier: "pro.betterdisplay.BetterDisplay",
			fileURL: URL(fileURLWithPath: "/Applications/BetterDisplay.app", isDirectory: true),
			source: .sparkle
		)

		guard case .githubRelease(let apiURL, _) = ReleaseNotesSourceCatalog.releaseNotes(
			for: bundle,
			remoteVersion: Version(versionNumber: "4.3.5", buildNumber: nil)
		) else {
			return XCTFail("Expected BetterDisplay 4.3.5 GitHub release")
		}
		XCTAssertEqual(apiURL.absoluteString, "https://api.github.com/repos/waydabber/BetterDummy/releases/tags/v4.3.5")
	}

	func testCurrentTelegramRegressionSelectsExactDesktopVersion() throws {
		let changelog = """
		7.0.3
		- Fix media viewer freezes on macOS.
		- Improve message rendering performance.
		7.0.2
		- Older unrelated fix.
		"""
		let text = try XCTUnwrap(ReleaseNotesMarkup.relevantChangelogText(
			fromHTML: changelog,
			version: "7.0.3",
			pageURL: URL(string: "https://raw.githubusercontent.com/telegramdesktop/tdesktop/dev/changelog.txt")!,
			allowFirstSectionFallback: false
		))

		XCTAssertTrue(text.contains("Fix media viewer freezes on macOS"))
		XCTAssertFalse(text.contains("Older unrelated fix"))
	}

	func testCurrentZedRegressionPrefersCompleteRenderedArticleOverTruncatedTransportPayload() throws {
		let html = """
		<html><body>
		<nav><a>1.11.4</a><a>1.11.3</a></nav>
		<main><div id="zed-1.11.3"><header><p>1.11.3</p><p>July 16, 2026</p></header><article>
		<p>This week's release includes complete collaboration improvements for shared projects.</p>
		<h2>Features</h2>
		<p>Fixed language server crashes when opening large workspaces.</p></article></div></main>
		<script>self.__next_f.push([1,"{\\\"release\\\":{\\\"version\\\":\\\"1.11.3\\\",\\\"description\\\":\\\"Fixed one truncated item.\\\"}}"])</script>
		</body></html>
		"""
		let text = try XCTUnwrap(ReleaseNotesMarkup.zedReleaseText(
			fromHTML: html,
			version: "1.11.3",
			pageURL: URL(string: "https://zed.dev/releases/stable/1.11.3")!
		))

		XCTAssertTrue(text.contains("complete collaboration improvements"))
		XCTAssertTrue(text.contains("language server crashes"))
		XCTAssertFalse(text.contains("truncated item"))
	}

	func testCurrentZoomRegressionDropsIOSOnlyRows() throws {
		let html = """
		<html><body>
		<h2>July 15, 2026 version 7.1.0 (83064)</h2>
		<h3>New, enhanced, and changed features</h3>
		<p>New or enhanced feature</p><p>Desktop meeting controls</p>
		<p>Improves meeting controls for desktop participants.</p><p>Windows</p><p>macOS</p><p>Linux</p>
		<p>New or enhanced feature</p><p>Mobile camera effects</p>
		<p>Adds iPhone camera effects.</p><p>iOS</p><p>iOS (Intune)</p>
		<h2>July 8, 2026 version 7.0.9</h2><p>Resolved issue</p><p>Older fix.</p><p>macOS</p>
		</body></html>
		"""
		let text = try XCTUnwrap(ReleaseNotesMarkup.zoomReleaseText(
			fromHTML: html,
			version: "7.1.0",
			pageURL: URL(string: "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222")!
		))

		XCTAssertTrue(text.contains("Desktop meeting controls"))
		XCTAssertFalse(text.contains("Mobile camera effects"))
		XCTAssertFalse(text.contains("iPhone camera effects"))
		XCTAssertFalse(text.contains("Older fix"))
	}

	func testReleaseNotesCandidateScorerRejectsWrongIdentityVersionPlatformAndSize() {
		let scorer = ReleaseNotesCandidateScorer(maximumMarkupSize: 32)
		let context = ReleaseNotesContext(
			appName: "Zed",
			bundleIdentifier: "dev.zed.Zed",
			localVersion: "1.11.2",
			remoteVersion: "1.11.3"
		)

		XCTAssertThrowsError(try scorer.quality(of: ReleaseNotesCandidate(
			markup: "Useful fixes for editors.", baseURL: nil, provenance: .changelog,
			declaredAppIdentifiers: ["com.example.Other"]
		), for: context)) { XCTAssertEqual($0 as? ReleaseNotesCandidateRejection, .wrongApplication) }
		XCTAssertThrowsError(try scorer.quality(of: ReleaseNotesCandidate(
			markup: "Useful fixes for editors.", baseURL: nil, provenance: .changelog,
			declaredVersion: "1.12.0"
		), for: context)) { XCTAssertEqual($0 as? ReleaseNotesCandidateRejection, .wrongVersion) }
		XCTAssertThrowsError(try scorer.quality(of: ReleaseNotesCandidate(
			markup: "Useful fixes for editors.", baseURL: nil, provenance: .changelog,
			declaredPlatforms: ["iOS"]
		), for: context)) { XCTAssertEqual($0 as? ReleaseNotesCandidateRejection, .wrongPlatform) }
		XCTAssertThrowsError(try scorer.quality(of: ReleaseNotesCandidate(
			markup: String(repeating: "x", count: 33), baseURL: nil, provenance: .changelog
		), for: context)) { XCTAssertEqual($0 as? ReleaseNotesCandidateRejection, .oversized) }
	}

	func testReleaseNotesResolverPrefersGenuineNotesOverGenericHomebrewMetadata() throws {
		let context = ReleaseNotesContext(
			appName: "Example",
			bundleIdentifier: "com.example.App",
			localVersion: "1.0",
			remoteVersion: "1.1"
		)
		let generic = ReleaseNotesCandidate(
			markup: "Example 1.1 is available from Homebrew.",
			baseURL: nil,
			provenance: .homebrewMetadata,
			qualityHint: .genericMetadata
		)
		let genuine = ReleaseNotesCandidate(
			markup: "Fixed a crash when reopening documents.",
			baseURL: nil,
			provenance: .changelog,
			qualityHint: .genuine
		)

		let resolved = try ReleaseNotesResolver().resolve(
			[generic, genuine],
			for: context,
			scorer: ReleaseNotesCandidateScorer()
		)
		XCTAssertEqual(resolved.quality, .genuine)
		XCTAssertEqual(resolved.candidate.provenance, .changelog)
	}

	func testGenericHomebrewMetadataHasDistinctQualityAndProvenance() {
		let releaseNotes = App.Update.ReleaseNotes.genericMetadata(string: "Example 1.1 is available from Homebrew.")
		XCTAssertEqual(releaseNotes.qualityHint, .genericMetadata)
		XCTAssertEqual(releaseNotes.provenance, .homebrewMetadata)
	}

	func testReleaseNotesFetcherRejectsMalformedAndOversizedContent() async throws {
		let url = URL(string: "https://example.com/notes")!
		let malformedFetcher = ReleaseNotesFetcher(loader: StubReleaseNotesLoader(response: Self.httpResponse(
			url: url,
			data: Data(repeating: 0, count: 128)
		)))
		await XCTAssertThrowsErrorAsync(try await malformedFetcher.fetchMarkup(from: url)) {
			XCTAssertEqual($0 as? ReleaseNotesFetchError, .unusableText)
		}

		let oversizedFetcher = ReleaseNotesFetcher(
			loader: StubReleaseNotesLoader(response: Self.httpResponse(url: url, data: Data("12345".utf8))),
			maximumResponseSize: 4
		)
		await XCTAssertThrowsErrorAsync(try await oversizedFetcher.fetchMarkup(from: url)) {
			XCTAssertEqual($0 as? ReleaseNotesFetchError, .oversized)
		}
	}

	func testSignedCatalogAcceptsValidRemoteDocument() async throws {
		let fixture = try makeSignedCatalogFixture(schemaVersion: 1)
		let client = SignedReleaseNotesCatalogClient(
			configuration: .init(
				isEnabled: true,
				remoteURL: fixture.url,
				publicKey: fixture.publicKey,
				maximumEnvelopeSize: 64 * 1_024
			),
			bundledCatalogData: fixture.bundled,
			loader: StubCatalogLoader(response: Self.httpResponse(url: fixture.url, data: fixture.envelope))
		)

		let loaded = try await client.load()
		XCTAssertEqual(loaded.origin, .remote)
		XCTAssertEqual(loaded.document.definitions.first?.keys, ["remote-app"])
	}

	func testSignedCatalogRejectsWrongSignatureAndUsesBundledLastKnownGood() async throws {
		var fixture = try makeSignedCatalogFixture(schemaVersion: 1)
		var envelope = try JSONDecoder().decode(SignedReleaseNotesCatalogEnvelope.self, from: fixture.envelope)
		envelope = SignedReleaseNotesCatalogEnvelope(
			schemaVersion: envelope.schemaVersion,
			payload: envelope.payload,
			signature: Data(repeating: 0, count: envelope.signature.count)
		)
		fixture.envelope = try JSONEncoder().encode(envelope)
		let client = catalogClient(fixture: fixture)

		let loaded = try await client.load()
		XCTAssertEqual(loaded.origin, .bundledFallback(.invalidSignature))
		XCTAssertEqual(loaded.document.definitions.first?.keys, ["bundled-app"])
	}

	func testSignedCatalogRejectsUnsupportedSchemaAndUsesBundledLastKnownGood() async throws {
		let fixture = try makeSignedCatalogFixture(schemaVersion: 99)
		let loaded = try await catalogClient(fixture: fixture).load()

		XCTAssertEqual(loaded.origin, .bundledFallback(.invalidCatalog))
		XCTAssertEqual(loaded.document.definitions.first?.keys, ["bundled-app"])
	}

	func testSignedCatalogRejectsUnsupportedEnvelopeSchemaAndUsesBundledLastKnownGood() async throws {
		var fixture = try makeSignedCatalogFixture(schemaVersion: 1)
		let validEnvelope = try JSONDecoder().decode(SignedReleaseNotesCatalogEnvelope.self, from: fixture.envelope)
		fixture.envelope = try JSONEncoder().encode(SignedReleaseNotesCatalogEnvelope(
			schemaVersion: 99,
			payload: validEnvelope.payload,
			signature: validEnvelope.signature
		))

		let loaded = try await catalogClient(fixture: fixture).load()
		XCTAssertEqual(loaded.origin, .bundledFallback(.invalidEnvelopeSchema))
		XCTAssertEqual(loaded.document.definitions.first?.keys, ["bundled-app"])
	}

	func testSignedCatalogOfflineAndDisabledModesUseBundledLastKnownGood() async throws {
		let fixture = try makeSignedCatalogFixture(schemaVersion: 1)
		let offlineClient = SignedReleaseNotesCatalogClient(
			configuration: .init(
				isEnabled: true,
				remoteURL: fixture.url,
				publicKey: fixture.publicKey,
				maximumEnvelopeSize: 64 * 1_024
			),
			bundledCatalogData: fixture.bundled,
			loader: OfflineCatalogLoader()
		)
		let offline = try await offlineClient.load()
		XCTAssertEqual(offline.origin, .bundledFallback(.network))

		let disabled = try await SignedReleaseNotesCatalogClient(
			configuration: .disabled,
			bundledCatalogData: fixture.bundled
		).load()
		XCTAssertEqual(disabled.origin, .bundledFallback(.disabled))
	}

	private static func httpResponse(url: URL, data: Data) -> ReleaseNotesFetchResponse {
		let response = HTTPURLResponse(
			url: url,
			statusCode: 200,
			httpVersion: "HTTP/1.1",
			headerFields: ["Content-Type": "application/json", "Content-Length": "\(data.count)"]
		)!
		return ReleaseNotesFetchResponse(data: data, response: response)
	}

	private func catalogClient(fixture: SignedCatalogFixture) -> SignedReleaseNotesCatalogClient {
		SignedReleaseNotesCatalogClient(
			configuration: .init(
				isEnabled: true,
				remoteURL: fixture.url,
				publicKey: fixture.publicKey,
				maximumEnvelopeSize: 64 * 1_024
			),
			bundledCatalogData: fixture.bundled,
			loader: StubCatalogLoader(response: Self.httpResponse(url: fixture.url, data: fixture.envelope))
		)
	}

	private func makeSignedCatalogFixture(schemaVersion: Int) throws -> SignedCatalogFixture {
		let bundled = try JSONEncoder().encode([Self.catalogDefinition(key: "bundled-app")])
		let remoteDocument = ReleaseNotesCatalogDocument(
			schemaVersion: schemaVersion,
			definitions: [Self.catalogDefinition(key: "remote-app")]
		)
		let payload = try JSONEncoder().encode(remoteDocument)
		let privateKey = Curve25519.Signing.PrivateKey()
		let envelope = SignedReleaseNotesCatalogEnvelope(
			schemaVersion: SignedReleaseNotesCatalogEnvelope.supportedSchemaVersion,
			payload: payload,
			signature: try privateKey.signature(for: payload)
		)
		return SignedCatalogFixture(
			url: URL(string: "https://catalog.example.com/release-notes.json")!,
			publicKey: privateKey.publicKey.rawRepresentation,
			bundled: bundled,
			envelope: try JSONEncoder().encode(envelope)
		)
	}

	private static func catalogDefinition(key: String) -> ReleaseNotesSourceDefinition {
		ReleaseNotesSourceDefinition(
			keys: [key],
			homebrewTokens: [],
			kind: .changelog,
			urlTemplate: "https://example.com/changelog/{version}",
			versionPrefix: .exact,
			knownFallbackKey: nil,
			allowsLatestFallback: false
		)
	}

}

private extension BundleCollectorTest {
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

private struct SignedCatalogFixture {
	let url: URL
	let publicKey: Data
	let bundled: Data
	var envelope: Data
}

private struct StubReleaseNotesLoader: ReleaseNotesHTTPDataLoading {
	let response: ReleaseNotesFetchResponse

	func load(_ request: URLRequest) async throws -> ReleaseNotesFetchResponse {
		response
	}
}

private struct StubCatalogLoader: ReleaseNotesCatalogHTTPDataLoading {
	let response: ReleaseNotesFetchResponse

	func load(_ request: URLRequest) async throws -> ReleaseNotesFetchResponse {
		response
	}
}

private struct OfflineCatalogLoader: ReleaseNotesCatalogHTTPDataLoading {
	private struct Offline: Error {}

	func load(_ request: URLRequest) async throws -> ReleaseNotesFetchResponse {
		throw Offline()
	}
}

private func XCTAssertThrowsErrorAsync<T>(
	_ expression: @autoclosure () async throws -> T,
	_ errorHandler: (Error) -> Void = { _ in },
	file: StaticString = #filePath,
	line: UInt = #line
) async {
	do {
		_ = try await expression()
		XCTFail("Expected expression to throw", file: file, line: line)
	} catch {
		errorHandler(error)
	}
}
