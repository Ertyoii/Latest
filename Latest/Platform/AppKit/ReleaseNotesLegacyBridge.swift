// Copyright © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import Foundation

/// Compatibility boundary for WebKit's existing rich-text input and the v2 RTF cache.
/// Parsing and semantic preparation belong to ReleaseNotesDocument.
enum ReleaseNotesLegacyBridge {
  static func attributedString(from text: AttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString()
    var styles: [ReleaseNotesStyle: [NSAttributedString.Key: Any]] = [:]
    for run in text.runs {
      var attributes: [NSAttributedString.Key: Any] = [:]
      if let style = run[ReleaseNotesStyleKey.self] {
        attributes = styles[style] ?? nativeAttributes(for: style)
        styles[style] = attributes
      }
      if let link = run.link { attributes[.link] = link }
      result.append(
        NSAttributedString(string: String(text[run.range].characters), attributes: attributes))
    }
    return result
  }

  private static func nativeAttributes(for style: ReleaseNotesStyle)
    -> [NSAttributedString.Key: Any]
  {
    let base =
      style.monospaced
      ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
      : NSFont.systemFont(ofSize: 13)
    var traits: NSFontDescriptor.SymbolicTraits = []
    if style.bold { traits.insert(.bold) }
    if style.italic { traits.insert(.italic) }
    var attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont(
        descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: base.pointSize)
        ?? base
    ]
    if let paragraph = style.paragraph {
      let native = NSMutableParagraphStyle()
      native.paragraphSpacing = paragraph.spacing
      native.paragraphSpacingBefore = paragraph.spacingBefore
      native.headIndent = paragraph.headIndent
      native.firstLineHeadIndent = paragraph.firstLineHeadIndent
      native.lineSpacing = 2
      attributes[.paragraphStyle] = native
      attributes[.foregroundColor] = NSColor.labelColor
    }
    if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
    return attributes
  }

  /// Retains Foundation's legacy encoding detection for non-UTF8 vendor notes.
  static func decode(_ data: Data) throws -> NSAttributedString {
    var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
      .documentType: NSAttributedString.DocumentType.html
    ]
    let text = try NSAttributedString(data: data, options: options, documentAttributes: nil)
    if text.string.split(separator: "\n").count == 1 {
      options[.documentType] = NSAttributedString.DocumentType.plain
      return try NSAttributedString(data: data, options: options, documentAttributes: nil)
    }
    return text
  }

  static func rtf(from text: NSAttributedString) throws -> Data {
    try text.data(
      from: NSRange(location: 0, length: text.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
  }

  static func decodeRTF(_ data: Data) throws -> NSAttributedString {
    try NSAttributedString(
      data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
      documentAttributes: nil)
  }
}
