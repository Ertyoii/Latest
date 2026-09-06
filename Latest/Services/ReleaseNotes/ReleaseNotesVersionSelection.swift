import AppKit
import Foundation

extension ReleaseNotesMarkup {
  static func relevantText(
    from text: String, version: String?, allowFirstSectionFallback: Bool,
    preferredSuffix: String? = nil
  ) -> String? {
    let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
      let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmedLine.isEmpty ? nil : trimmedLine
    }

    guard !lines.isEmpty else { return nil }

    let versionCandidates = Self.versionCandidates(from: version)
    var startIndex: Int?

    if !versionCandidates.isEmpty {
      func matchers(preferredSuffix: String?) -> [NSRegularExpression] {
        versionCandidates.compactMap { version in
          let escapedVersion = NSRegularExpression.escapedPattern(for: version)
          let pattern: String
          if let preferredSuffix {
            let escapedSuffix = NSRegularExpression.escapedPattern(for: preferredSuffix)
            pattern = #"(^|[^\d])v?\#(escapedVersion)\s+\#(escapedSuffix)([^\w]|\z)"#
          } else {
            pattern = #"(^|[^\d])v?\#(escapedVersion)([^\d]|\z)"#
          }
          return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
      }

      let standardMatchers = matchers(preferredSuffix: nil)
      let preferredMatchers = preferredSuffix.map { matchers(preferredSuffix: $0) } ?? []

      func matchingVersionIndex(requiresBoundary: Bool, matchers: [NSRegularExpression]) -> Int? {
        for (index, line) in lines.enumerated() {
          guard !Self.looksLikeVersionNavigation(line, at: index, in: lines),
            !requiresBoundary || Self.looksLikeVersionBoundary(line)
          else { continue }

          let lineRange = NSRange(line.startIndex..<line.endIndex, in: line)
          if matchers.contains(where: { regex in
            regex.firstMatch(in: line, range: lineRange) != nil
          }) {
            return index
          }
        }

        return nil
      }

      if preferredSuffix != nil {
        startIndex =
          matchingVersionIndex(requiresBoundary: true, matchers: preferredMatchers)
          ?? matchingVersionIndex(requiresBoundary: false, matchers: preferredMatchers)
      }

      startIndex =
        startIndex ?? matchingVersionIndex(requiresBoundary: true, matchers: standardMatchers)
        ?? matchingVersionIndex(requiresBoundary: false, matchers: standardMatchers)
    }

    if startIndex == nil, allowFirstSectionFallback {
      startIndex = lines.firstIndex { line in
        Self.looksLikeReleaseBoundary(line)
      }
    }

    guard let startIndex else { return nil }
    let exactVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines)
    let startLine = lines[startIndex]
    let shouldEndAtVersionBoundary = Self.looksLikeVersionBoundary(startLine)
    let startsWithBareVersionLine = Self.isBareVersionLine(startLine)
    var endIndex = lines.endIndex
    for index in (startIndex + 1)..<lines.endIndex {
      let line = lines[index]
      let isImmediateDateAfterBareVersion =
        startsWithBareVersionLine && index == startIndex + 1
        && Self.looksLikeDateReleaseBoundary(line)
      let isBoundary =
        if shouldEndAtVersionBoundary {
          Self.looksLikeVersionBoundary(line)
            || (Self.looksLikeDateReleaseBoundary(line) && !isImmediateDateAfterBareVersion)
        } else {
          Self.looksLikeReleaseBoundary(line)
        }

      if isBoundary && !(exactVersion.map { line.localizedCaseInsensitiveContains($0) } ?? false) {
        endIndex = index
        break
      }
    }

    let selectedLines = lines[startIndex..<endIndex]
    guard !selectedLines.isEmpty else { return nil }

    return selectedLines.joined(separator: "\n")
  }

  static func lineContainsVersionCandidate(_ line: String, candidates: [String]) -> Bool {
    candidates.contains { candidate in
      let escapedCandidate = NSRegularExpression.escapedPattern(for: candidate)
      return line.range(
        of: #"(^|[^\d])v?\#(escapedCandidate)([^\d]|\z)"#,
        options: [.regularExpression, .caseInsensitive]) != nil
    }
  }

  static func versionCandidates(from version: String?) -> [String] {
    guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty
    else {
      return []
    }

    var candidates = [version]
    let parts = version.split(separator: ".", omittingEmptySubsequences: true)
    if parts.count >= 2 {
      candidates.append(parts.prefix(2).joined(separator: "."))
    }

    return Array(Set(candidates)).sorted { $0.count > $1.count }
  }

  private static func looksLikeReleaseBoundary(_ line: String) -> Bool {
    Self.looksLikeVersionBoundary(line) || Self.looksLikeDateReleaseBoundary(line)
  }

  static func looksLikeDateReleaseBoundary(_ line: String) -> Bool {
    line.range(of: #"^[A-Z][a-z]+ \d{1,2}, \d{4}"#, options: .regularExpression) != nil
  }

  static func looksLikeVersionBoundary(_ line: String) -> Bool {
    line.range(of: #"^#{1,6}\s*v?\d+(\.\d+){1,}"#, options: [.regularExpression, .caseInsensitive])
      != nil
      || line.range(
        of: #"^v?\d+(\.\d+){1,}(\s|$|-)"#, options: [.regularExpression, .caseInsensitive]) != nil
      || line.range(
        of: #"^(?![-*•])\D{1,60}v?\d+(\.\d+){1,}(\s|$|-)"#,
        options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static func looksLikeVersionNavigation(_ line: String, at index: Int, in lines: [String])
    -> Bool
  {
    if Self.looksLikeDenseVersionNavigation(line) {
      return true
    }

    guard Self.isBareVersionLine(line) else { return false }

    if lines.indices.contains(index + 1), Self.looksLikeDateReleaseBoundary(lines[index + 1]) {
      return false
    }

    if index > lines.startIndex, Self.isBareVersionLine(lines[index - 1]) {
      return true
    }

    if lines.indices.contains(index + 1), Self.isBareVersionLine(lines[index + 1]) {
      return true
    }

    return index > lines.startIndex
      && Self.versionNavigationWords.contains(lines[index - 1].lowercased())
  }

  private static func looksLikeDenseVersionNavigation(_ line: String) -> Bool {
    let matches = line.matches(of: /\bv?\d+(?:\.\d+){1,}\b/)
    guard matches.count >= 4 else { return false }

    let words = line.matches(of: /[A-Za-z]{3,}/).map { String(line[$0.range]) }
    let meaningfulWords = words.filter { !Self.versionNavigationWords.contains($0.lowercased()) }

    return meaningfulWords.count <= 2
  }

  static func isBareVersionLine(_ line: String) -> Bool {
    line.range(of: #"^v?\d+(\.\d+){1,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
  }
}
