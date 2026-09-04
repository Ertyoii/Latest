//
//  ReleaseNotesSourceExtractors.swift
//  Latest
//
//  Structural split from the original implementation.
//

import AppKit
import Foundation

extension ReleaseNotesMarkup {
	static func zedReleaseText(fromHTML html: String, version: String?, pageURL: URL) -> String? {
		guard pageURL.host?.localizedCaseInsensitiveContains("zed.dev") == true,
			  let version = version?.trimmingCharacters(in: .whitespacesAndNewlines),
			  !version.isEmpty else {
			return nil
		}

		// Zed's version page currently contains both rendered article text and React
		// transport records. Prefer the rendered article: transport descriptions can
		// be references or partial payloads even when they decode successfully.
		if let articleHTML = Self.zedArticleBodyHTML(fromHTML: html, version: version),
		   let text = Self.plainText(fromHTML: articleHTML),
		   let cleanedText = Self.cleanedZedReleaseText(text),
		   Self.isUsefulZedReleaseArticleText(cleanedText) {
			return cleanedText
		}

		if let text = Self.plainText(fromHTML: html),
		   let releaseText = Self.zedReleaseText(fromPlainText: text, version: version),
		   let cleanedText = Self.cleanedZedReleaseText(releaseText),
		   Self.isUsefulReleaseNotesText(cleanedText, relevantVersion: version) {
			return cleanedText
		}

		let escapedVersion = NSRegularExpression.escapedPattern(for: version)
		let pattern = #"\\\"release\\\":\{\\\"version\\\":\\\""# + escapedVersion + #"\\\",\\\"description\\\":\\\"((?:\\\\.|[^\\\"])*)\\\""#
		if let regex = try? NSRegularExpression(pattern: pattern) {
			let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
			if let match = regex.firstMatch(in: html, range: htmlRange),
			   let descriptionRange = Range(match.range(at: 1), in: html) {
				let escapedDescription = String(html[descriptionRange])
				let jsonString = "\"\(escapedDescription)\""
				if let data = jsonString.data(using: .utf8),
				   let decodedDescription = try? JSONDecoder().decode(String.self, from: data) {
					let description = decodedDescription
						.replacingOccurrences(of: "\\r", with: "\r")
						.replacingOccurrences(of: "\\n", with: "\n")
						.trimmingCharacters(in: .whitespacesAndNewlines)

					if Self.isReactServerReference(description),
					   let referencedDescription = Self.reactServerText(for: description, in: html),
					   let cleanedText = Self.cleanedZedReleaseText(referencedDescription),
					   Self.isUsefulReleaseNotesText(cleanedText, relevantVersion: version) {
						return cleanedText
					}

					if !description.isEmpty, !Self.isReactServerReference(description) {
						return description
					}
				}
			}
		}

		return nil
	}

