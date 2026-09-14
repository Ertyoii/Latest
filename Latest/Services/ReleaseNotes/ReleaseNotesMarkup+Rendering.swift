// Copyright © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit

extension ReleaseNotesMarkup {
  static func attributedString(fromMarkdown markdown: String, baseURL: URL? = nil)
    -> NSAttributedString
  {
    let cleaned = markdown.replacingOccurrences(
      of: #"(?m)^(\s*)[-*•]\s+[-*•]\s+"#, with: "$1- ", options: .regularExpression
    )
    .replacingOccurrences(of: #"(?m)^(\s*)[•◦]\s+"#, with: "$1- ", options: .regularExpression)
    let structured = cleaned.components(separatedBy: .newlines).map { line in
      let label = line.trimmingCharacters(in: .whitespaces)
      if !label.hasPrefix("#"), ReleaseNotesMarkup.looksLikeVersionBoundary(label) {
        return "## " + label
      }
      if [
        "Features", "New", "Improvements", "Bug Fixes", "Bug fixes", "Fixes", "Changes",
        "Highlights", "Resolved issues", "Security", "No longer broken", "Maintenance",
      ].contains(label) {
        return "### " + label
      }
      return line
    }.joined(separator: "\n")
    return ReleaseNotesDocument.render(structured, baseURL: baseURL)
  }

  static func attributedString(fromPlainText text: String) -> NSAttributedString {
    ReleaseNotesDocument.render(text.replacingOccurrences(of: "\n", with: "  \n"))
  }

  static func attributedString(fromHTML html: String, baseURL: URL?)
    -> ReleaseNotesProvider.ReleaseNotes
  {
    guard let markdown = ReleaseNotesDocument.markdown(fromHTML: html, baseURL: baseURL),
      isUsefulReleaseNotesText(markdown)
    else { return .failure(LatestError.releaseNotesUnavailable) }
    return .success(ReleaseNotesDocument.render(markdown, baseURL: baseURL))
  }

  static func prefersMarkdown(_ string: String) -> Bool {
    !string.containsHTMLTag
      && string.range(
        of: #"(?m)^\s*(?:#{1,6} |[-*•◦] |\d+\. |```)|\[[^\]]+\]\(|\*|_|`"#,
        options: .regularExpression) != nil
  }
}
