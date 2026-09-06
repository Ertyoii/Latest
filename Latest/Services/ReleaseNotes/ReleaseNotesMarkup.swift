//
//  ReleaseNotesMarkup.swift
//  Latest
//
//  Structural split from the original implementation.
//

import AppKit
import Foundation
import OSLog

struct StructuredArticle: Decodable {
	let articleBody: String?
}

enum ReleaseNotesMarkup {
	private struct PreparedMarkup: Sendable {
		enum Kind: Sendable {
			case markdown
			case plainText
			case html
		}

		let string: String
		let kind: Kind
		let baseURL: URL?
	}

	enum Regexes {
		static let omittedElements = try! NSRegularExpression(pattern: #"(?is)<(script|style|noscript|svg)\b.*?</\1>"#)
		static let lineBreak = try! NSRegularExpression(pattern: #"(?i)<br\s*/?>"#)
		static let listItem = try! NSRegularExpression(pattern: #"(?i)<li\b[^>]*>"#)
		static let blockOpening = try! NSRegularExpression(pattern: #"(?i)<(p|div|h[1-6]|tr|section|article|header|footer|table|ul|ol|dl|dt|dd)\b[^>]*>"#)
		static let blockClosing = try! NSRegularExpression(pattern: #"(?i)</(p|div|li|h[1-6]|tr|section|article|header|footer|table|ul|ol|dl|dt|dd)>"#)
		static let anyTag = try! NSRegularExpression(pattern: #"<[^>]+>"#)
		static let repeatedWhitespace = try! NSRegularExpression(pattern: #"\s{2,}"#)
		static let rawURL = try! NSRegularExpression(pattern: #"https?://\S+"#)
		static let markdownLink = try! NSRegularExpression(pattern: #"\[[^\]]*\]\([^)]+\)"#)
		static let versionNumber = try! NSRegularExpression(pattern: #"\bv?\d+(?:\.\d+){1,}(?:\.\d+)?\b"#, options: .caseInsensitive)
		static let namedDate = try! NSRegularExpression(pattern: #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{4}\b"#, options: .caseInsensitive)
		static let isoDate = try! NSRegularExpression(pattern: #"\b\d{4}-\d{2}-\d{2}\b"#)
		static let firstRawURL = try! NSRegularExpression(pattern: #"https?://[^\s<>\"']+"#)
		static let anchorWithLabel = try! NSRegularExpression(pattern: #"(?is)<a\b[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#)
		static let anchorHref = try! NSRegularExpression(pattern: #"(?is)<a\b[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"']"#)
		static let numericEntity = try! NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#)
	}

	static func replacingMatches(
		in string: String,
		matching regex: NSRegularExpression,
		with replacement: String
	) -> String {
		regex.stringByReplacingMatches(
			in: string,
			range: NSRange(string.startIndex..<string.endIndex, in: string),
			withTemplate: replacement
		)
	}

	static let genericReleaseNoteWords: Set<String> = [
		"changelog", "changes", "details", "history", "latest", "link", "links",
		"more", "note", "notes", "public", "recent", "release", "releases",
		"version", "versions", "view", "whats", "what"
	]
	static let releaseSentenceBodyVerbs: Set<String> = [
		"adds", "allows", "applies", "brings", "changes", "fixes",
		"improves", "introduces", "lets", "makes", "resolves", "updates"
	]
	static let repeatedHeadingBodyVerbs: Set<String> = [
		"adds", "allows", "applies", "are", "brings", "can", "changes",
		"fixes", "has", "have", "improves", "introduces", "is", "lets",
		"makes", "now", "updates", "uses", "was", "were", "will"
	]
	static let versionNavigationWords: Set<String> = [
		"versions", "version", "channel", "stable", "preview", "releases"
	]
	static let zedReleaseChromeLines: Set<String> = [
		"linux", "loading...", "loading…", "macos", "windows"
	]
	static let webPageChromeReleaseTerms = [
		"release", "changelog", "change log", "fixed", "bug", "improved", "added", "security", "resolved"
	]

	static func attributedString(from markup: String, baseURL: URL?, relevantVersion: String? = nil) -> ReleaseNotesProvider.ReleaseNotes {
		let signpostID = releaseNotesSignposter.makeSignpostID()
		let interval = releaseNotesSignposter.beginInterval("Render Release Notes", id: signpostID)
		defer { releaseNotesSignposter.endInterval("Render Release Notes", interval) }
		guard let preparedMarkup = prepare(markup, baseURL: baseURL, relevantVersion: relevantVersion) else {
			return .failure(LatestError.releaseNotesUnavailable)
		}
		return render(preparedMarkup)
	}

	@MainActor
	static func attributedStringByPreparingOffMain(
		from markup: String,
		baseURL: URL?,
		relevantVersion: String?
	) async -> ReleaseNotesProvider.ReleaseNotes {
		let preparedMarkup = await prepareOffMain {
			prepare(markup, baseURL: baseURL, relevantVersion: relevantVersion)
		}
		guard let preparedMarkup else {
			return .failure(LatestError.releaseNotesUnavailable)
		}
		return render(preparedMarkup)
	}

	@MainActor
	static func githubAttributedStringByPreparingOffMain(
		from markup: String,
		title: String?,
		baseURL: URL?,
		relevantVersion: String?
	) async -> ReleaseNotesProvider.ReleaseNotes? {
		let preparedMarkup = await prepareOffMain {
			let relevantMarkup: String
			if markup.containsHTMLTag {
				relevantMarkup = markup
			} else {
				relevantMarkup = relevantText(
					from: markup,
					version: relevantVersion,
					allowFirstSectionFallback: true
				) ?? markup
			}
			guard isUsefulReleaseNotesText(relevantMarkup, relevantVersion: relevantVersion) else {
				return nil
			}

			let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
			let renderedMarkup = ([title, relevantMarkup]
				.compactMap { text in
					guard let text, !text.isEmpty else { return nil }
					return text
				} as [String]).joined(separator: "\n\n")
			return prepare(renderedMarkup, baseURL: baseURL, relevantVersion: relevantVersion)
		}
		guard let preparedMarkup else { return nil }
		let result = render(preparedMarkup)
		guard case .success = result else { return nil }
		return result
	}

	@MainActor
	static func plainTextAttributedStringByPreparingOffMain(
		fromHTML html: String,
		baseURL: URL?,
		relevantVersion: String?
	) async -> ReleaseNotesProvider.ReleaseNotes? {
		let preparedMarkup = await prepareOffMain {
			guard let text = plainText(fromHTML: html),
			      isUsefulReleaseNotesText(text, relevantVersion: relevantVersion) else {
				return nil
			}
			return prepare(text, baseURL: baseURL, relevantVersion: relevantVersion)
		}
		guard let preparedMarkup else { return nil }
		let result = render(preparedMarkup)
		guard case .success = result else { return nil }
		return result
	}

	@MainActor
	static func attributedStringFromChangelogByPreparingOffMain(
		fromHTML html: String,
		baseURL: URL,
		relevantVersion: String?,
		allowFirstSectionFallback: Bool
	) async -> ReleaseNotesProvider.ReleaseNotes? {
		let preparedMarkup = await prepareOffMain {
			guard let relevantText = relevantChangelogText(
				fromHTML: html,
				version: relevantVersion,
				pageURL: baseURL,
				allowFirstSectionFallback: allowFirstSectionFallback
			) else { return nil }
			return prepare(relevantText, baseURL: baseURL, relevantVersion: relevantVersion)
		}
		guard let preparedMarkup else { return nil }
		return render(preparedMarkup)
	}

	private static func prepareOffMain(
		_ operation: @escaping @Sendable () -> PreparedMarkup?
	) async -> PreparedMarkup? {
		let preparationTask = Task.detached(priority: .userInitiated) {
			guard !Task.isCancelled else { return Optional<PreparedMarkup>.none }
			let signpostID = releaseNotesSignposter.makeSignpostID()
			let interval = releaseNotesSignposter.beginInterval("Prepare Release Notes", id: signpostID)
			defer { releaseNotesSignposter.endInterval("Prepare Release Notes", interval) }
			return operation()
		}
		return await withTaskCancellationHandler {
			await preparationTask.value
		} onCancel: {
			preparationTask.cancel()
		}
	}

	private static func prepare(_ markup: String, baseURL: URL?, relevantVersion: String?) -> PreparedMarkup? {

		let trimmedMarkup = markup.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedMarkup.isEmpty else { return nil }

		let sourceMarkup = trimmedMarkup.containsHTMLTag ? trimmedMarkup : Self.normalizedPlainText(trimmedMarkup)
		let markup: String
		if sourceMarkup.containsHTMLTag,
		   let relevantVersion,
		   let text = Self.relevantChangelogText(fromHTML: sourceMarkup, version: relevantVersion, pageURL: baseURL ?? URL(fileURLWithPath: "/"), allowFirstSectionFallback: false) {
			markup = text
		} else {
			markup = Self.relevantText(from: sourceMarkup, version: relevantVersion, allowFirstSectionFallback: false) ?? sourceMarkup
		}

		let displayMarkup = markup.containsHTMLTag ? markup : Self.cleaningInlineMarkdown(in: markup)
		let normalizedMarkup = Self.removingDuplicateLeadingLines(displayMarkup)
		let isValidatedZedArticle = baseURL?.host?.localizedCaseInsensitiveContains("zed.dev") == true &&
			ZedReleaseNotesExtractor.isUsefulZedReleaseArticleText(normalizedMarkup)
		guard isValidatedZedArticle || Self.isUsefulReleaseNotesText(normalizedMarkup, relevantVersion: relevantVersion) else {
			return nil
		}

		if Self.prefersMarkdown(normalizedMarkup) {
			return PreparedMarkup(string: normalizedMarkup, kind: .markdown, baseURL: baseURL)
		}

		if !normalizedMarkup.containsHTMLTag {
			return PreparedMarkup(string: normalizedMarkup, kind: .plainText, baseURL: baseURL)
		}

		return PreparedMarkup(string: normalizedMarkup, kind: .html, baseURL: baseURL)
	}

	private static func render(_ preparedMarkup: PreparedMarkup) -> ReleaseNotesProvider.ReleaseNotes {
		switch preparedMarkup.kind {
		case .markdown:
			return .success(Self.attributedString(fromMarkdown: preparedMarkup.string))
		case .plainText:
			return .success(Self.attributedString(fromPlainText: preparedMarkup.string))
		case .html:
			return Self.attributedString(fromHTML: preparedMarkup.string, baseURL: preparedMarkup.baseURL)
		}
	}

	static func attributedString(from data: Data, baseURL: URL?, relevantVersion: String? = nil) -> ReleaseNotesProvider.ReleaseNotes {
		if let markup = String(data: data, encoding: .utf8), !Self.looksLikeBinaryOrMojibakeText(markup) {
			return Self.attributedString(from: markup, baseURL: baseURL, relevantVersion: relevantVersion)
		}

		var options : [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.html]

		var string: NSAttributedString
		do {
			string = try NSAttributedString(data: data, options: options, documentAttributes: nil)
		} catch let error {
			return .failure(error)
		}

		// Having only one line means that the text was no HTML but plain text. Therefore we instantiate the attributed string as plain text again.
		// The initialization with HTML enabled removes all new lines
		// If anyone has a better idea for checking if the data is valid HTML or plain text, feel free to fix.
		if string.string.split(separator: "\n").count == 1 {
			options[.documentType] = NSAttributedString.DocumentType.plain

			do {
				string = try NSAttributedString(data: data, options: options, documentAttributes: nil)
			} catch let error {
				return .failure(error)
			}
		}

		guard Self.isUsefulReleaseNotesText(string.string, relevantVersion: relevantVersion) else {
			return .failure(LatestError.releaseNotesUnavailable)
		}

		return .success(string)
	}

	@MainActor
	static func attributedStringByPreparingOffMain(
		from data: Data,
		baseURL: URL?,
		relevantVersion: String?
	) async -> ReleaseNotesProvider.ReleaseNotes {
		let markup = await Task.detached(priority: .userInitiated) {
			guard let markup = String(data: data, encoding: .utf8),
			      !looksLikeBinaryOrMojibakeText(markup) else {
				return Optional<String>.none
			}
			return markup
		}.value

		if let markup {
			return await attributedStringByPreparingOffMain(
				from: markup,
				baseURL: baseURL,
				relevantVersion: relevantVersion
			)
		}

		guard !Task.isCancelled else {
			return .failure(CancellationError())
		}
		return attributedString(from: data, baseURL: baseURL, relevantVersion: relevantVersion)
	}

}

extension String {

	var containsHTMLTag: Bool {
		range(of: #"<\s*/?\s*(html|body|p|br|div|span|ul|ol|li|h[1-6]|a|strong|em|table)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
	}

}

extension NSAttributedString {
	func mapToResolved(
		quality: ReleaseNotesQuality,
		provenance: ReleaseNotesProvenance
	) -> ResolvedReleaseNotes {
		ResolvedReleaseNotes(content: self, quality: quality, provenance: provenance)
	}
}