	static func zoomReleaseText(fromHTML html: String, version: String?, pageURL: URL) -> String? {
		guard pageURL.host?.localizedCaseInsensitiveContains("zoom.com") == true,
			  let text = Self.plainText(fromHTML: Self.zoomTableAwareHTML(Self.zoomArticleBodyHTML(fromHTML: html) ?? html)) else {
			return nil
		}

		let normalizedText = text
			.replacingOccurrences(of: #"\\r\\n|\\n|\\r"#, with: "\n", options: .regularExpression)

		let lines = normalizedText.components(separatedBy: .newlines).compactMap { line -> String? in
			let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmedLine.isEmpty ? nil : trimmedLine
		}
		guard !lines.isEmpty else { return nil }

		let candidates = Self.versionCandidates(from: version)
		guard !candidates.isEmpty else { return nil }

		let versionIndexes = lines.indices.filter { index in
			let line = lines[index]
			return Self.lineContainsVersionCandidate(line, candidates: candidates)
		}

		for versionIndex in versionIndexes {
			let startIndex = lines[..<versionIndex].indices.reversed().first { index in
				Self.looksLikeDateReleaseBoundary(lines[index])
			} ?? versionIndex

			var endIndex = lines.endIndex
			for index in (startIndex + 1)..<lines.endIndex {
				if Self.looksLikeDateReleaseBoundary(lines[index]) {
					endIndex = index
					break
				}
			}

			let selectedLines = Array(lines[startIndex..<endIndex])
			let cleanedText = Self.cleanedZoomReleaseText(selectedLines)
			guard Self.looksLikeZoomReleaseBody(cleanedText),
			      Self.isUsefulReleaseNotesText(cleanedText, relevantVersion: version) else {
				continue
			}

			return Self.zoomReleaseTextWithVersionHeader(cleanedText, version: version)
		}

		return nil
	}

	static func usesSourceSpecificTextExtraction(for url: URL) -> Bool {
		guard let host = url.host?.lowercased() else { return false }
		return host.contains("chromereleases.googleblog.com") ||
			host.contains("navicat.com") ||
			host.contains("zed.dev") ||
			host.contains("zoom.com")
	}

	static func relevantChangelogText(fromHTML html: String, version: String?, pageURL: URL, allowFirstSectionFallback: Bool) -> String? {
		if let relevantText = Self.navicatMacReleaseText(fromHTML: html, version: version, pageURL: pageURL) {
			return relevantText
		}

		if let relevantText = Self.zedReleaseText(fromHTML: html, version: version, pageURL: pageURL) {
			return relevantText
		}

		if let relevantText = Self.zoomReleaseText(fromHTML: html, version: version, pageURL: pageURL) {
			return relevantText
		}

		if let relevantText = Self.chromeDesktopReleaseText(fromHTML: html, version: version, pageURL: pageURL) {
			return relevantText
		}
		if pageURL.host?.localizedCaseInsensitiveContains("chromereleases.googleblog.com") == true {
			return nil
		}

		let preferredSuffix = pageURL.host?.localizedCaseInsensitiveContains("obsidian.md") == true ? "Desktop" : nil
		guard let text = Self.plainText(fromHTML: html),
			  let relevantText = Self.relevantText(from: text, version: version, allowFirstSectionFallback: allowFirstSectionFallback, preferredSuffix: preferredSuffix),
			  Self.isUsefulReleaseNotesText(relevantText, relevantVersion: version) else {
			return nil
		}

		return relevantText
	}

	static func navicatMacReleaseText(fromHTML html: String, version: String?, pageURL: URL) -> String? {
		guard pageURL.host?.localizedCaseInsensitiveContains("navicat.com") == true,
			  let text = Self.plainText(fromHTML: html) else {
			return nil
		}

		let candidates = Self.versionCandidates(from: version)
		guard !candidates.isEmpty else { return nil }
		let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
			let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmedLine.isEmpty ? nil : trimmedLine
		}

		guard let startIndex = lines.firstIndex(where: { line in
			line.localizedCaseInsensitiveContains("(macOS)") &&
				line.localizedCaseInsensitiveContains("version") &&
				candidates.contains(where: { line.localizedCaseInsensitiveContains($0) })
		}) else {
			return nil
		}

		var endIndex = lines.endIndex
		for index in (startIndex + 1)..<lines.endIndex {
			let line = lines[index]
			let isPlatformReleaseHeading = line.localizedCaseInsensitiveContains("version") &&
				(line.localizedCaseInsensitiveContains("(Windows)") ||
				 line.localizedCaseInsensitiveContains("(macOS)") ||
				 line.localizedCaseInsensitiveContains("(Linux)"))
			if isPlatformReleaseHeading {
				endIndex = index
				break
			}
		}

		let releaseText = lines[startIndex..<endIndex].joined(separator: "\n")
		guard Self.isUsefulReleaseNotesText(releaseText, relevantVersion: version) else {
			return nil
		}

		return releaseText
	}

	static func chromeDesktopReleaseText(fromHTML html: String, version: String?, pageURL: URL) -> String? {
		guard pageURL.host?.localizedCaseInsensitiveContains("chromereleases.googleblog.com") == true else {
			return nil
		}

		let candidates = Self.versionCandidates(from: version)
		if let releaseText = Self.chromeDesktopReleaseTextFromBloggerTemplate(html, version: version, candidates: candidates) {
			return releaseText
		}

		guard let text = Self.plainText(fromHTML: html) else { return nil }
		return Self.chromeDesktopReleaseText(fromPlainText: text, version: version, candidates: candidates)
	}

	private static func chromeDesktopReleaseTextFromBloggerTemplate(_ html: String, version: String?, candidates: [String]) -> String? {
		var searchStart = html.startIndex
		while let titleRange = html.range(of: "Stable Channel Update for Desktop", options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<html.endIndex) {
			let postStart = html[..<titleRange.lowerBound].range(of: "<div class='post'", options: [.backwards, .caseInsensitive])?.lowerBound ?? titleRange.lowerBound
			let postEnd = html.range(of: "<div class='post'", options: [.caseInsensitive], range: titleRange.upperBound..<html.endIndex)?.lowerBound ?? html.endIndex
			let postHTML = String(html[postStart..<postEnd])

			if let bodyMarkup = Self.chromeBloggerBodyMarkup(in: postHTML),
			   let bodyText = Self.plainText(fromHTML: bodyMarkup) {
				let releaseText = "Stable Channel Update for Desktop\n" + bodyText
				if Self.chromeReleaseTextMatches(releaseText, version: version, candidates: candidates),
				   Self.isUsefulReleaseNotesText(releaseText, relevantVersion: nil) {
					return releaseText
				}
			}

			searchStart = titleRange.upperBound
		}

		return nil
	}

	private static func chromeBloggerBodyMarkup(in html: String) -> String? {
		var searchStart = html.startIndex
		while let element = Self.nextHTMLElement(in: html, tagName: "script", searchStart: searchStart) {
			let openingTag = String(html[element.range.lowerBound..<element.contentRange.lowerBound])
			if openingTag.range(of: #"type\s*=\s*['"]text/template['"]"#, options: [.regularExpression, .caseInsensitive]) != nil {
				return String(html[element.contentRange])
			}

			searchStart = element.range.upperBound
		}

		if let element = Self.nextHTMLElement(in: html, tagName: "noscript", searchStart: html.startIndex) {
			return String(html[element.contentRange])
		}

		return nil
	}

