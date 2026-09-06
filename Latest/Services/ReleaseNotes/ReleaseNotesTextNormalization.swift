import AppKit
import Foundation

extension ReleaseNotesMarkup {
  static func isUsefulReleaseNotesText(_ text: String, relevantVersion: String? = nil) -> Bool {
    let displayText: String
    if text.containsHTMLTag {
      guard let plainText = Self.plainText(fromHTML: text) else {
        return false
      }
      displayText = plainText
    } else {
      displayText = text
    }
    guard !Self.looksLikeBinaryOrMojibakeText(displayText),
      !Self.looksLikeWebPageChrome(displayText)
    else {
      return false
    }

    var informationText = displayText
    informationText = replacingMatches(in: informationText, matching: Regexes.rawURL, with: " ")
    informationText = replacingMatches(
      in: informationText, matching: Regexes.markdownLink, with: " ")
    informationText = replacingMatches(
      in: informationText, matching: Regexes.versionNumber, with: " ")
    if let relevantVersion, !relevantVersion.isEmpty {
      informationText = informationText.replacingOccurrences(
        of: relevantVersion, with: " ", options: [.caseInsensitive])
    }
    informationText = replacingMatches(in: informationText, matching: Regexes.namedDate, with: " ")
    informationText = replacingMatches(in: informationText, matching: Regexes.isoDate, with: " ")

    let lowercasedInformationText = informationText.lowercased()
    let words = lowercasedInformationText.matches(of: /[a-z][a-z0-9+-]{1,}/).map {
      String(lowercasedInformationText[$0.range])
    }
    let meaningfulWords = words.filter { !Self.genericReleaseNoteWords.contains($0) }

    return meaningfulWords.count >= 2 || meaningfulWords.joined().count >= 14
  }

