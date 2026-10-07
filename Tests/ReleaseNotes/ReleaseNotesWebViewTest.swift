// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import ScreenCaptureKit
import SwiftUI
import WebKit
import XCTest

@testable import Latest

final class ReleaseNotesWebViewTest: XCTestCase {
  @MainActor
  func testChromeReleaseNotesRenderSecurityEntriesOnSeparateLines() async throws {
    try requireUITests()
    let html = """
      <div class='post'><h2>Stable Channel Update for Desktop</h2>
      <script type='text/template'>
      <p>The Stable channel has been updated to 155.0.8059.39/.40 for Windows and Mac.</p>
      <h1>Security Fixes and Rewards</h1>
      <p>Critical CVE-2026-106382: Use after free in Chromecast. Reported by @_3P1C.</p>
      <p>Critical CVE-2026-106197: Use after free in Browser. Reported by @lbherrera_.</p>
      </script></div>
      """
    let url = try XCTUnwrap(URL(string: "https://chromereleases.googleblog.com/"))
    let result = await ReleaseNotesMarkup.attributedStringFromChangelogByPreparingOffMain(
      fromHTML: html, baseURL: url, relevantVersion: "155.0.8059.40",
      allowFirstSectionFallback: false)
    let content = try XCTUnwrap(result).get()
    let app = makeTestApp(name: "Chrome", version: "154.0.8037.98", remoteVersion: "155.0.8059.40")
    let window = try await makeLatestTestWindow(
      content: ReleaseNotesDetailSurface(app: app, contentState: .text(content)), testCase: self)
    defer { window.close() }
    let host = try XCTUnwrap(window.contentView)
    var renderer: WKWebView?
    let deadline = ContinuousClock.now + .seconds(5)
    repeat {
      host.layoutSubtreeIfNeeded()
      renderer = host.descendant(of: WKWebView.self)
      if renderer != nil { break }
      try await Task.sleep(for: .milliseconds(20))
    } while ContinuousClock.now < deadline
    let web = try XCTUnwrap(renderer, "The production release-note renderer must mount")
    try await waitForWebPaint(web)
    let text =
      try await web.evaluateJavaScript("document.querySelector('main').innerText") as? String
    XCTAssertEqual(text, content.string)
    let tops =
      try await web.evaluateJavaScript(
        """
        ['Stable Channel', 'Security Fixes', 'Critical CVE-2026-106382', 'Critical CVE-2026-106197'].map(prefix => {
          const nodes = document.createTreeWalker(document.querySelector('main'), NodeFilter.SHOW_TEXT);
          while (nodes.nextNode()) {
            const offset = nodes.currentNode.textContent.indexOf(prefix);
            if (offset < 0) continue;
            const range = document.createRange();
            range.setStart(nodes.currentNode, offset); range.setEnd(nodes.currentNode, offset + prefix.length);
            return range.getBoundingClientRect().top;
          }
          return -1;
        });
        """) as? [Double]
    let positions = try XCTUnwrap(tops)
    XCTAssertEqual(positions.count, 4)
    XCTAssertTrue(positions.allSatisfy { $0 >= 0 })
    for (first, next) in zip(positions, positions.dropFirst()) {
      XCTAssertGreaterThan(
        next - first, 15, "Each heading and security entry must start on a new line")
    }
    let bitmap = try await settledWindowBitmap(window)
    let attachment = XCTAttachment(
      image: NSImage(cgImage: try XCTUnwrap(bitmap.cgImage), size: bitmap.size))
    attachment.name = "chrome-release-notes-blocks"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testReleaseNotesBackgroundDoesNotFlashWhileLoading() async throws {
    try requireUITests()
    let app = makeTestApp(name: "First paint", version: "1")
    for dark in [true, false] {
      let host = NSHostingView(
        rootView: ReleaseNotesDetailSurface(app: nil, contentState: .message(.noSelection)))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      window.contentView = host
      defer { window.close() }
      window.orderFront(nil)
      host.layoutSubtreeIfNeeded()
      let shareable = try await SCShareableContent.currentProcess
      let capturedWindow = try XCTUnwrap(
        shareable.windows.first { $0.windowID == window.windowNumber })
      let configuration = SCStreamConfiguration()
      configuration.width = 480
      configuration.height = Int(window.frame.height)
      configuration.minimumFrameInterval = CMTime(value: 1, timescale: 120)
      configuration.pixelFormat = kCVPixelFormatType_32BGRA
      configuration.showsCursor = false
      let frames = ReleaseNotesBackgroundFrames()
      let stream = SCStream(
        filter: SCContentFilter(desktopIndependentWindow: capturedWindow),
        configuration: configuration, delegate: nil)
      try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: .main)
      try await stream.startCapture()
      do {
        for _ in 0..<100 where frames.brightness.isEmpty {
          try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(frames.brightness.isEmpty, "Capture must start before loading the page")
        // Record the cold first load and subsequent selections without waiting
        // for paint between the SwiftUI state change and each captured frame.
        for index in 0..<3 {
          let text = "Release notes selection \(index)"
          host.rootView = ReleaseNotesDetailSurface(
            app: app, contentState: .text(ReleaseNotesContent(string: text)))
          host.layoutSubtreeIfNeeded()
          let web = try XCTUnwrap(host.descendant(of: WKWebView.self))
          try await waitForWebContent(web, containing: text)
          try await Task.sleep(for: .milliseconds(100))
        }
        try await stream.stopCapture()
      } catch {
        try? await stream.stopCapture()
        throw error
      }
      XCTAssertGreaterThan(frames.brightness.count, 3, "Capture must include the page transitions")
      if dark {
        XCTAssertLessThan(
          frames.brightness.max() ?? 1, 0.3,
          "The dark release-notes background must never flash white, including its first paint")
      } else {
        XCTAssertGreaterThan(
          frames.brightness.min() ?? 0, 0.85,
          "The light release-notes background must remain light while pages load")
      }
    }
  }

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

/// Inspect an empty area below the short notes in actual WindowServer frames.
@MainActor
private final class ReleaseNotesBackgroundFrames: NSObject, SCStreamOutput {
  private(set) var brightness: [Double] = []

  nonisolated func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen, sampleBuffer.isValid,
      let buffer = sampleBuffer.imageBuffer,
      CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
    else { return }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let bytes = CVPixelBufferGetBaseAddress(buffer) else { return }
    let x = CVPixelBufferGetWidth(buffer) / 2
    let y = CVPixelBufferGetHeight(buffer) * 3 / 4
    let pixel = bytes.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer) + x * 4)
      .assumingMemoryBound(to: UInt8.self)
    guard pixel[3] == 255 else { return }
    let value = Double(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / (3 * 255)
    // The stream explicitly delivers its samples on the main queue.
    MainActor.assumeIsolated { brightness.append(value) }
  }
}