	private static func chromeDesktopReleaseText(fromPlainText text: String, version: String?, candidates: [String]) -> String? {
		let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
			let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmedLine.isEmpty ? nil : trimmedLine
		}
		guard !lines.isEmpty, !candidates.isEmpty else { return nil }

		guard let versionLineIndex = lines.firstIndex(where: { line in
			Self.chromeReleaseLineMatches(line, version: version, candidates: candidates)
		}) else {
			return nil
		}

		let startIndex = lines[..<versionLineIndex].indices.reversed().first { index in
			let line = lines[index]
			return line.localizedCaseInsensitiveContains("Desktop") &&
				line.localizedCaseInsensitiveContains("Update")
		} ?? versionLineIndex

		var endIndex = lines.endIndex
		if versionLineIndex + 1 < lines.endIndex {
			for index in (versionLineIndex + 1)..<lines.endIndex {
				let line = lines[index]
				if index > startIndex,
				   line.localizedCaseInsensitiveContains("Update"),
				   Self.looksLikeChromeReleaseHeading(line),
				   !Self.lineMatchesChromeVersion(line, version: version, candidates: candidates) {
					endIndex = index
					break
				}
			}
		}

		let releaseText = lines[startIndex..<endIndex].joined(separator: "\n")
		guard Self.isUsefulReleaseNotesText(releaseText, relevantVersion: nil) else {
			return nil
		}

