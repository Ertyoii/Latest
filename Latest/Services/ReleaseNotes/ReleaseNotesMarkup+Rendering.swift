//
//  ReleaseNotesMarkup+Rendering.swift
//  Latest
//
//  Rich-text rendering for normalized release-note markup.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-09-04.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit

extension ReleaseNotesMarkup {

  static func attributedString(fromMarkdown markdown: String) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let headingFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
    let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    markdown.components(separatedBy: .newlines).forEach { line in
      let trimmedLine = line.trimmingCharacters(in: .whitespaces)
      let text: String
      let font: NSFont

      if let headingRange = trimmedLine.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
        text = String(trimmedLine[headingRange.upperBound...])
        font = headingFont
      } else if let bulletRange = trimmedLine.range(
        of: #"^(\*|-|•)\s+"#, options: .regularExpression)
      {
        text =
          "• " + removingLeadingBulletMarkers(from: String(trimmedLine[bulletRange.upperBound...]))
        font = bodyFont
      } else if let numberedRange = trimmedLine.range(
        of: #"^\d+\.\s+"#, options: .regularExpression)
      {
        text =
          String(trimmedLine[..<numberedRange.upperBound])
          + String(trimmedLine[numberedRange.upperBound...])
        font = bodyFont
      } else {
        text = trimmedLine
        font = bodyFont
      }

      result.append(NSAttributedString(string: text + "\n", attributes: [.font: font]))
    }

    return result
  }

  static func attributedString(fromPlainText text: String) -> NSAttributedString {
    NSAttributedString(
      string: text + "\n", attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
  }

  static func attributedString(fromHTML html: String, baseURL: URL?)
    -> ReleaseNotesProvider.ReleaseNotes
  {
    guard let data = html.data(using: .utf16) else {
      return .failure(LatestError.releaseNotesUnavailable)
    }

    if let string = attributedString(fromHTMLData: data, baseURL: baseURL) {
      return .success(string)
    }

    guard let plainText = plainText(fromHTML: html),
      isUsefulReleaseNotesText(plainText)
    else {
      return .failure(LatestError.releaseNotesUnavailable)
    }
    return .success(attributedString(fromPlainText: plainText))
  }

  static func prefersMarkdown(_ string: String) -> Bool {
    guard !string.containsHTMLTag else { return false }

    return string.split(whereSeparator: \.isNewline).contains { line in
      let trimmedLine = line.drop(while: \.isWhitespace)
      return trimmedLine.hasPrefix("#") || trimmedLine.hasPrefix("* ")
        || trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("• ")
        || trimmedLine.range(of: #"^\d+\. "#, options: .regularExpression) != nil
    }
  }

  private static func attributedString(fromHTMLData data: Data, baseURL: URL?)
    -> NSAttributedString?
  {
    if let baseURL {
      return NSAttributedString(html: data, baseURL: baseURL, documentAttributes: nil)
    }

    return NSAttributedString(html: data, documentAttributes: nil)
  }

  private static func removingLeadingBulletMarkers(from string: String) -> String {
    var result = string.trimmingCharacters(in: .whitespaces)

    while let range = result.range(of: #"^(\*|-|•)\s+"#, options: .regularExpression) {
      result = String(result[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    return result
  }

}
