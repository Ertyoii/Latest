import AppKit
import Foundation

enum NavicatReleaseNotesExtractor {
  static func navicatMacReleaseText(fromHTML html: String, version: String?, pageURL: URL)
    -> String?
  {
    guard pageURL.host?.localizedCaseInsensitiveContains("navicat.com") == true,
      let text = ReleaseNotesMarkup.plainText(fromHTML: html)
    else {
      return nil
    }

    let candidates = ReleaseNotesMarkup.versionCandidates(from: version)
    guard !candidates.isEmpty else { return nil }
    let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
      let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmedLine.isEmpty ? nil : trimmedLine
    }

    guard
      let startIndex = lines.firstIndex(where: { line in
        line.localizedCaseInsensitiveContains("(macOS)")
          && line.localizedCaseInsensitiveContains("version")
          && candidates.contains(where: { line.localizedCaseInsensitiveContains($0) })
      })
    else {
      return nil
    }

    var endIndex = lines.endIndex
    for index in (startIndex + 1)..<lines.endIndex {
      let line = lines[index]
      let isPlatformReleaseHeading =
        line.localizedCaseInsensitiveContains("version")
        && (line.localizedCaseInsensitiveContains("(Windows)")
          || line.localizedCaseInsensitiveContains("(macOS)")
          || line.localizedCaseInsensitiveContains("(Linux)"))
      if isPlatformReleaseHeading {
        endIndex = index
        break
      }
    }

    let releaseText = lines[startIndex..<endIndex].joined(separator: "\n")
    guard ReleaseNotesMarkup.isUsefulReleaseNotesText(releaseText, relevantVersion: version) else {
      return nil
    }

    return releaseText
  }
}
