// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import WebKit
import XCTest

@testable import Latest

final class ReleaseNotesWebViewTest: XCTestCase {
  @MainActor
  func testReleaseNotesTextPreservesRichTextSelectionCopyAndAccessibility() async throws {
    try requireUITests()
    let source = NSMutableAttributedString(string: "Bold link\tbody\nSecond paragraph")
    let fullRange = NSRange(location: 0, length: source.length)
    let linkRange = (source.string as NSString).range(of: "link")
    let originalParagraphStyle = NSMutableParagraphStyle()
    originalParagraphStyle.firstLineHeadIndent = 32
    originalParagraphStyle.headIndent = 24
    originalParagraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: 48)]
    source.addAttributes(
      [
        .font: NSFont.boldSystemFont(ofSize: 22),
        .backgroundColor: NSColor.systemYellow,
        .shadow: NSShadow(),
        .paragraphStyle: originalParagraphStyle,
      ], range: fullRange)
    source.addAttribute(.link, value: URL(string: "https://example.com/release")!, range: linkRange)

    let html = ReleaseNotesWebDocument.html(for: ReleaseNotesLegacyBridge.content(from: source))
    XCTAssertTrue(html.contains("<strong>"))
    XCTAssertFalse(html.contains("background-color"))
    XCTAssertFalse(html.contains("22px"))

    let hostingView = NSHostingView(
      rootView: ReleaseNotesWebView(text: ReleaseNotesLegacyBridge.content(from: source)))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    defer { window.close() }
    window.orderFront(nil)
    hostingView.layoutSubtreeIfNeeded()
    let web = try XCTUnwrap(hostingView.descendant(of: WKWebView.self))
    try await waitForWebContent(web, containing: "Second paragraph")
    let href = try await web.evaluateJavaScript("document.querySelector('a').href") as? String
    XCTAssertEqual(href, "https://example.com/release")
    let selection =
      try await web.evaluateJavaScript(
        """
        var range = document.createRange(); range.selectNodeContents(document.querySelector('main'));
        window.getSelection().removeAllRanges(); window.getSelection().addRange(range);
        window.getSelection().toString();
        """) as? String
    XCTAssertEqual(selection, source.string.replacingOccurrences(of: "\t", with: " "))
    XCTAssertFalse(web.configuration.websiteDataStore.isPersistent)
    XCTAssertFalse(web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    XCTAssertFalse(web.allowsBackForwardNavigationGestures)
    XCTAssertFalse(web.allowsMagnification)
  }

  @MainActor
  func testReleaseNotesWebViewReusesRendererAndResetsScrollOnSelection() async throws {
    try requireUITests()
    let firstApp = makeTestApp(name: "First app", version: "1", remoteVersion: "2")
    let secondApp = makeTestApp(name: "Second app", version: "3", remoteVersion: "4")
    let short = ReleaseNotesContent(string: "Short release notes")
    let long = ReleaseNotesContent(
      string: Array(repeating: "Long release notes", count: 150)
        .joined(separator: "\n"))
    let host = NSHostingView(
      rootView: ReleaseNotesDetailSurface(app: firstApp, contentState: .text(long)))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    let web = try XCTUnwrap(host.descendant(of: WKWebView.self))
    try await waitForWebContent(web, containing: "Long release notes")
    _ = try await web.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight)")
    let scrolled = try await web.evaluateJavaScript("window.scrollY") as? Double
    XCTAssertGreaterThan(scrolled ?? 0, 0)
    _ = try await web.evaluateJavaScript(
      """
      window.rendererReuseMarker = 42;
      var range = document.createRange();
      range.selectNodeContents(document.querySelector('main'));
      window.getSelection().removeAllRanges(); window.getSelection().addRange(range);
      """)
    // Held arrows change the header while the previous notes remain displayed.
    host.rootView = ReleaseNotesDetailSurface(app: secondApp, contentState: .text(long))
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    let marker = try await web.evaluateJavaScript("window.rendererReuseMarker") as? Int
    XCTAssertEqual(marker, 42, "Unchanged notes must not reload the page")
    let retainedScroll = try await web.evaluateJavaScript("window.scrollY") as? Double
    XCTAssertEqual(retainedScroll, scrolled, "Header selection must preserve notes scroll position")
    let retainedSelection =
      try await web.evaluateJavaScript("window.getSelection().toString()") as? String
    XCTAssertEqual(retainedSelection, long.string, "Header selection must preserve text selection")
    // A different selection can have identical text. Its new content identity
    // must still reset scroll while the same content object above stays loaded.
    host.rootView = ReleaseNotesDetailSurface(
      app: secondApp, contentState: .text(ReleaseNotesContent(string: long.string)))
    host.layoutSubtreeIfNeeded()
    var reloaded = false
    for _ in 0..<100 {
      reloaded =
        (try await web.evaluateJavaScript("typeof window.rendererReuseMarker === 'undefined'")
          as? Bool) == true
      if reloaded { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTAssertTrue(reloaded, "Distinct notes with equal text must reload the page")
    let equalTextScroll = try await web.evaluateJavaScript("window.scrollY") as? Double
    XCTAssertEqual(equalTextScroll, 0)
    host.rootView = ReleaseNotesDetailSurface(app: secondApp, contentState: .loading)
    host.layoutSubtreeIfNeeded()
    XCTAssertTrue(host.descendant(of: WKWebView.self) === web)
    host.rootView = ReleaseNotesDetailSurface(app: secondApp, contentState: .text(short))
    window.setContentSize(NSSize(width: 360, height: 280))
    host.layoutSubtreeIfNeeded()
    try await waitForWebContent(web, containing: "Short release notes")
    XCTAssertTrue(host.descendant(of: WKWebView.self) === web)
    let top = try await web.evaluateJavaScript("window.scrollY") as? Double
    XCTAssertEqual(top, 0)
    let overflow =
      try await web.evaluateJavaScript(
        "document.documentElement.scrollWidth > window.innerWidth") as? Bool
    XCTAssertEqual(overflow, false)
  }

  @MainActor
  private func waitForWebContent(_ web: WKWebView, containing text: String) async throws {
    let deadline = Date(timeIntervalSinceNow: 10)
    while Date() < deadline {
      if let body = try? await web.evaluateJavaScript("document.body.innerText") as? String,
        body.contains(text), !web.isLoading
      {
        return
      }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTFail("WebKit did not render expected content: \(text)")
  }
}
