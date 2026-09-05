import Foundation
import AppKit

extension ReleaseNotesMarkup {
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

	static func isReactServerReference(_ text: String) -> Bool {
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

	static func nextHTMLElement(in html: String, tagName: String, searchStart: String.Index) -> (range: Range<String.Index>, contentRange: Range<String.Index>)? {
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

	static func reactServerText(for reference: String, in html: String) -> String? {
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
}
