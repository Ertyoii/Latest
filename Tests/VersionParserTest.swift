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

		guard case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML) = entry.releaseNotes else {
			return XCTFail("Expected changelog release notes")
		}

		XCTAssertEqual(versionPrefix, "2.4")
		XCTAssertFalse(allowsLatestFallback)
		XCTAssertTrue(fallbackHTML?.contains("Example App 2.4.1") == true)
		XCTAssertTrue(fallbackHTML?.contains("Notes, tasks &amp; reminders") == true)
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

		guard case .githubRelease(let apiURL, let fallbackHTML) = entry.releaseNotes else {
			return XCTFail("Expected GitHub release notes")
		}

		XCTAssertEqual(apiURL.absoluteString, "https://api.github.com/repos/bitgapp/eqMac/releases/tags/v1.8.15")
		XCTAssertTrue(fallbackHTML?.contains("eqMac 1.8.15") == true)
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

		guard case .html(let html) = entry.releaseNotes else {
			return XCTFail("Expected fallback HTML release notes")
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

	func testReleaseNotesMarkupExtractsFirstReleaseNotesURLFromStubText() throws {
		let text = "1.12.7 https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/"
		let url = try XCTUnwrap(ReleaseNotesMarkup.firstReleaseNotesURL(in: text, baseURL: nil))

		XCTAssertEqual(url.absoluteString, "https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/")
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
	func testReleaseNotesProviderInvalidatesCacheWhenReleaseNoteSourceChanges() throws {
		let provider = ReleaseNotesProvider()
		let oldApp = makeReleaseNotesApp(html: "<p>Old release notes with bug fixes.</p>")
		let refreshedApp = makeReleaseNotesApp(html: "<p>Fresh release notes with improvements.</p>")

		let oldNotes = try releaseNotes(for: oldApp, provider: provider)
		let refreshedNotes = try releaseNotes(for: refreshedApp, provider: provider)

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
	private func releaseNotes(for app: App, provider: ReleaseNotesProvider) throws -> NSAttributedString {
		var result: ReleaseNotesProvider.ReleaseNotes?
		provider.releaseNotes(for: app) { notes in
			result = notes
		}

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
