//
//  ReleaseNotesWebView.swift
//  Latest
//
//  Created by ertyoii on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-01.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import Combine
import SwiftUI
import WebKit

/// SwiftUI owns the page lifetime; WebKit retains native text selection and scrolling.
struct ReleaseNotesWebView: View {
  let text: NSAttributedString?
  @StateObject private var renderer = ReleaseNotesPage()

  var body: some View {
    WebView(renderer.page)
      .webViewBackForwardNavigationGestures(.disabled)
      .webViewMagnificationGestures(.disabled)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Release Notes")
      .accessibilityIdentifier("release-notes.web")
      .onAppear { renderer.display(text) }
      .onChange(of: text.map(ObjectIdentifier.init)) { renderer.display(text) }
      .onDisappear { renderer.stop() }
  }
}

@MainActor
private final class ReleaseNotesPage: ObservableObject {
  let page: WebPage
  private var displayedText: NSAttributedString?

  init() {
    var configuration = WebPage.Configuration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultNavigationPreferences.allowsContentJavaScript = false
    page = WebPage(configuration: configuration, navigationDecider: ReleaseNotesNavigationDecider())
  }

  func display(_ text: NSAttributedString?) {
    guard let text, displayedText !== text else { return }
    displayedText = text
    page.load(html: ReleaseNotesWebDocument.html(for: text))
  }

  func stop() {
    page.stopLoading()
    displayedText = nil
  }
}

private struct ReleaseNotesNavigationDecider: WebPage.NavigationDeciding {
  func decidePolicy(
    for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences
  ) async -> WKNavigationActionPolicy {
    if action.navigationType == .linkActivated,
      let url = ReleaseNotesWebDocument.externalURL(action.request.url)
    {
      NSWorkspace.shared.open(url)
    }
    return action.navigationType == .other && action.request.url?.absoluteString == "about:blank"
      ? .allow : .cancel
  }
}

/// Serializes only the prepared rich text. No vendor scripts, styles, embeds or
/// network resources enter the display web view.
enum ReleaseNotesWebDocument {
  static func html(for text: NSAttributedString) -> String {
    let plainText = text.string as NSString
    var body = ""
    body.reserveCapacity(plainText.length)
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) {
      attributes, range, _ in
      var run = escape(plainText.substring(with: range), normalizingTabs: true)
      if let font = attributes[.font] as? NSFont {
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.bold) { run = "<strong>" + run + "</strong>" }
        if traits.contains(.italic) { run = "<em>" + run + "</em>" }
        if traits.contains(.monoSpace) { run = "<code>" + run + "</code>" }
      }
      if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { run = "<s>" + run + "</s>" }
      if let url = externalURL(attributes[.link]) {
        run = "<a href=\"" + escape(url.absoluteString) + "\">" + run + "</a>"
      }
      body += run
    }
    return """
      <!doctype html><html><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
      <style>
      :root { color-scheme: light dark; }
      body { margin: 0; padding: 14px 20px; font: 13px/1.6 -apple-system, sans-serif;
        color: CanvasText; background: Canvas; overflow-wrap: anywhere; }
      main { white-space: pre-wrap; }
      a { color: -apple-system-blue; }
      code { font-family: ui-monospace, monospace; font-size: 12px; }
      </style></head><body><main aria-label="Release Notes">\(body)</main></body></html>
      """
  }

  static func externalURL(_ value: Any?) -> URL? {
    let url: URL?
    switch value {
    case let value as URL: url = value
    case let value as String: url = URL(string: value)
    default: return nil
    }
    guard let url else { return nil }
    switch url.scheme?.lowercased() {
    case "http", "https", "mailto": return url
    default: return nil
    }
  }

  private static func escape(_ string: String, normalizingTabs: Bool = false) -> String {
    var result = ""
    result.reserveCapacity(string.utf8.count)
    for scalar in string.unicodeScalars {
      switch scalar {
      case "&": result += "&amp;"
      case "<": result += "&lt;"
      case ">": result += "&gt;"
      case "\"": result += "&quot;"
      case "\t" where normalizingTabs: result += " "
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result
  }
}