  static func normalizedReleaseLine(_ line: String) -> String {
    var normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
    normalized = normalized.replacingOccurrences(
      of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
    normalized = normalized.replacingOccurrences(
      of: #"^(\*|-|•)\s+"#, with: "", options: .regularExpression)
    normalized = normalized.replacingOccurrences(
      of: #"\s+"#, with: " ", options: .regularExpression)
    return normalized.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
      .lowercased()
  }

  static func looksLikeBinaryOrMojibakeText(_ text: String) -> Bool {
    var scalarCount = 0
    var containsControlCharacter = false
    var cjkCount = 0
    var latin1SupplementCount = 0
    var nonASCIIPrintableCount = 0

    for scalar in text.unicodeScalars where !scalar.properties.isWhitespace {
      scalarCount += 1

      let scalarValue = Int(scalar.value)
      if (scalar.value < 32 || scalar.value == 127) && scalar.value != 10 && scalar.value != 9
        && scalar.value != 13
      {
        containsControlCharacter = true
      }
      if (0x4E00...0x9FFF).contains(scalarValue) || (0x3040...0x30FF).contains(scalarValue)
        || (0xAC00...0xD7AF).contains(scalarValue)
      {
        cjkCount += 1
      }
      if (0x00A0...0x00FF).contains(scalarValue) {
        latin1SupplementCount += 1
      }
      if scalar.value > 127 {
        nonASCIIPrintableCount += 1
      }
    }

    guard scalarCount > 40 else { return false }

    if containsControlCharacter {
      return true
    }

    let cjkRatio = Double(cjkCount) / Double(scalarCount)
    if cjkRatio > 0.2 {
      return false
    }

    let asciiWordCount = text.matches(of: /[A-Za-z][A-Za-z0-9+-]{2,}/).count
    let latin1Ratio = Double(latin1SupplementCount) / Double(scalarCount)
    let nonASCIIRatio = Double(nonASCIIPrintableCount) / Double(scalarCount)

    return (latin1Ratio > 0.22 && asciiWordCount < 8)
      || (nonASCIIRatio > 0.55 && asciiWordCount < 4)
  }

  private static func looksLikeWebPageChrome(_ text: String) -> Bool {
    let lines = text.components(separatedBy: .newlines).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    guard lines.count >= 12 else { return false }

    let separatorLineCount = lines.filter { $0 == "-" || $0 == "–" || $0 == "—" }.count
    if separatorLineCount >= 4 {
      return true
    }

    let lowercased = text.lowercased()
    let hasReleaseTerms = Self.webPageChromeReleaseTerms.contains { lowercased.contains($0) }
    if lines.count >= 30 && !hasReleaseTerms {
      return true
    }

    let shortNavigationLikeLines = lines.filter { line in
      let wordCount = line.split(separator: " ").count
      return wordCount <= 5 && !line.contains(".") && !line.contains(":")
    }
    return lines.count >= 18 && shortNavigationLikeLines.count >= 12 && !hasReleaseTerms
  }

  static func removingDuplicateLeadingLines(_ text: String) -> String {
    var lines = text.components(separatedBy: .newlines)
    while lines.count > 1 {
      let first = Self.normalizedReleaseLine(lines[0])
      let second = Self.normalizedReleaseLine(lines[1])
      guard !first.isEmpty, first == second else { break }
      lines.remove(at: 1)
    }

    if lines.count > 1,
      let releaseTitle = Self.releaseTitleText(from: lines[0]),
      let bodyWithoutRepeatedTitle = Self.bodyLineWithoutRepeatedTitle(
        lines[1], releaseTitle: releaseTitle)
    {
      lines[1] = bodyWithoutRepeatedTitle
    }

    return lines.joined(separator: "\n")
  }

  private static func releaseTitleText(from line: String) -> String? {
    var title = line.trimmingCharacters(in: .whitespacesAndNewlines)
    title = title.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
    title = title.replacingOccurrences(of: #"^(\*|-|•)\s+"#, with: "", options: .regularExpression)
    title = title.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    return title.isEmpty ? nil : title
  }

  private static func bodyLineWithoutRepeatedTitle(_ line: String, releaseTitle: String) -> String?
  {
    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let range = trimmedLine.range(
        of: releaseTitle, options: [.anchored, .caseInsensitive, .diacriticInsensitive])
    else {
      return nil
    }

    let suffix = trimmedLine[range.upperBound...]
    guard suffix.first.map({ $0.isWhitespace || "-–—:".contains($0) }) ?? false else {
      return nil
    }

    let remainder =
      suffix
      .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:").union(.whitespacesAndNewlines))
    guard Self.looksLikeReleaseSentence(remainder) else {
      return nil
    }

    return Self.capitalizingFirstLetter(remainder)
  }

  private static func looksLikeReleaseSentence(_ text: String) -> Bool {
    guard let firstWord = text.split(separator: " ").first else { return false }
    return Self.releaseSentenceBodyVerbs.contains(Self.normalizedToken(firstWord))
  }

  private static func capitalizingFirstLetter(_ text: String) -> String {
    guard let first = text.first else { return text }
    return first.uppercased() + text.dropFirst()
  }

  static func normalizedPlainText(_ text: String) -> String {
    var result = Self.removingMarkdownFrontMatter(from: text)
    result = Self.removingMDXScaffolding(from: result)
    result = result.replacingOccurrences(
      of: #"(?i)(\s·\s*Changelog)\s+"#, with: "$1\n", options: .regularExpression)
    result = result.replacingOccurrences(
      of: #"(?i)(^|\s)(v?\d+(?:\.\d+){1,}\s+[A-Z][a-z]+\s+\d{1,2},\s+\d{4})\s+(?!·)"#,
      with: "$1$2\n", options: .regularExpression)
    result = result.replacingOccurrences(
      of: #"(\S)\s+(?=v?\d+(?:\.\d+){1,}\s+[A-Z][a-z]+\s+\d{1,2},\s+\d{4}\b)"#, with: "$1\n",
      options: [.regularExpression, .caseInsensitive])

    let lines = result.components(separatedBy: .newlines).map {
      Self.splittingRepeatedHeadingPrefix(in: $0)
    }
    return lines.joined(separator: "\n")
  }

  private static func removingMarkdownFrontMatter(from text: String) -> String {
    let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
    if let compactRange = normalizedText.range(
      of: #"(?s)\A---\s+.*?\s+---\s*"#, options: .regularExpression)
    {
      return String(normalizedText[compactRange.upperBound...]).trimmingCharacters(
        in: .whitespacesAndNewlines)
    }

    let lines = normalizedText.components(separatedBy: "\n")
    let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if firstLine == "---" {
      for index in lines.indices.dropFirst() {
        if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
          return lines.dropFirst(index + 1).joined(separator: "\n").trimmingCharacters(
            in: .whitespacesAndNewlines)
        }
      }

      return text
    }

    if firstLine?.hasPrefix("title:") == true || firstLine?.hasPrefix("description:") == true {
      for index in lines.indices {
        if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
          return lines.dropFirst(index + 1).joined(separator: "\n").trimmingCharacters(
            in: .whitespacesAndNewlines)
        }
      }
    }

    return text
  }

  private static func removingMDXScaffolding(from text: String) -> String {
    let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
      let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedLine.range(
        of: #"^(import|export)\s+"#, options: [.regularExpression, .caseInsensitive]) != nil
      {
        return nil
      }
      if trimmedLine.range(
        of: #"^</?[A-Z][A-Za-z0-9]*(?:\s+[^>]*)?/?>$"#, options: .regularExpression) != nil
      {
        return nil
      }
      return line
    }
    return lines.joined(separator: "\n")
  }

  static func cleaningInlineMarkdown(in text: String) -> String {
    var result = text
    result = result.replacingOccurrences(
      of: #"\!\[([^\]]*)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
    result = result.replacingOccurrences(
      of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
    result = result.replacingOccurrences(
      of: #"`([^`\n]+)`"#, with: "$1", options: .regularExpression)
    result = result.replacingOccurrences(
      of: #"(?s)\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
    result = result.replacingOccurrences(
      of: #"(?s)__([^_]+)__"#, with: "$1", options: .regularExpression)
    result = result.replacingOccurrences(of: "**", with: "")
    result = result.replacingOccurrences(of: "__", with: "")
    return result
  }

  private static func splittingRepeatedHeadingPrefix(in line: String) -> String {
    let tokens = line.split(separator: " ")
    guard tokens.count >= 6 else { return line }

    for headingLength in 2...min(8, tokens.count - 3) {
      let repeatedTokenIndex = headingLength
      guard Self.normalizedToken(tokens[0]) == Self.normalizedToken(tokens[repeatedTokenIndex]),
        Self.looksLikeBodyStart(tokens[repeatedTokenIndex...])
      else {
        continue
      }

      let heading = tokens[..<headingLength].joined(separator: " ")
      let body = tokens[repeatedTokenIndex...].joined(separator: " ")
      return heading + "\n" + body
    }

    return line
  }

  private static func normalizedToken(_ token: Substring) -> String {
    token.trimmingCharacters(in: .punctuationCharacters).lowercased()
  }

  private static func looksLikeBodyStart(_ tokens: ArraySlice<Substring>) -> Bool {
    guard tokens.count >= 2 else { return false }

    return Self.repeatedHeadingBodyVerbs.contains(
      Self.normalizedToken(tokens[tokens.index(after: tokens.startIndex)]))
  }
}
