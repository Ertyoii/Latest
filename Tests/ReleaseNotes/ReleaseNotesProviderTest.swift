//
//  ReleaseNotesProviderTest.swift
//  Latest Tests
//
//  Structural split from the original implementation.
//

import CryptoKit
import XCTest

@testable import Latest

final class ReleaseNotesProviderTest: XCTestCase {
  func testReleaseNotesProviderBuildsGitHubWebURLFromAPIURL() throws {
    let apiURL = URL(string: "https://api.github.com/repos/usebruno/bruno/releases/tags/v3.4.2")!
    let webURL = try XCTUnwrap(ReleaseNotesProvider.githubReleaseWebURL(fromAPIURL: apiURL))

    XCTAssertEqual(webURL.absoluteString, "https://github.com/usebruno/bruno/releases/tag/v3.4.2")
  }

  func testReleaseNotesProviderExtractsGitHubReleaseBodyHTML() throws {
    let html = """
      <main>
      \t<div data-test-selector="body-content" class="markdown-body tmp-my-3">
      \t\t<ul>
      \t\t\t<li>Fix possible crash in OpenGL init.</li>
      \t\t\t<li>Fix display of rich messages without text.</li>
      \t\t</ul>
      \t\t<div><p>Nested note stays in the release body.</p></div>
      \t</div>
      \t<div class="Box-footer">Assets 11</div>
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
      \t<p><a href="https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/">https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/</a></p>
      </div>
      """

    let body = try XCTUnwrap(ReleaseNotesProvider.githubReleaseBodyHTML(fromHTML: html))
    let url = try XCTUnwrap(
      ReleaseNotesMarkup.firstReleaseNotesURL(
        in: body,
        baseURL: URL(
          string: "https://github.com/obsidianmd/obsidian-releases/releases/tag/v1.12.7")!))

    XCTAssertEqual(url.absoluteString, "https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/")
    XCTAssertThrowsError(
      try ReleaseNotesMarkup.attributedString(from: body, baseURL: nil, relevantVersion: "1.12.7")
        .get())
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
    let app = makeReleaseNotesApp(
      releaseNotes: .url(url: URL(string: "https://example.com/Thunder.dmg")!))
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
      case .releaseNotesUnavailable = error
    else {
      return XCTFail(
        "Expected downloadable release note URLs to be rejected before the web loader.")
    }
  }

  @MainActor
  private func releaseNotes(for app: App, provider: ReleaseNotesProvider) async throws
    -> NSAttributedString
  {
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