		return releaseText
	}

	private static func zedReleaseText(fromPlainText text: String, version: String) -> String? {
		let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
			let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmedLine.isEmpty ? nil : trimmedLine
		}
		guard !lines.isEmpty else { return nil }

		let candidates = Self.versionCandidates(from: version)
		guard let startIndex = lines.indices.first(where: { index in
			guard Self.isBareVersionLine(lines[index]),
				  Self.lineContainsVersionCandidate(lines[index], candidates: candidates),
				  lines.indices.contains(index + 1) else {
				return false
			}

			return Self.looksLikeDateReleaseBoundary(lines[index + 1])
		}) else {
			return nil
		}

		var endIndex = lines.endIndex
		for index in (startIndex + 1)..<lines.endIndex {
			if index != startIndex,
			   Self.looksLikeVersionBoundary(lines[index]),
			   !Self.lineContainsVersionCandidate(lines[index], candidates: candidates) {
				endIndex = index
				break
			}
		}

		return lines[startIndex..<endIndex].joined(separator: "\n")
	}

	private static func chromeReleaseTextMatches(_ text: String, version: String?, candidates: [String]) -> Bool {
		text.components(separatedBy: .newlines).contains { line in
			Self.chromeReleaseLineMatches(line, version: version, candidates: candidates)
		}
	}

	private static func chromeReleaseLineMatches(_ line: String, version: String?, candidates: [String]) -> Bool {
		let lowercased = line.lowercased()
		return lowercased.contains("windows") &&
			lowercased.contains("mac") &&
			!lowercased.contains("android releases contain") &&
			Self.lineMatchesChromeVersion(line, version: version, candidates: candidates)
	}

	private static func lineMatchesChromeVersion(_ line: String, version: String?, candidates: [String]) -> Bool {
		let preciseCandidates = candidates.filter { candidate in
			candidate.split(separator: ".", omittingEmptySubsequences: false).count >= 4
		}
		if preciseCandidates.contains(where: { candidate in
			line.range(of: candidate, options: [.caseInsensitive, .diacriticInsensitive]) != nil
		}) {
			return true
		}

		guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty else {
			return false
		}

		let parts = version.split(separator: ".", omittingEmptySubsequences: false)
		guard parts.count >= 4 else { return false }

		let prefix = parts.dropLast().joined(separator: ".")
		let suffix = String(parts.last ?? "")
		guard !prefix.isEmpty, !suffix.isEmpty else { return false }

		let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
		let escapedSuffix = NSRegularExpression.escapedPattern(for: suffix)
		return line.range(
			of: #"\b\#(escapedPrefix)\.\d+/\.?\#(escapedSuffix)\b"#,
			options: [.regularExpression, .caseInsensitive]
		) != nil
	}

	private static func looksLikeChromeReleaseHeading(_ line: String) -> Bool {
		let lowercased = line.lowercased()
		return lowercased.contains("desktop") ||
			lowercased.contains("chromeos") ||
			lowercased.hasPrefix("chrome for ") ||
			lowercased.hasPrefix("beta channel") ||
			lowercased.hasPrefix("dev channel")
	}

	static func releaseContentHTML(fromHTML html: String, version: String?, pageURL: URL) -> String? {
		let isObsidianChangelog = pageURL.host?.localizedCaseInsensitiveContains("obsidian.md") == true
		if isObsidianChangelog,
		   let article = Self.versionedReleaseArticleHTML(fromHTML: html, version: version, preferredSuffix: "Desktop"),
		   Self.isUsefulReleaseNotesText(article, relevantVersion: version) {
			return article
		}

		if let article = Self.versionedReleaseArticleHTML(fromHTML: html, version: version),
		   Self.isUsefulReleaseNotesText(article, relevantVersion: version) {
			return article
		}

		if isObsidianChangelog,
		   !Self.isObsidianChangelogIndex(pageURL),
		   let content = Self.firstHTMLBlock(in: html, tagName: "div", marker: #"class="typeset"#),
		   Self.isUsefulReleaseNotesText(content, relevantVersion: version) {
			return content
		}

		return nil
	}

	static func plainText(fromHTML html: String) -> String? {
		var text = html

		text = replacingMatches(in: text, matching: Regexes.omittedElements, with: "\n")
		text = replacingMatches(in: text, matching: Regexes.lineBreak, with: "\n")
		text = replacingMatches(in: text, matching: Regexes.listItem, with: "\n- ")
		text = replacingMatches(in: text, matching: Regexes.blockOpening, with: "\n")
		text = replacingMatches(in: text, matching: Regexes.blockClosing, with: "\n")
		text = replacingMatches(in: text, matching: Regexes.anyTag, with: " ")
		text = Self.decodingHTMLEntities(in: text)
		text = text.replacingOccurrences(of: "\u{00a0}", with: " ")

		let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
			let trimmedLine = replacingMatches(
				in: line.trimmingCharacters(in: .whitespacesAndNewlines),
				matching: Regexes.repeatedWhitespace,
				with: " "
			)
			return trimmedLine.isEmpty ? nil : trimmedLine
		}

		return lines.isEmpty ? nil : lines.joined(separator: "\n")
	}

	static func firstReleaseNotesURL(in markup: String, baseURL: URL?) -> URL? {
		if let hrefURL = Self.firstHrefURL(in: markup, baseURL: baseURL) {
			return hrefURL
		}

		let range = NSRange(markup.startIndex..<markup.endIndex, in: markup)
		guard let match = Regexes.firstRawURL.firstMatch(in: markup, range: range),
			  let matchRange = Range(match.range, in: markup) else {
			return nil
		}

		let urlString = String(markup[matchRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)"))
		return URL(string: urlString)
	}

	static func linkedChangelogURL(fromHTML html: String, version: String?, pageURL: URL) -> URL? {
		let candidates = versionCandidates(from: version)
		guard !candidates.isEmpty else { return nil }

		let range = NSRange(html.startIndex..<html.endIndex, in: html)
		let matches = Regexes.anchorWithLabel.matches(in: html, range: range)
		var fallbackURL: URL?
		var preferredURL: URL?

		for match in matches {
			guard let hrefRange = Range(match.range(at: 1), in: html),
				  let labelRange = Range(match.range(at: 2), in: html) else {
				continue
			}

			let href = Self.decodingHTMLEntities(in: String(html[hrefRange]))
			let labelHTML = String(html[labelRange])
			let label = Self.plainText(fromHTML: labelHTML) ?? labelHTML
			let searchText = href + "\n" + label
			guard candidates.contains(where: { candidate in
				searchText.range(of: candidate, options: [.caseInsensitive, .diacriticInsensitive]) != nil
			}) else {
				continue
			}

			guard let url = URL(string: href, relativeTo: pageURL)?.absoluteURL else {
				continue
			}

			if fallbackURL == nil {
				fallbackURL = url
			}

			if searchText.range(of: "desktop", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
				preferredURL = url
				break
			}
		}

		return preferredURL ?? fallbackURL
	}

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
			  !Self.looksLikeWebPageChrome(displayText) else {
			return false
		}

		var informationText = displayText
		informationText = replacingMatches(in: informationText, matching: Regexes.rawURL, with: " ")
		informationText = replacingMatches(in: informationText, matching: Regexes.markdownLink, with: " ")
		informationText = replacingMatches(in: informationText, matching: Regexes.versionNumber, with: " ")
		if let relevantVersion, !relevantVersion.isEmpty {
			informationText = informationText.replacingOccurrences(of: relevantVersion, with: " ", options: [.caseInsensitive])
		}
		informationText = replacingMatches(in: informationText, matching: Regexes.namedDate, with: " ")
		informationText = replacingMatches(in: informationText, matching: Regexes.isoDate, with: " ")

		let lowercasedInformationText = informationText.lowercased()
		let words = lowercasedInformationText.matches(of: /[a-z][a-z0-9+-]{1,}/).map { String(lowercasedInformationText[$0.range]) }
		let meaningfulWords = words.filter { !Self.genericReleaseNoteWords.contains($0) }

		return meaningfulWords.count >= 2 || meaningfulWords.joined().count >= 14
	}

	static func relevantText(from text: String, version: String?, allowFirstSectionFallback: Bool, preferredSuffix: String? = nil) -> String? {
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
						  !requiresBoundary || Self.looksLikeVersionBoundary(line) else { continue }

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
				startIndex = matchingVersionIndex(requiresBoundary: true, matchers: preferredMatchers) ??
					matchingVersionIndex(requiresBoundary: false, matchers: preferredMatchers)
			}

			startIndex = startIndex ??
				matchingVersionIndex(requiresBoundary: true, matchers: standardMatchers) ??
				matchingVersionIndex(requiresBoundary: false, matchers: standardMatchers)
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
			let isImmediateDateAfterBareVersion = startsWithBareVersionLine &&
				index == startIndex + 1 &&
				Self.looksLikeDateReleaseBoundary(line)
			let isBoundary = if shouldEndAtVersionBoundary {
				Self.looksLikeVersionBoundary(line) ||
				(Self.looksLikeDateReleaseBoundary(line) && !isImmediateDateAfterBareVersion)
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

	static func normalizedReleaseLine(_ line: String) -> String {
		var normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
		normalized = normalized.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
		normalized = normalized.replacingOccurrences(of: #"^(\*|-|•)\s+"#, with: "", options: .regularExpression)
		normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
		return normalized.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)).lowercased()
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
			if (scalar.value < 32 || scalar.value == 127) && scalar.value != 10 && scalar.value != 9 && scalar.value != 13 {
				containsControlCharacter = true
			}
			if (0x4E00...0x9FFF).contains(scalarValue) ||
				(0x3040...0x30FF).contains(scalarValue) ||
				(0xAC00...0xD7AF).contains(scalarValue) {
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

		return (latin1Ratio > 0.22 && asciiWordCount < 8) || (nonASCIIRatio > 0.55 && asciiWordCount < 4)
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
		   let bodyWithoutRepeatedTitle = Self.bodyLineWithoutRepeatedTitle(lines[1], releaseTitle: releaseTitle) {
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

	private static func bodyLineWithoutRepeatedTitle(_ line: String, releaseTitle: String) -> String? {
		let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let range = trimmedLine.range(of: releaseTitle, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) else {
			return nil
		}

		let suffix = trimmedLine[range.upperBound...]
		guard suffix.first.map({ $0.isWhitespace || "-–—:".contains($0) }) ?? false else {
			return nil
		}

		let remainder = suffix
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
		result = result.replacingOccurrences(of: #"(?i)(\s·\s*Changelog)\s+"#, with: "$1\n", options: .regularExpression)
		result = result.replacingOccurrences(of: #"(?i)(^|\s)(v?\d+(?:\.\d+){1,}\s+[A-Z][a-z]+\s+\d{1,2},\s+\d{4})\s+(?!·)"#, with: "$1$2\n", options: .regularExpression)
		result = result.replacingOccurrences(of: #"(\S)\s+(?=v?\d+(?:\.\d+){1,}\s+[A-Z][a-z]+\s+\d{1,2},\s+\d{4}\b)"#, with: "$1\n", options: [.regularExpression, .caseInsensitive])

		let lines = result.components(separatedBy: .newlines).map { Self.splittingRepeatedHeadingPrefix(in: $0) }
		return lines.joined(separator: "\n")
	}

	private static func removingMarkdownFrontMatter(from text: String) -> String {
		let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
		if let compactRange = normalizedText.range(of: #"(?s)\A---\s+.*?\s+---\s*"#, options: .regularExpression) {
			return String(normalizedText[compactRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
		}

		let lines = normalizedText.components(separatedBy: "\n")
		let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		if firstLine == "---" {
			for index in lines.indices.dropFirst() {
				if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
					return lines.dropFirst(index + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
				}
			}

			return text
		}

		if firstLine?.hasPrefix("title:") == true || firstLine?.hasPrefix("description:") == true {
			for index in lines.indices {
				if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
					return lines.dropFirst(index + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
				}
			}
		}

		return text
	}

	private static func removingMDXScaffolding(from text: String) -> String {
		let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
			let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
			if trimmedLine.range(of: #"^(import|export)\s+"#, options: [.regularExpression, .caseInsensitive]) != nil {
				return nil
			}
			if trimmedLine.range(of: #"^</?[A-Z][A-Za-z0-9]*(?:\s+[^>]*)?/?>$"#, options: .regularExpression) != nil {
				return nil
			}
			return line
		}
		return lines.joined(separator: "\n")
	}

	static func cleaningInlineMarkdown(in text: String) -> String {
		var result = text
		result = result.replacingOccurrences(of: #"\!\[([^\]]*)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
		result = result.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
		result = result.replacingOccurrences(of: #"`([^`\n]+)`"#, with: "$1", options: .regularExpression)
		result = result.replacingOccurrences(of: #"(?s)\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
		result = result.replacingOccurrences(of: #"(?s)__([^_]+)__"#, with: "$1", options: .regularExpression)
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
				  Self.looksLikeBodyStart(tokens[repeatedTokenIndex...]) else {
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

		return Self.repeatedHeadingBodyVerbs.contains(Self.normalizedToken(tokens[tokens.index(after: tokens.startIndex)]))
	}

	private static func cleanedZedReleaseText(_ text: String) -> String? {
		let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
			let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmedLine.isEmpty,
				  !["-", "–", "—"].contains(trimmedLine),
				  !Self.zedReleaseChromeLines.contains(trimmedLine.lowercased()) else {
				return nil
			}

			return trimmedLine
		}

		let cleanedText = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
		return cleanedText.isEmpty ? nil : cleanedText
	}

	private static func zedArticleBodyHTML(fromHTML html: String, version: String) -> String? {
		let identifiers = ["id=\"zed-\(version)\"", "id='zed-\(version)'"]
		guard let cardIdentifier = identifiers.compactMap({ identifier in
			html.range(of: identifier, options: [.caseInsensitive, .diacriticInsensitive])
		}).min(by: { $0.lowerBound < $1.lowerBound }),
		      let articleTag = html.range(
			of: "<article",
			options: [.caseInsensitive, .diacriticInsensitive],
			range: cardIdentifier.upperBound..<html.endIndex
		),
		      let articleBodyStart = html.range(of: ">", range: articleTag.upperBound..<html.endIndex)?.upperBound,
		      let articleBodyEnd = html.range(
			of: "</article>",
			options: [.caseInsensitive, .diacriticInsensitive],
			range: articleBodyStart..<html.endIndex
		)?.lowerBound else {
			return nil
		}
		return String(html[articleBodyStart..<articleBodyEnd])
	}

	static func isUsefulZedReleaseArticleText(_ text: String) -> Bool {
		guard text.count >= 80,
		      !Self.looksLikeBinaryOrMojibakeText(text) else {
			return false
		}
		return text.range(
			of: #"(?m)^(This week's release|Features|Bug Fixes|Shipped by the Zed Guild)\b"#,
			options: [.regularExpression, .caseInsensitive]
		) != nil
	}

	private static func zoomTableAwareHTML(_ html: String) -> String {
		html
			.replacingOccurrences(
				of: #"(?is)</(?:td|th)>\s*<(?:td|th)\b[^>]*>"#,
				with: "<br />",
				options: .regularExpression
			)
			.replacingOccurrences(
				of: #"(?is)</tr>\s*<tr\b[^>]*>"#,
				with: "<br />",
				options: .regularExpression
			)
	}

	private static func cleanedZoomReleaseText(_ lines: [String]) -> String {
		var normalizedLines = [String]()
		var skippingFullVersions = false

		for line in lines {
			let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmedLine.isEmpty else { continue }

			if trimmedLine.localizedCaseInsensitiveCompare("Full versions") == .orderedSame {
				skippingFullVersions = true
				continue
			}

			if skippingFullVersions {
				if Self.looksLikeZoomReleaseNotesSectionStart(trimmedLine) {
					skippingFullVersions = false
				} else {
					continue
				}
			}

			if trimmedLine.localizedCaseInsensitiveCompare("Type Feature title Description Platforms") == .orderedSame {
				continue
			}

			normalizedLines.append(trimmedLine)
		}

		var cleanedLines = [String]()
		var index = normalizedLines.startIndex
		while index < normalizedLines.endIndex {
			let line = normalizedLines[index]
			guard Self.looksLikeZoomFeatureRowStart(line) else {
				if !Self.isZoomPlatformOnlyLine(line) {
					cleanedLines.append(line)
				}
				index += 1
				continue
			}

			var endIndex = index + 1
			while endIndex < normalizedLines.endIndex,
			      !Self.looksLikeZoomFeatureRowStart(normalizedLines[endIndex]),
			      !Self.looksLikeZoomReleaseNotesSectionStart(normalizedLines[endIndex]) {
				endIndex += 1
			}

			let block = Array(normalizedLines[index..<endIndex])
			let declaredPlatforms = block.dropFirst().flatMap { Self.zoomPlatformsIfOnlyLine($0) ?? [] }
			if declaredPlatforms.isEmpty || declaredPlatforms.contains("macos") {
				cleanedLines.append(contentsOf: block.filter { Self.zoomPlatformsIfOnlyLine($0) == nil })
			}
			index = endIndex
		}

		return cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func zoomArticleBodyHTML(fromHTML html: String) -> String? {
		let pattern = #"(?is)<script\b[^>]*\btype\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
		guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

		let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
		let decoder = JSONDecoder()
		for match in matches {
			guard let scriptRange = Range(match.range(at: 1), in: html) else { continue }

			let json = String(html[scriptRange])
			guard let data = json.data(using: .utf8) else { continue }

			if let article = try? decoder.decode(StructuredArticle.self, from: data),
			   let articleBody = article.articleBody?.trimmingCharacters(in: .whitespacesAndNewlines),
			   !articleBody.isEmpty {
				return articleBody
			}

			if let articles = try? decoder.decode([StructuredArticle].self, from: data),
			   let articleBody = articles.compactMap(\.articleBody).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
				return articleBody
			}
		}

		return nil
	}

	private static func looksLikeZoomReleaseBody(_ text: String) -> Bool {
		text.range(of: #"(?m)^(New, enhanced, and changed features|Resolved issues|Changed features|Security enhancements)\b"#, options: [.regularExpression, .caseInsensitive]) != nil ||
		text.range(of: #"Show or hide icon labels|New or enhanced feature|Resolved an issue"#, options: [.regularExpression, .caseInsensitive]) != nil
	}

	private static func zoomReleaseTextWithVersionHeader(_ text: String, version: String?) -> String {
		guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines),
		      !version.isEmpty,
		      text.range(of: version, options: [.caseInsensitive, .diacriticInsensitive]) == nil else {
			return text
		}

		return "Zoom \(version)\n\(text)"
	}

	private static func looksLikeZoomReleaseNotesSectionStart(_ line: String) -> Bool {
		line.range(of: #"^(New, enhanced, and changed features|Resolved issues|Changed features|Security enhancements)"#, options: [.regularExpression, .caseInsensitive]) != nil
	}

	private static func looksLikeZoomFeatureRowStart(_ line: String) -> Bool {
		line.range(
			of: #"^(New or enhanced feature|Changed feature|Resolved issue|Security enhancement)\b"#,
			options: [.regularExpression, .caseInsensitive]
		) != nil
	}

	private static func isZoomPlatformOnlyLine(_ line: String) -> Bool {
		Self.zoomPlatformsIfOnlyLine(line) != nil
	}

	private static func zoomPlatformsIfOnlyLine(_ line: String) -> [String]? {
		var remainder = line.lowercased()
		let platformPatterns: [(pattern: String, value: String)] = [
			(#"\bmacos\b"#, "macos"),
			(#"\bwindows\b"#, "windows"),
			(#"\blinux\b"#, "linux"),
			(#"\bandroid(?:\s*\(intune\))?"#, "android"),
			(#"\bios(?:\s*\(intune\))?"#, "ios"),
			(#"\bvisionos\b"#, "visionos")
		]
		var platforms = [String]()
		for platform in platformPatterns {
			if remainder.range(of: platform.pattern, options: .regularExpression) != nil {
				platforms.append(platform.value)
				remainder = remainder.replacingOccurrences(
					of: platform.pattern,
					with: " ",
					options: .regularExpression
				)
			}
		}
		remainder = remainder.replacingOccurrences(of: #"[\s,/*|&+()-]+"#, with: "", options: .regularExpression)
		return !platforms.isEmpty && remainder.isEmpty ? platforms : nil
	}

	private static func lineContainsVersionCandidate(_ line: String, candidates: [String]) -> Bool {
		candidates.contains { candidate in
			let escapedCandidate = NSRegularExpression.escapedPattern(for: candidate)
			return line.range(of: #"(^|[^\d])v?\#(escapedCandidate)([^\d]|\z)"#, options: [.regularExpression, .caseInsensitive]) != nil
		}
	}

	private static func isReactServerReference(_ text: String) -> Bool {
		text.range(of: #"^\$[0-9A-Za-z]+$"#, options: .regularExpression) != nil
	}

	private static func isObsidianChangelogIndex(_ url: URL) -> Bool {
		let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		return path == "changelog"
	}

	private static func versionedReleaseArticleHTML(fromHTML html: String, version: String?, preferredSuffix: String? = nil) -> String? {
		let candidates = Self.versionCandidates(from: version)
		guard !candidates.isEmpty else { return nil }

		var searchStart = html.startIndex
		var fallbackArticleHTML: String?
		while let article = Self.nextHTMLElement(in: html, tagName: "article", searchStart: searchStart) {
			let articleHTML = String(html[article.range])
			let articleText = Self.plainText(fromHTML: articleHTML) ?? articleHTML
			if candidates.contains(where: { candidate in
				articleText.range(of: candidate, options: [.caseInsensitive, .diacriticInsensitive]) != nil
			}) {
				if let preferredSuffix {
					if candidates.contains(where: { candidate in
						articleText.range(of: "\(candidate) \(preferredSuffix)", options: [.caseInsensitive, .diacriticInsensitive]) != nil
					}) {
						return articleHTML
					}
					if fallbackArticleHTML == nil {
						fallbackArticleHTML = articleHTML
					}
					searchStart = article.range.upperBound
					continue
				}

				return articleHTML
			}

			searchStart = article.range.upperBound
		}

		return fallbackArticleHTML
	}

	private static func firstHTMLBlock(in html: String, tagName: String, marker: String) -> String? {
		guard let markerRange = html.range(of: marker, options: .regularExpression),
		      let openingRange = html[..<markerRange.lowerBound].range(of: "<\(tagName)", options: [.backwards, .caseInsensitive]) else {
			return nil
		}

		return Self.nextHTMLElement(in: html, tagName: tagName, searchStart: openingRange.lowerBound).map { element in
			String(html[element.range])
		}
	}

	private static func nextHTMLElement(in html: String, tagName: String, searchStart: String.Index) -> (range: Range<String.Index>, contentRange: Range<String.Index>)? {
		let escapedTagName = NSRegularExpression.escapedPattern(for: tagName)
		guard let regex = try? NSRegularExpression(
			pattern: "(?is)</?\(escapedTagName)\\b[^>]*>"
		) else {
			return nil
		}
		let searchRange = NSRange(searchStart..<html.endIndex, in: html)
		let matches = regex.matches(in: html, range: searchRange)
		guard let firstMatch = matches.first,
		      let openingRange = Range(firstMatch.range, in: html),
		      !html[openingRange].hasPrefix("</") else {
			return nil
		}

		var depth = 0
		for match in matches {
			guard let tokenRange = Range(match.range, in: html) else { continue }
			let token = html[tokenRange]
			let isClosing = token.hasPrefix("</")
			let isSelfClosing = token.dropLast().last == "/"
			if isClosing {
				depth -= 1
				if depth == 0 {
					return (
						range: openingRange.lowerBound..<tokenRange.upperBound,
						contentRange: openingRange.upperBound..<tokenRange.lowerBound
					)
				}
			} else if !isSelfClosing {
				depth += 1
			}
		}

		return nil
	}

	private static func reactServerText(for reference: String, in html: String) -> String? {
		let identifier = String(reference.dropFirst())
		guard !identifier.isEmpty else { return nil }

		let markerPattern = NSRegularExpression.escapedPattern(for: identifier) + #":T[0-9A-Fa-f]+,"#
		guard let markerRange = html.range(of: markerPattern, options: .regularExpression) else {
			return nil
		}

		let remainingHTML = String(html[markerRange.upperBound...])
		let textPattern = #"(?s)self\.__next_f\.push\(\[1,"((?:\\.|[^"\\])*)"\]\)</script>"#
		guard let regex = try? NSRegularExpression(pattern: textPattern),
			  let match = regex.firstMatch(in: remainingHTML, range: NSRange(remainingHTML.startIndex..<remainingHTML.endIndex, in: remainingHTML)),
			  let textRange = Range(match.range(at: 1), in: remainingHTML) else {
			return nil
		}

		let escapedText = String(remainingHTML[textRange])
		let jsonString = "\"\(escapedText)\""
		guard let data = jsonString.data(using: .utf8),
			  let decodedText = try? JSONDecoder().decode(String.self, from: data) else {
			return nil
		}

		return decodedText.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func firstHrefURL(in html: String, baseURL: URL?) -> URL? {
		let range = NSRange(html.startIndex..<html.endIndex, in: html)
		guard let match = Regexes.anchorHref.firstMatch(in: html, range: range),
			  let hrefRange = Range(match.range(at: 1), in: html) else {
			return nil
		}

		let href = Self.decodingHTMLEntities(in: String(html[hrefRange]))
		return URL(string: href, relativeTo: baseURL)?.absoluteURL
	}

	private static func decodingHTMLEntities(in string: String) -> String {
		var result = string
		let replacements = [
			"&nbsp;": " ",
			"&amp;": "&",
			"&lt;": "<",
			"&gt;": ">",
			"&quot;": "\"",
			"&#39;": "'",
			"&apos;": "'"
		]

		for (entity, replacement) in replacements {
			result = result.replacingOccurrences(of: entity, with: replacement)
		}

		let matches = Regexes.numericEntity.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
		for match in matches.reversed() {
			guard let matchRange = Range(match.range(at: 0), in: result),
				  let valueRange = Range(match.range(at: 1), in: result) else {
				continue
			}

			let rawValue = String(result[valueRange])
			let scalarValue: UInt32?
			if rawValue.lowercased().hasPrefix("x") {
				scalarValue = UInt32(rawValue.dropFirst(), radix: 16)
			} else {
				scalarValue = UInt32(rawValue, radix: 10)
			}

			guard let scalarValue,
				  let scalar = UnicodeScalar(scalarValue) else {
				continue
			}

			result.replaceSubrange(matchRange, with: String(Character(scalar)))
		}

		return result
	}

	private static func versionCandidates(from version: String?) -> [String] {
		guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty else {
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
		Self.looksLikeVersionBoundary(line) ||
		Self.looksLikeDateReleaseBoundary(line)
	}

	private static func looksLikeDateReleaseBoundary(_ line: String) -> Bool {
		line.range(of: #"^[A-Z][a-z]+ \d{1,2}, \d{4}"#, options: .regularExpression) != nil
	}

	private static func looksLikeVersionBoundary(_ line: String) -> Bool {
		line.range(of: #"^#{1,6}\s*v?\d+(\.\d+){1,}"#, options: [.regularExpression, .caseInsensitive]) != nil ||
		line.range(of: #"^v?\d+(\.\d+){1,}(\s|$|-)"#, options: [.regularExpression, .caseInsensitive]) != nil ||
		line.range(of: #"^(?![-*•])\D{1,60}v?\d+(\.\d+){1,}(\s|$|-)"#, options: [.regularExpression, .caseInsensitive]) != nil
	}

	private static func looksLikeVersionNavigation(_ line: String, at index: Int, in lines: [String]) -> Bool {
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

		return index > lines.startIndex && Self.versionNavigationWords.contains(lines[index - 1].lowercased())
	}

	private static func looksLikeDenseVersionNavigation(_ line: String) -> Bool {
		let matches = line.matches(of: /\bv?\d+(?:\.\d+){1,}\b/)
		guard matches.count >= 4 else { return false }

		let words = line.matches(of: /[A-Za-z]{3,}/).map { String(line[$0.range]) }
		let meaningfulWords = words.filter { !Self.versionNavigationWords.contains($0.lowercased()) }

		return meaningfulWords.count <= 2
	}

	private static func isBareVersionLine(_ line: String) -> Bool {
		line.range(of: #"^v?\d+(\.\d+){1,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
	}

}
