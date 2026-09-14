//
//  SelectableReleaseNotesTextView.swift
//  Latest
//
//  Created by ertyoii on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-01.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI

enum ReleaseNotesTextFormatter {
  static func format(_ attributedString: NSAttributedString) -> NSAttributedString {
    let string = NSMutableAttributedString(attributedString: attributedString)
    string.mutableString.replaceOccurrences(
      of: "\t",
      with: " ",
      options: [],
      range: NSRange(location: 0, length: string.length)
    )

    let textRange = NSRange(location: 0, length: string.length)
    let defaultFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    string.removeAttribute(.foregroundColor, range: textRange)
    string.addAttribute(.foregroundColor, value: NSColor.labelColor, range: textRange)
    string.removeAttribute(.backgroundColor, range: textRange)
    string.removeAttribute(.shadow, range: textRange)
    string.removeAttribute(.font, range: textRange)
    string.addAttribute(.font, value: defaultFont, range: textRange)

    let plainText = string.string
    plainText.enumerateSubstrings(
      in: plainText.startIndex..<plainText.endIndex, options: .byParagraphs
    ) { paragraph, range, _, _ in
      guard let paragraph else { return }
      let nsRange = NSRange(range, in: plainText)
      let original =
        string.attribute(.paragraphStyle, at: nsRange.location, effectiveRange: nil)
        as? NSParagraphStyle
      let isList = paragraph.range(of: #"^\s*(?:[•◦]|\d+\.)\s"#, options: .regularExpression) != nil
      let style = NSMutableParagraphStyle()
      style.alignment = .left
      style.tabStops = []
      style.lineSpacing = min(max(original?.lineSpacing ?? 0, 0), 2)
      style.paragraphSpacing = min(max(original?.paragraphSpacing ?? 0, 0), isList ? 4 : 8)
      style.paragraphSpacingBefore = min(original?.paragraphSpacingBefore ?? 0, 5)
      if isList {
        style.firstLineHeadIndent = min(max(original?.firstLineHeadIndent ?? 0, 0), 64)
        style.headIndent = style.firstLineHeadIndent + 14
      }
      string.addAttribute(.paragraphStyle, value: style, range: nsRange)
    }

    attributedString.enumerateAttribute(.font, in: textRange) { fontObject, range, _ in
      guard let font = fontObject as? NSFont else { return }
      let baseFont =
        font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) : defaultFont
      let descriptor = baseFont.fontDescriptor.withSymbolicTraits(
        font.fontDescriptor.symbolicTraits)
      if let replacement = NSFont(descriptor: descriptor, size: baseFont.pointSize) {
        string.addAttribute(.font, value: replacement, range: range)
      }
    }

    return string
  }
}

struct SelectableReleaseNotesTextView: NSViewRepresentable {
  let text: NSAttributedString

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.automaticallyAdjustsContentInsets = false

    let textView = NSTextView()
    textView.drawsBackground = false
    textView.isEditable = false
    textView.isSelectable = true
    textView.allowsUndo = false
    textView.isRichText = true
    textView.importsGraphics = false
    // Keep padding in document coordinates: clip-view insets can be consumed
    // by scrollRangeToVisible when the same view displays another app.
    textView.textContainerInset = NSSize(
      width: VisualMetrics.releaseNotesTextInset,
      height: VisualMetrics.releaseNotesTextInset
    )
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: scrollView.contentSize.width,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.setAccessibilityIdentifier("release-notes.text")
    textView.setAccessibilityLabel("Release Notes")

    scrollView.documentView = textView
    context.coordinator.textView = textView
    context.coordinator.apply(text)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.apply(text)
  }

  @MainActor
  final class Coordinator {
    weak var textView: NSTextView?
    private var displayedText: NSAttributedString?

    func apply(_ text: NSAttributedString) {
      guard displayedText !== text else { return }
      displayedText = text
      let formatted = ReleaseNotesTextFormatter.format(text)
      textView?.textStorage?.setAttributedString(formatted)
      textView?.setSelectedRange(NSRange(location: 0, length: 0))
      textView?.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
  }
}
