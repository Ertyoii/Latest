//
//  UpdateRepositoryTest.swift
//  Latest Tests
//
//  Structural split from the original implementation.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-29.
//  Licensed under GPL-3.0; see LICENSE.md.

import CryptoKit
import XCTest

@testable import Latest

final class UpdateRepositoryTest: XCTestCase {
  func testZIPExtractionCannotWriteThroughAnArchiveSymlink() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let outside = directory.appendingPathComponent("outside")
    let extracted = directory.appendingPathComponent("extracted")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/symlink-escape.zip")
    do {
      try await AppDownloadUpdateOperation.extractZIP(at: fixture, to: extracted)
      XCTFail("Archive paths through symlinks must be rejected")
    } catch {}
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: outside.appendingPathComponent("escaped.txt").path))
  }

  /// Opt-in integration check against downloaded vendor artifacts; never installs them.
  func testDownloadedVendorArtifactsMatchTheirInstalledSigningIdentity() async throws {
    guard let path = ProcessInfo.processInfo.environment["LATEST_VENDOR_ARTIFACTS"] else {
      throw XCTSkip("Set LATEST_VENDOR_ARTIFACTS to a prepared vendor-validation directory.")
    }
    try await Task.detached {
      let directory = URL(fileURLWithPath: path)
      let delta = try XCTUnwrap(
        BundleCollector.collectBundle(at: URL(fileURLWithPath: "/Applications/Delta.app")))
      let release = try AppDownloadRelease(
        data: Data(contentsOf: directory.appendingPathComponent("delta-release.json")),
        source: .delta
      )
      try AppDownloadUpdateOperation.validate(
        candidate: directory.appendingPathComponent("Delta.app"),
        replacing: delta, expectedVersion: release.version)
      let obsidian = try ObsidianUpdate.release(
        from: Data(
          contentsOf: directory.deletingLastPathComponent().appendingPathComponent(
            "obsidian-release.json")),
        includesEarlyAccess: false)
      try ObsidianUpdate.verify(
        Data(contentsOf: directory.appendingPathComponent("obsidian.asar.gz")), release: obsidian)
    }.value
  }

  func testDownloadMetadataSelectsTheHostArchitectureAndRejectsInstallerArtifacts() throws {
    var record: [String: Any] = [
      "version": "2.0.0", "url": "https://example.com/arm64.dmg",
      "sha256": String(repeating: "a", count: 64), "artifacts": [["app": ["Example.app"]]],
      "variations": [
        "tahoe": [
          "url": "https://example.com/intel.dmg", "sha256": String(repeating: "b", count: 64),
        ]
      ],
    ]
    func release(_ platform: String) throws -> AppDownloadRelease {
      try AppDownloadRelease(
        data: JSONSerialization.data(withJSONObject: record),
        source: .homebrew("example"), platform: platform)
    }
    XCTAssertEqual(try release("arm64_tahoe").url.lastPathComponent, "arm64.dmg")
    XCTAssertEqual(try release("tahoe").url.lastPathComponent, "intel.dmg")
    XCTAssertEqual(try release("tahoe").sha256, String(repeating: "b", count: 64))
    record["artifacts"] = [["pkg": ["Installer.pkg"]]]
    XCTAssertThrowsError(try release("arm64_tahoe"))
    record["artifacts"] = [["app": ["../Other.app"]]]
    XCTAssertThrowsError(try release("arm64_tahoe"))
    record["artifacts"] = [["app": ["Example.app"]]]
    record["url"] = "http://example.com/update.dmg"
    XCTAssertThrowsError(try release("arm64_tahoe"))
  }

  func testDownloadChecksumRejectsModifiedArchiveAndReplacementRestoresOriginalOnFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = directory.appendingPathComponent("Example.app")
    try Data("abc".utf8).write(to: original)
    try AppDownloadUpdateOperation.verifyChecksum(
      of: original,
      expected: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    XCTAssertThrowsError(
      try AppDownloadUpdateOperation.verifyChecksum(
        of: original,
        expected: String(repeating: "0", count: 64)))
    let stage = directory.appendingPathComponent("stage")
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    XCTAssertThrowsError(
      try AppDownloadUpdateOperation.replaceApplication(
        at: original, with: stage.appendingPathComponent("missing.app"), backupDirectory: stage))
    XCTAssertEqual(try Data(contentsOf: original), Data("abc".utf8))
    let candidate = stage.appendingPathComponent("Example.app")
    try Data("new".utf8).write(to: candidate)
    try AppDownloadUpdateOperation.replaceApplication(
      at: original, with: candidate, backupDirectory: stage)
    XCTAssertEqual(try Data(contentsOf: original), Data("new".utf8))
    XCTAssertEqual(
      try Data(contentsOf: stage.appendingPathComponent("original.app")), Data("abc".utf8))
  }

  func testObsidianPreservesStableAndExistingEarlyAccessChannels() throws {
    let data = Data(
      #"{"minimumVersion":"1.1.9","latestVersion":"1.13.7","downloadUrl":"https://example.com/public.asar.gz","hash":"hash","signature":"signature","beta":{"minimumVersion":"1.1.9","latestVersion":"1.14.4","downloadUrl":"https://example.com/beta.asar.gz","hash":"hash","signature":"signature"}}"#
        .utf8)
    XCTAssertEqual(
      try ObsidianUpdate.release(
        from: data,
        includesEarlyAccess: false
      ).latestVersion, "1.13.7")
    let beta = try ObsidianUpdate.release(
      from: data,
      includesEarlyAccess: true)
    XCTAssertEqual(beta.latestVersion, "1.14.4")
    XCTAssertThrowsError(try ObsidianUpdate.verify(Data("tampered".utf8), release: beta))
  }

  func testGhosttyUsesItsOfficialStableSparkleFeed() {
    XCTAssertEqual(
      SparkleFeed.feedURL(
        from: [:], bundleIdentifier: "com.mitchellh.ghostty",
        bundleURL: URL(fileURLWithPath: "/Applications/Ghostty.app"))?.absoluteString,
      "https://release.files.ghostty.org/appcast.xml")
  }

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
      \t"token": "example-app",
      \t"version": "2.4.1",
      \t"name": ["Example App"],
      \t"desc": "Notes, tasks & reminders",
      \t"homepage": "https://example.com/",
      \t"depends_on": {
      \t\t"macos": {
      \t\t\t">=": ["13.0"]
      \t\t}
      \t},
      \t"artifacts": [
      \t\t{
      \t\t\t"app": ["Example App.app"]
      \t\t}
      \t]
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
      \t"token": "eqmac",
      \t"version": "1.8.15",
      \t"name": ["eqMac"],
      \t"homepage": "https://eqmac.app/",
      \t"url": "https://github.com/bitgapp/eqMac/releases/download/v1.8.15/eqMac.dmg",
      \t"artifacts": [
      \t\t{
      \t\t\t"app": ["eqMac.app"]
      \t\t}
      \t],
      \t"depends_on": {
      \t\t"macos": {}
      \t}
      }
      """
    let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

    guard case .githubRelease(let apiURL, let fallbackHTML) = entry.releaseNotes else {
      return XCTFail("Expected GitHub release notes")
    }

    XCTAssertEqual(
      apiURL.absoluteString, "https://api.github.com/repos/bitgapp/eqMac/releases/tags/v1.8.15")
    XCTAssertNil(fallbackHTML)
  }

  func testHomebrewCaskEntryDerivesLatestGitHubReleaseFromLatestDownloadURL() throws {
    let json = """
      {
      \t"token": "example-app",
      \t"version": "2.4.1",
      \t"name": ["Example App"],
      \t"homepage": "https://example.com/",
      \t"url": "https://github.com/example/example-app/releases/latest/download/Example.zip",
      \t"artifacts": [{ "app": ["Example App.app"] }],
      \t"depends_on": { "macos": {} }
      }
      """
    let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

    guard case .githubRelease(let apiURL, _) = entry.releaseNotes else {
      return XCTFail("Expected GitHub release notes")
    }

    XCTAssertEqual(
      apiURL.absoluteString, "https://api.github.com/repos/example/example-app/releases/latest")
    XCTAssertEqual(
      ReleaseNotesProvider.githubReleaseWebURL(fromAPIURL: apiURL)?.absoluteString,
      "https://github.com/example/example-app/releases/latest"
    )
  }

  func testHomebrewCaskEntryDerivesLatestGitHubReleaseFromRepositoryHomepage() throws {
    let json = """
      {
      \t"token": "example-app",
      \t"version": "2.4.1",
      \t"name": ["Example App"],
      \t"homepage": "https://github.com/example/example-app/",
      \t"url": "https://downloads.example.com/Example.zip",
      \t"artifacts": [{ "app": ["Example App.app"] }],
      \t"depends_on": { "macos": {} }
      }
      """
    let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

    guard case .githubRelease(let apiURL, _) = entry.releaseNotes else {
      return XCTFail("Expected GitHub release notes")
    }

    XCTAssertEqual(
      apiURL.absoluteString, "https://api.github.com/repos/example/example-app/releases/latest")
  }

  func testHomebrewNonAppCaskDoesNotConstructReleaseNotes() throws {
    let json = """
      {
      \t"token": "example-font",
      \t"version": { "unexpected": true },
      \t"name": ["Example Font"],
      \t"homepage": 42,
      \t"artifacts": [{ "font": ["Example.ttf"] }],
      \t"depends_on": "not-app-metadata"
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
      \t"token": "1password",
      \t"version": "8.12.22",
      \t"name": ["1Password"],
      \t"desc": "Password manager",
      \t"homepage": "https://1password.com/",
      \t"url": "https://downloads.1password.com/mac/1Password.zip",
      \t"artifacts": [
      \t\t{
      \t\t\t"app": ["1Password.app"]
      \t\t}
      \t],
      \t"depends_on": {
      \t\t"macos": {}
      \t}
      }
      """
    let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

    guard
      case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML) =
        entry.releaseNotes
    else {
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
      \t"token": "obsidian",
      \t"version": "1.12.7",
      \t"name": ["Obsidian"],
      \t"desc": "Knowledge base",
      \t"homepage": "https://obsidian.md/",
      \t"url": "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.12.7/Obsidian-1.12.7.dmg",
      \t"artifacts": [
      \t\t{
      \t\t\t"app": ["Obsidian.app"]
      \t\t}
      \t],
      \t"depends_on": {
      \t\t"macos": {}
      \t}
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
      \t"token": "cursor",
      \t"version": "3.4.16,abcdef",
      \t"name": ["Cursor"],
      \t"homepage": "https://www.cursor.com/",
      \t"url": "https://downloads.cursor.com/production/abcdef/darwin/arm64/Cursor-darwin-arm64.zip",
      \t"artifacts": [
      \t\t{
      \t\t\t"app": ["Cursor.app"]
      \t\t}
      \t],
      \t"depends_on": {
      \t\t"macos": {}
      \t}
      }
      """
    let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

    guard
      case .changelog(let urls, let versionPrefix, let allowsLatestFallback, _) = entry.releaseNotes
    else {
      return XCTFail("Expected changelog release notes")
    }

    XCTAssertEqual(versionPrefix, "3.4")
    XCTAssertTrue(allowsLatestFallback)
    XCTAssertEqual(urls, [URL(string: "https://cursor.com/changelog")!])
  }

  func testHomebrewCaskEntryUsesExactZedStableReleasePage() throws {
    let json = """
      {
      \t"token": "zed",
      \t"version": "1.4.4",
      \t"name": ["Zed"],
      \t"homepage": "https://zed.dev/",
      \t"url": "https://zed.dev/api/releases/stable/1.4.4/Zed-aarch64.dmg",
      \t"artifacts": [
      \t\t{
      \t\t\t"app": ["Zed.app"]
      \t\t}
      \t],
      \t"depends_on": {
      \t\t"macos": {}
      \t}
      }
      """
    let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

    guard
      case .changelog(let urls, let versionPrefix, let allowsLatestFallback, _) = entry.releaseNotes
    else {
      return XCTFail("Expected changelog release notes")
    }

    XCTAssertEqual(versionPrefix, "1.4.4")
    XCTAssertFalse(allowsLatestFallback)
    XCTAssertEqual(urls, [URL(string: "https://zed.dev/releases/stable/1.4.4")!])
  }

  func testHomebrewCaskEntryUsesExactZedPreviewReleasePage() throws {
    let json = """
      {
      \t"token": "zed@preview",
      \t"version": "1.4.5",
      \t"name": ["Zed Preview"],
      \t"homepage": "https://zed.dev/",
      \t"url": "https://zed.dev/api/releases/preview/1.4.5/Zed-aarch64.dmg",
      \t"artifacts": [
      \t\t{
      \t\t\t"app": ["Zed Preview.app"]
      \t\t}
      \t],
      \t"depends_on": {
      \t\t"macos": {}
      \t}
      }
      """
    let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

    guard
      case .changelog(let urls, let versionPrefix, let allowsLatestFallback, _) = entry.releaseNotes
    else {
      return XCTFail("Expected changelog release notes")
    }

    XCTAssertEqual(versionPrefix, "1.4.5")
    XCTAssertFalse(allowsLatestFallback)
    XCTAssertEqual(urls, [URL(string: "https://zed.dev/releases/preview/1.4.5")!])
  }

  func testHomebrewCaskEntryProvidesFallbackReleaseNotesWhenNoChangelogExists() throws {
    let json = """
      {
      \t"token": "example-vpn",
      \t"version": "14.1.1.13156",
      \t"name": ["ExampleVPN"],
      \t"desc": "VPN client for secure & private internet access",
      \t"artifacts": [
      \t\t{
      \t\t\t"uninstall": [
      \t\t\t\t{
      \t\t\t\t\t"quit": "com.example.vpn",
      \t\t\t\t\t"delete": "/Applications/ExampleVPN.app"
      \t\t\t\t}
      \t\t\t]
      \t\t}
      \t],
      \t"depends_on": {
      \t\t"macos": {}
      \t}
      }
      """
    let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

    guard case .genericMetadata(let html) = entry.releaseNotes else {
      return XCTFail("Expected separately classified Homebrew metadata")
    }

    XCTAssertTrue(html.contains("ExampleVPN 14.1.1.13156"))
    XCTAssertTrue(html.contains("secure &amp; private"))
  }

  func testHomebrewCaskEntryKeepsBundleIdentifiersWhenAppArtifactExists() throws {
    let json = """
      {
      \t"token": "example-app",
      \t"version": "2.4.1",
      \t"artifacts": [
      \t\t{
      \t\t\t"app": ["Example App.app"]
      \t\t},
      \t\t{
      \t\t\t"zap": [
      \t\t\t\t{
      \t\t\t\t\t"trash": [
      \t\t\t\t\t\t"~/Library/Preferences/com.example.app.plist"
      \t\t\t\t\t],
      \t\t\t\t\t"delete": [
      \t\t\t\t\t\t"~/Library/Application Support/com.example.helper"
      \t\t\t\t\t]
      \t\t\t\t}
      \t\t\t]
      \t\t}
      \t],
      \t"depends_on": {
      \t\t"macos": {}
      \t}
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
      \t"token": "garmin-express",
      \t"name": ["Garmin Express"],
      \t"version": "7.28.0",
      \t"artifacts": [
      \t\t{
      \t\t\t"uninstall": [
      \t\t\t\t{
      \t\t\t\t\t"quit": ["com.garmin.renu.client"]
      \t\t\t\t}
      \t\t\t]
      \t\t},
      \t\t{
      \t\t\t"pkg": ["Install Garmin Express.pkg"]
      \t\t}
      \t],
      \t"depends_on": {
      \t\t"macos": {}
      \t}
      }
      """
    let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

    XCTAssertEqual(entry.names, ["Garmin Express.app"])
    XCTAssertEqual(entry.bundleIdentifiers, ["com.garmin.renu.client"])
    XCTAssertTrue(entry.requiresBundleIdentifierMatch)
  }

  func testHomebrewRepositoryPrefersStableCaskAfterIdentifierMatch() throws {
    let stable = try homebrewEntry(
      token: "telegram-desktop", bundleIdentifier: "com.tdesktop.Telegram")
    let beta = try homebrewEntry(
      token: "telegram-desktop@beta", bundleIdentifier: "com.tdesktop.Telegram")
    let other = try homebrewEntry(token: "telegram", bundleIdentifier: "ru.keepcoder.Telegram")

    let entry = UpdateRepository.preferredEntry(
      from: [other, stable, beta], for: "com.tdesktop.Telegram")

    XCTAssertEqual(entry?.token, "telegram-desktop")
  }

  func testHomebrewRepositoryPrefersShortestStableCaskWhenIdentifierMatchesMultipleEntries() throws
  {
    let stable = try homebrewEntry(token: "zoom", bundleIdentifier: "us.zoom.xos")
    let admin = try homebrewEntry(token: "zoom-for-it-admins", bundleIdentifier: "us.zoom.xos")

    let entry = UpdateRepository.preferredEntry(from: [admin, stable], for: "us.zoom.xos")

    XCTAssertEqual(entry?.token, "zoom")
  }

}

private func homebrewEntry(token: String, bundleIdentifier: String) throws -> UpdateRepository.Entry
{
  let json = """
    {
    \t"token": "\(token)",
    \t"version": "1.0",
    \t"artifacts": [
    \t\t{
    \t\t\t"app": ["Example App.app"]
    \t\t},
    \t\t{
    \t\t\t"zap": [
    \t\t\t\t{
    \t\t\t\t\t"trash": [
    \t\t\t\t\t\t"~/Library/Preferences/\(bundleIdentifier).plist"
    \t\t\t\t\t]
    \t\t\t\t}
    \t\t\t]
    \t\t}
    \t],
    \t"depends_on": {
    \t\t"macos": {}
    \t}
    }
    """

  return try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))
}
