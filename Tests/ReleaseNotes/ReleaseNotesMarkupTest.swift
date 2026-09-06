//
//  ReleaseNotesMarkupTest.swift
//  Latest Tests
//
//  Structural split from the original implementation.
//

import CryptoKit
import XCTest

@testable import Latest

final class ReleaseNotesMarkupTest: XCTestCase {
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
      \t<li>Improved update discovery performance.</li>
      \t<li>Fixed release note selection.</li>
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

    let string = try ReleaseNotesMarkup.attributedString(
      from: markdown, baseURL: nil, relevantVersion: "1.3.1"
    ).get()

    XCTAssertTrue(string.string.contains("Ghostty 1.3.1 includes changes"))
    XCTAssertTrue(string.string.contains("15 contributors over 100 commits"))
    XCTAssertTrue(string.string.contains("macOS Mouse Selection Bugs Fixed"))
    XCTAssertFalse(string.string.contains("title:"))
    XCTAssertFalse(string.string.contains("description:"))
    XCTAssertFalse(string.string.contains("**"))
    XCTAssertFalse(string.string.contains("---"))

    let compactMarkdown =
      "--- title: Ghostty 1.3.1 description: |- Release notes for Ghostty 1.3.1, released on March 13, 2026. --- Ghostty 1.3.1 includes changes from **15 contributors** over **100 commits**. This is a patch release focused on fixing regressions introduced in 1.3.0."
    let compactString = try ReleaseNotesMarkup.attributedString(
      from: compactMarkdown, baseURL: nil, relevantVersion: "1.3.1"
    ).get()
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
    let missingOpeningString = try ReleaseNotesMarkup.attributedString(
      from: missingOpeningDelimiterMarkdown, baseURL: nil, relevantVersion: "1.3.1"
    ).get()
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

    let string = try ReleaseNotesMarkup.attributedString(
      from: changelog, baseURL: nil, relevantVersion: "1.8.15"
    ).get()

    XCTAssertTrue(string.string.contains("AirPods loop fix"))
    XCTAssertFalse(string.string.contains("Device Routing fixes"))
  }

  func testReleaseNotesMarkupKeepsOnlyCurrentReleaseFromHTMLHistory() throws {
    let html = """
      <h2>AppCleaner 3.6.8 - 4 July, 2023</h2>
      <ul>
      \t<li>New app icon.</li>
      \t<li>Allow searching for related files of system apps.</li>
      </ul>
      <h2>AppCleaner 3.6.7 - 9 Dec, 2022</h2>
      <ul>
      \t<li>Fixed a bug causing SmartDelete to crash.</li>
      </ul>
      """

    let string = try ReleaseNotesMarkup.attributedString(
      from: html, baseURL: nil, relevantVersion: "3.6.8"
    ).get()

    XCTAssertTrue(string.string.contains("AppCleaner 3.6.8"))
    XCTAssertTrue(string.string.contains("New app icon"))
    XCTAssertFalse(string.string.contains("AppCleaner 3.6.7"))
    XCTAssertFalse(string.string.contains("SmartDelete"))
  }

  func testReleaseNotesMarkupRejectsVersionOnlyAndLinkOnlyText() throws {
    XCTAssertThrowsError(
      try ReleaseNotesMarkup.attributedString(
        from: "v3.4.2", baseURL: nil, relevantVersion: "3.4.2"
      ).get())
    XCTAssertThrowsError(
      try ReleaseNotesMarkup.attributedString(
        from:
          "<a href=\"https://example.com/details\">Details</a><br><a href=\"https://example.com/history\">Recent version history</a>",
        baseURL: nil, relevantVersion: "0.95"
      ).get())
    XCTAssertThrowsError(
      try ReleaseNotesMarkup.attributedString(
        from: "1.12.7 https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/", baseURL: nil,
        relevantVersion: "1.12.7"
      ).get())
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

    let string = try ReleaseNotesMarkup.attributedString(
      from: changelog, baseURL: nil, relevantVersion: "3.6"
    ).get()

    XCTAssertTrue(string.string.contains("3.6 May 29, 2026\nAuto-review Run Mode"))
    XCTAssertFalse(string.string.contains("3.5 May 20, 2026"))
  }

  func testReleaseNotesMarkupSeparatesCompactedSparkleChangelogText() throws {
    let changelog =
      "3.6 May 29, 2026 · Changelog Auto-review Run Mode Auto-review is a new run mode that allows Cursor to work for longer with fewer approval prompts and safer execution. Configure your run mode in Settings > Cursor Settings > Agents > Run Mode."

    let string = try ReleaseNotesMarkup.attributedString(
      from: changelog, baseURL: nil, relevantVersion: "3.6"
    ).get()

    XCTAssertTrue(
      string.string.contains(
        "3.6 May 29, 2026 · Changelog\nAuto-review Run Mode\nAuto-review is a new run mode"))
  }

  func testReleaseNotesMarkupDeduplicatesRepeatedLeadingVersionTitle() throws {
    let markdown = """
      IINA 1.4.3
      IINA 1.4.3
      IINA 1.4.3 fixes important security issues and regressions.
      Bug Fixes
      - Fix a security issue.
      """

    let string = try ReleaseNotesMarkup.attributedString(
      from: markdown, baseURL: nil, relevantVersion: "1.4.3"
    ).get()

    XCTAssertFalse(string.string.contains("IINA 1.4.3\nIINA 1.4.3\nIINA 1.4.3 fixes"))
    XCTAssertTrue(
      string.string.contains("IINA 1.4.3\nFixes important security issues and regressions."))
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

    XCTAssertThrowsError(
      try ReleaseNotesMarkup.attributedString(
        from: html, baseURL: URL(string: "https://www.notion.so/product")!, relevantVersion: "7.19"
      ).get())
  }

  func testReleaseNotesMarkupRejectsMojibakeText() throws {
    let gibberish = """
      Ñù¢x¿ëÆIw±¥ûs]z|².6 ç°^éÉ"st0Æñqd7wßZú¼üä,õ0!GéØ9cL=x16ãè³Ø´ÙÀ è på°7ÆgÝ².4,±ø}¿ õù±¯¾üiàpípjòÎ½c Ëp¾;µ¼,á{ÝVyÃ(ä¤Ç¶xs´i;»||
      ³HxåÿXèÕõ%ÍÁ÷9 óke  ˜&ó¼öU#êÒùñÛà¸}Òäwö¦¾¶Ex2EöòËÕÿÚüæ8Å/xÜcDøþéõ@ãÚ
      """

    XCTAssertThrowsError(
      try ReleaseNotesMarkup.attributedString(
        from: gibberish, baseURL: nil, relevantVersion: "5.80.6"
      ).get())
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

    let string = try ReleaseNotesMarkup.attributedString(
      from: html, baseURL: URL(string: "https://cursor.com/changelog")!, relevantVersion: "3.6"
    ).get()

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

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantText(
        from: changelog, version: "3.7", allowFirstSectionFallback: true))

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

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantText(
        from: changelog, version: "3.7", allowFirstSectionFallback: true))

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

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantChangelogText(
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

  func testReleaseNotesMarkupExtractsNavicatMacReleaseInsteadOfWindows() throws {
    let html = """
      <h2>Navicat Premium (Windows) version 17.3.12</h2>
      <p>Fixed a Windows-only credential manager issue.</p>
      <h2>Navicat Premium (macOS) version 17.3.12</h2>
      <ul><li>Added native support for the latest macOS database driver.</li><li>Improved sidebar responsiveness.</li></ul>
      <h2>Navicat Premium (Linux) version 17.3.12</h2>
      <p>Fixed a Linux package installation issue.</p>
      """

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantChangelogText(
        fromHTML: html,
        version: "17.3.12",
        pageURL: URL(string: "https://www.navicat.com/en/products/navicat-premium-release-note")!,
        allowFirstSectionFallback: false
      ))

    XCTAssertTrue(text.contains("Navicat Premium (macOS) version 17.3.12"))
    XCTAssertTrue(text.contains("native support"))
    XCTAssertFalse(text.contains("Windows-only"))
    XCTAssertFalse(text.contains("Linux package"))
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

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantChangelogText(
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

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantChangelogText(
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

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantChangelogText(
        fromHTML: html,
        version: "7.0.5",
        pageURL: URL(
          string: "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222")!,
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
      "articleBody": articleBody,
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

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantChangelogText(
        fromHTML: html,
        version: "7.0.5",
        pageURL: URL(
          string: "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222")!,
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
      baseURL: URL(
        string: "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222")!,
      relevantVersion: "7.0.5"
    ).get().string
    XCTAssertTrue(renderedText.contains("Show or hide icon labels"))
    XCTAssertTrue(renderedText.contains("Minor bug fixes"))
  }
  func testReleaseNotesMarkupExtractsVersionedArticleFrom1PasswordPage() throws {
    let html = """
      <section class="c-updates">
      \t<article class="c-updates__release">
      \t\t<header>
      \t\t\t<time>June 2 2026</time>
      \t\t\t<h6>1Password for Mac 8.12.22</h6>
      \t\t</header>
      \t\t<div class="c-updates__content">
      \t\t\t<ul>
      \t\t\t\t<li>We&rsquo;ve improved the scrolling experience to better match typical macOS scrolling behavior.</li>
      \t\t\t</ul>
      \t\t</div>
      \t</article>
      \t<article class="c-updates__release">
      \t\t<header>
      \t\t\t<time>May 20 2026</time>
      \t\t\t<h6>1Password for Mac 8.12.21</h6>
      \t\t</header>
      \t\t<div class="c-updates__content">
      \t\t\t<ul><li>Older release notes should not be included.</li></ul>
      \t\t</div>
      \t</article>
      </section>
      """

    let article = try XCTUnwrap(
      ReleaseNotesMarkup.releaseContentHTML(
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

    let url = try XCTUnwrap(
      ReleaseNotesMarkup.linkedChangelogURL(
        fromHTML: html,
        version: "1.12.7",
        pageURL: URL(string: "https://obsidian.md/changelog/")!
      ))

    XCTAssertEqual(url.absoluteString, "https://obsidian.md/changelog/2026-03-23-desktop-v1.12.7/")
  }

  func testReleaseNotesMarkupPrefersObsidianDesktopArticle() throws {
    let html = """
      <article>
      \t<h2>1.12.7 Mobile</h2>
      \t<p>Includes all new features and bug fixes up to Obsidian Desktop v1.12.7.</p>
      </article>
      <article>
      \t<h2>1.12.7 Desktop</h2>
      \t<h3>Improvements</h3>
      \t<p>The Obsidian Installer is now bundled with a new binary file for using the CLI.</p>
      </article>
      """

    let article = try XCTUnwrap(
      ReleaseNotesMarkup.releaseContentHTML(
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

    let relevantText = try XCTUnwrap(
      ReleaseNotesMarkup.relevantChangelogText(
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
      \t<h2>1.13.1 Mobile</h2>
      \t<p>Includes all new features and bug fixes up to Obsidian Desktop v1.13.1.</p>
      \t<h2>1.13.1 Desktop</h2>
      \t<p>Sliders now show a permanent label with the current value.</p>
      </div>
      """

    XCTAssertNil(
      ReleaseNotesMarkup.releaseContentHTML(
        fromHTML: html,
        version: "1.13.1",
        pageURL: URL(string: "https://obsidian.md/changelog/")!
      ))

    XCTAssertNotNil(
      ReleaseNotesMarkup.releaseContentHTML(
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

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantText(
        from: changelog, version: "3.4", allowFirstSectionFallback: true))

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

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantText(
        from: changelog, version: "1.4.4", allowFirstSectionFallback: false))

    XCTAssertFalse(text.contains("1.4.3 • 1.4.2"))
    XCTAssertTrue(text.contains("Fixed an issue where using GPT models"))
    XCTAssertFalse(text.contains("empty model dropdown"))
  }

  func testReleaseNotesMarkupSkipsZedVersionSidebarList() throws {
    let html = """
      <nav>
      \t<h2>Versions</h2>
      \t<a href="/releases/stable/1.6.3">1.6.3</a>
      \t<a href="/releases/stable/1.5.5">1.5.5</a>
      \t<a href="/releases/stable/1.5.4">1.5.4</a>
      \t<h2>Versions</h2>
      \t<a href="/releases/stable/1.6.3">1.6.3</a>
      \t<a href="/releases/stable/1.5.5">1.5.5</a>
      \t<a href="/releases/stable/1.5.4">1.5.4</a>
      </nav>
      <main>
      \t<h2>June 2026</h2>
      \t<p>* * *</p>
      \t<h2>1.6.3</h2>
      \t<p>Jun 10, 2026</p>
      \t<p>macOS</p>
      \t<p>Loading…</p>
      \t<p>Windows</p>
      \t<p>Loading...</p>
      \t<p>Linux</p>
      \t<p>This week's release includes the ability to open a Git diff for a single file.</p>
      \t<h3>Features</h3>
      \t<ul>
      \t\t<li>Agent: Added a way to share skills via links.</li>
      \t</ul>
      \t<h2>1.5.5</h2>
      \t<p>Jun 09, 2026</p>
      \t<ul>
      \t\t<li>Older release note.</li>
      \t</ul>
      </main>
      """

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantChangelogText(
        fromHTML: html, version: "1.6.3",
        pageURL: URL(string: "https://zed.dev/releases/stable/1.6.3")!,
        allowFirstSectionFallback: false))

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

    let text = try XCTUnwrap(
      ZedReleaseNotesExtractor.zedReleaseText(
        fromHTML: html, version: "1.4.4",
        pageURL: URL(string: "https://zed.dev/releases/stable/1.4.4")!))

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
      \t<p>Version : 1.6.3</p>
      \t<p>Platform : macOS</p>
      \t<p>Trusted by world-class developers and industry leading teams</p>
      </main>
      <script>self.__next_f.push([1,"106:T4b60,"])</script>
      <script>self.__next_f.push([1,"This week's release includes the ability to open a Git diff for a single file.\\r\\n\\r\\n## Features\\r\\n\\r\\n- Agent: Added a way to share skills via links.\\r\\n"])</script>
      """

    let text = try XCTUnwrap(
      ZedReleaseNotesExtractor.zedReleaseText(
        fromHTML: html, version: "1.6.3",
        pageURL: URL(string: "https://zed.dev/releases/stable/1.6.3")!))

    XCTAssertTrue(text.hasPrefix("This week's release"))
    XCTAssertTrue(text.contains("Agent: Added a way to share skills"))
    XCTAssertFalse(text.contains("$106"))
    XCTAssertFalse(text.contains("Version : 1.6.3"))
  }

  func testReleaseNotesMarkupExtractsRelevantSectionFromHTMLWithoutRendering() throws {
    let html = """
      <html>
      <head>
      \t<script>window.versions = ["1.4.3"];</script>
      </head>
      <body>
      \t<h2>1.4.4</h2>
      \t<p>Fixed &amp; improved<br>Added &#33; support</p>
      \t<h2>1.4.3</h2>
      \t<p>Previous release</p>
      </body>
      </html>
      """

    let text = try XCTUnwrap(
      ReleaseNotesMarkup.relevantChangelogText(
        fromHTML: html, version: "1.4.4", pageURL: URL(string: "https://example.com/changelog")!,
        allowFirstSectionFallback: false))

    XCTAssertTrue(text.contains("Fixed & improved"))
    XCTAssertTrue(text.contains("Added ! support"))
    XCTAssertFalse(text.contains("Previous release"))
    XCTAssertFalse(text.contains("window.versions"))
  }

}
