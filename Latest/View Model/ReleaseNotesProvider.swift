//
//  ReleaseNotesProvider.swift
//  Latest
//
//  Created by Max Langer on 04.03.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import AppKit

/// Handles release notes conversion and loading.
///
/// The object provides release notes in a uniform representation and caches remote contents for faster access.
@MainActor
class ReleaseNotesProvider {

	/// The return value, containing either the desired release notes, or an error if unavailable.
	typealias ReleaseNotes = Result<NSAttributedString, Error>
	typealias Completion = @MainActor (ReleaseNotes) -> Void

	/// Initializes the provider.
	init() {
		self.cache = NSCache()
	}

	/// Tracks the currently requested app.
	///
	/// Used to suppress completion calls from older requests.
	private var currentApp: App?

	/// Tracks the currently requested release notes operation.
	private var currentRequestID = UUID()

	/// Provides release notes for the given app.
	func releaseNotes(for app: App, with completion: @escaping Completion) {
		let requestID = UUID()
		currentApp = app
		currentRequestID = requestID
		webContentLoader?.cancel()

		let cacheKey = ReleaseNotesCacheKey(app: app)
		if let releaseNotes = self.cache.object(forKey: cacheKey) {
			completion(.success(releaseNotes))
			return
		}

		self.loadReleaseNotes(for: app) { releaseNotes in
			if case .success(let text) = releaseNotes {
				self.cache.setObject(text, forKey: cacheKey)
			}

			/// Release notes may be returned late or updated while another app was already requested. Don't forward this update, just cache in case of success.
			guard self.isCurrentRequest(requestID, for: app) else { return }

			completion(releaseNotes)
		}
	}


	// MARK: - Release Notes Handling

	/// The cache for release notes content.
	///
	/// All content is cached, since any given release notes object requires some sort of modification.
	private var cache: NSCache<ReleaseNotesCacheKey, NSAttributedString>

	/// Object loading HTML content for any given URL.
	private var webContentLoader: WebContentLoader?

	private var activeWebContentLoader: WebContentLoader {
		if let webContentLoader {
			return webContentLoader
		}

		let webContentLoader = WebContentLoader()
		self.webContentLoader = webContentLoader
		return webContentLoader
	}

	private func loadReleaseNotes(for app: App, with completion: @escaping Completion) {
		if let releaseNotes = app.releaseNotes {
			switch releaseNotes {
				case .html(let html):
					completion(ReleaseNotesMarkup.attributedString(from: html, baseURL: nil, relevantVersion: app.remoteVersion?.versionNumber))
				case .url(let url):
					self.releaseNotes(from: url, requestID: currentRequestID, with: completion)
				case .encoded(let data):
					completion(ReleaseNotesMarkup.attributedString(from: data, baseURL: nil))
				case .githubRelease(let apiURL):
					Task {
						completion(await self.githubReleaseNotes(from: apiURL, relevantVersion: app.remoteVersion?.versionNumber))
					}
				case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML):
					self.changelogReleaseNotes(from: urls, versionPrefix: versionPrefix ?? app.remoteVersion?.versionNumber, allowsLatestFallback: allowsLatestFallback, fallbackHTML: fallbackHTML, requestID: currentRequestID, with: completion)
			}
		} else if let error = app.error {
			completion(.failure(error))
		} else {
			completion(.failure(LatestError.releaseNotesUnavailable))
		}
	}

	private func isCurrentRequest(_ requestID: UUID, for app: App? = nil) -> Bool {
		guard requestID == currentRequestID else { return false }

		if let app {
			return currentApp == app
		}

		return true
	}


	/// Fetches release notes from the given URL.
	private func releaseNotes(from url: URL, requestID: UUID, with completion: @escaping Completion) {
		Task { [weak self] in
			guard let self else { return }

			if let html = try? await Self.fetchHTML(from: url) {
				guard self.isCurrentRequest(requestID) else { return }
				completion(ReleaseNotesMarkup.attributedString(from: html, baseURL: url))
				return
			}

			guard self.isCurrentRequest(requestID) else { return }
			self.webReleaseNotes(from: url, requestID: requestID, with: completion)
		}
	}

	private func webReleaseNotes(from url: URL, requestID: UUID, with completion: @escaping Completion) {
		activeWebContentLoader.load(from: url) { result in
			guard self.isCurrentRequest(requestID) else { return }

			switch result {
			case .success(let html):
				self.webContentLoader?.cancel()
				completion(ReleaseNotesMarkup.attributedString(from: html, baseURL: url))
			case .failure(let error):
				completion(.failure(error))
			}
		}
	}

	private func githubReleaseNotes(from url: URL, relevantVersion: String?) async -> ReleaseNotes {
		do {
			let (data, _) = try await URLSession.shared.data(from: url)
			let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
			let body = release.body.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !body.isEmpty else {
				return .failure(LatestError.releaseNotesUnavailable)
			}

			let title = release.name?.trimmingCharacters(in: .whitespacesAndNewlines)
			let markdown = ([title, ReleaseNotesMarkup.relevantText(from: body, version: relevantVersion, allowFirstSectionFallback: true)]
				.compactMap { text in
					guard let text, !text.isEmpty else { return nil }
					return text
				} as [String]).joined(separator: "\n\n")

			return ReleaseNotesMarkup.attributedString(from: markdown, baseURL: nil)
		} catch {
			return .failure(error)
		}
	}

	private func changelogReleaseNotes(from urls: [URL], versionPrefix: String?, allowsLatestFallback: Bool, fallbackHTML: String?, requestID: UUID, with completion: @escaping Completion) {
		Task { [weak self] in
			guard let self else { return }

			if let content = await Self.fetchChangelogContent(from: urls, versionPrefix: versionPrefix, allowsLatestFallback: allowsLatestFallback) {
				guard self.isCurrentRequest(requestID) else { return }
				completion(ReleaseNotesMarkup.attributedString(from: content.text, baseURL: content.baseURL))
				return
			}

			guard self.isCurrentRequest(requestID) else { return }

			if let fallbackHTML {
				completion(ReleaseNotesMarkup.attributedString(from: fallbackHTML, baseURL: nil))
				return
			}

			self.webChangelogReleaseNotes(from: urls, versionPrefix: versionPrefix, allowsLatestFallback: allowsLatestFallback, requestID: requestID, with: completion)
		}
	}

	private func webChangelogReleaseNotes(from urls: [URL], versionPrefix: String?, allowsLatestFallback: Bool, requestID: UUID, with completion: @escaping Completion) {
		var remainingURLs = urls
		var activeAttemptID = UUID()
		var didComplete = false

		func finish(_ releaseNotes: ReleaseNotes) {
			guard !didComplete else { return }
			didComplete = true
			self.webContentLoader?.cancel()
			completion(releaseNotes)
		}

		func loadNext() {
			guard !remainingURLs.isEmpty else {
				finish(.failure(LatestError.releaseNotesUnavailable))
				return
			}

			let url = remainingURLs.removeFirst()
			let attemptID = UUID()
			activeAttemptID = attemptID

			activeWebContentLoader.load(from: url) { result in
				guard self.isCurrentRequest(requestID), activeAttemptID == attemptID, !didComplete else { return }

				switch result {
				case .success(let html):
					if let relevantText = ReleaseNotesMarkup.relevantChangelogText(fromHTML: html, version: versionPrefix, pageURL: url, allowFirstSectionFallback: allowsLatestFallback) {
						finish(ReleaseNotesMarkup.attributedString(from: relevantText, baseURL: url))
						return
					}

					loadNext()
				case .failure:
					loadNext()
				}
			}
		}

		loadNext()
	}

	private nonisolated static func fetchChangelogContent(from urls: [URL], versionPrefix: String?, allowsLatestFallback: Bool) async -> ChangelogContent? {
		await withTaskGroup(of: ChangelogContent?.self) { group in
			for url in urls {
				group.addTask {
					guard !Task.isCancelled,
						  let html = try? await Self.fetchHTML(from: url),
						  let text = ReleaseNotesMarkup.relevantChangelogText(fromHTML: html, version: versionPrefix, pageURL: url, allowFirstSectionFallback: allowsLatestFallback) else {
						return nil
					}

					return ChangelogContent(text: text, baseURL: url)
				}
			}

			for await content in group {
				if let content {
					group.cancelAll()
					return content
				}
			}

			return nil
		}
	}

	private nonisolated static func fetchHTML(from url: URL) async throws -> String {
		var request = URLRequest(url: url)
		request.cachePolicy = .returnCacheDataElseLoad
		request.timeoutInterval = 4
		request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

		let (data, response) = try await URLSession.shared.data(for: request)

		if let response = response as? HTTPURLResponse,
		   !(200..<400).contains(response.statusCode) {
			throw LatestError.releaseNotesUnavailable
		}

		if let html = String(data: data, encoding: .utf8) {
			return html
		}

		if let html = String(data: data, encoding: .isoLatin1) {
			return html
		}

		throw LatestError.releaseNotesUnavailable
	}

}

private struct GitHubRelease: Decodable {
	let name: String?
	let body: String
}

private struct ChangelogContent: Sendable {
	let text: String
	let baseURL: URL
}

private final class ReleaseNotesCacheKey: NSObject {
	private let identifier: App.Bundle.Identifier
	private let localVersion: String
	private let remoteVersion: String
	private let releaseNotes: String

	init(app: App) {
		self.identifier = app.identifier
		self.localVersion = app.version.debugDescription
		self.remoteVersion = app.remoteVersion?.debugDescription ?? ""
		self.releaseNotes = app.releaseNotes?.cacheIdentifier ?? ""
	}

	override var hash: Int {
		var hasher = Hasher()
		hasher.combine(identifier)
		hasher.combine(localVersion)
		hasher.combine(remoteVersion)
		hasher.combine(releaseNotes)
		return hasher.finalize()
	}

	override func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? ReleaseNotesCacheKey else {
			return false
		}

		return identifier == other.identifier &&
			localVersion == other.localVersion &&
			remoteVersion == other.remoteVersion &&
			releaseNotes == other.releaseNotes
	}
}

private extension App.Update.ReleaseNotes {
	var cacheIdentifier: String {
		switch self {
		case .url(let url):
			return "url:\(url.absoluteString)"
		case .html(let string):
			return "html:\(string.hashValue)"
		case .encoded(let data):
			return "encoded:\(data.hashValue)"
		case .githubRelease(let apiURL):
			return "github:\(apiURL.absoluteString)"
		case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML):
			let urlList = urls.map(\.absoluteString).joined(separator: "|")
			return "changelog:\(urlList):\(versionPrefix ?? ""):\(allowsLatestFallback):\(fallbackHTML?.hashValue ?? 0)"
		}
	}
}

enum ReleaseNotesMarkup {

	static func attributedString(from markup: String, baseURL: URL?, relevantVersion: String? = nil) -> ReleaseNotesProvider.ReleaseNotes {
		let markup = Self.relevantText(from: markup, version: relevantVersion, allowFirstSectionFallback: false) ?? markup

		if Self.prefersMarkdown(markup) {
			return .success(Self.attributedString(fromMarkdown: markup))
		}

		return Self.attributedString(fromHTML: markup, baseURL: baseURL)
	}

	static func attributedString(from data: Data, baseURL: URL?) -> ReleaseNotesProvider.ReleaseNotes {
		if let markup = String(data: data, encoding: .utf8), Self.prefersMarkdown(markup) {
			return Self.attributedString(from: markup, baseURL: baseURL)
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

		return .success(string)
	}

	static func zedReleaseText(fromHTML html: String, version: String?, pageURL: URL) -> String? {
		guard pageURL.host?.localizedCaseInsensitiveContains("zed.dev") == true,
			  let version = version?.trimmingCharacters(in: .whitespacesAndNewlines),
			  !version.isEmpty else {
			return nil
		}

		let escapedVersion = NSRegularExpression.escapedPattern(for: version)
		let pattern = #"\\\"release\\\":\{\\\"version\\\":\\\""# + escapedVersion + #"\\\",\\\"description\\\":\\\"((?:\\\\.|[^\\\"])*)\\\""#
		guard let regex = try? NSRegularExpression(pattern: pattern) else {
			return nil
		}

		let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
		guard let match = regex.firstMatch(in: html, range: htmlRange),
			  let descriptionRange = Range(match.range(at: 1), in: html) else {
			return nil
		}

		let escapedDescription = String(html[descriptionRange])
		let jsonString = "\"\(escapedDescription)\""
		guard let data = jsonString.data(using: .utf8),
			  let decodedDescription = try? JSONDecoder().decode(String.self, from: data) else {
			return nil
		}

		let description = decodedDescription
			.replacingOccurrences(of: "\\r", with: "\r")
			.replacingOccurrences(of: "\\n", with: "\n")
			.trimmingCharacters(in: .whitespacesAndNewlines)

		return description.isEmpty ? nil : description
	}

	static func relevantChangelogText(fromHTML html: String, version: String?, pageURL: URL, allowFirstSectionFallback: Bool) -> String? {
		if let relevantText = Self.zedReleaseText(fromHTML: html, version: version, pageURL: pageURL) {
			return relevantText
		}

		guard let text = Self.plainText(fromHTML: html),
			  let relevantText = Self.relevantText(from: text, version: version, allowFirstSectionFallback: allowFirstSectionFallback),
			  !relevantText.isEmpty else {
			return nil
		}

		return relevantText
	}

	static func plainText(fromHTML html: String) -> String? {
		var text = html

		text = text.replacingOccurrences(of: #"(?is)<(script|style|noscript|svg)\b.*?</\1>"#, with: "\n", options: .regularExpression)
		text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
		text = text.replacingOccurrences(of: #"(?i)<li\b[^>]*>"#, with: "\n- ", options: .regularExpression)
		text = text.replacingOccurrences(of: #"(?i)</(p|div|li|h[1-6]|tr|section|article|header|footer|table|ul|ol|dl|dt|dd)>"#, with: "\n", options: .regularExpression)
		text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
		text = Self.decodingHTMLEntities(in: text)
		text = text.replacingOccurrences(of: "\u{00a0}", with: " ")

		let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
			let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
				.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
			return trimmedLine.isEmpty ? nil : trimmedLine
		}

		return lines.isEmpty ? nil : lines.joined(separator: "\n")
	}

	static func relevantText(from text: String, version: String?, allowFirstSectionFallback: Bool) -> String? {
		let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
			let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmedLine.isEmpty ? nil : trimmedLine
		}

		guard !lines.isEmpty else { return nil }

		let versionCandidates = Self.versionCandidates(from: version)
		var startIndex: Int?

		if !versionCandidates.isEmpty {
			startIndex = lines.firstIndex { line in
				guard !Self.looksLikeVersionNavigation(line) else { return false }

				return versionCandidates.contains { version in
					line.range(of: #"(^|[^\d])v?\#(NSRegularExpression.escapedPattern(for: version))([^\d]|\z)"#, options: [.regularExpression, .caseInsensitive]) != nil
				}
			}
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
		let endIndex = lines[(startIndex + 1)...].firstIndex { line in
			let isBoundary = shouldEndAtVersionBoundary ? Self.looksLikeVersionBoundary(line) : Self.looksLikeReleaseBoundary(line)
			return isBoundary && !(exactVersion.map { line.localizedCaseInsensitiveContains($0) } ?? false)
		} ?? lines.endIndex

		let selectedLines = lines[startIndex..<endIndex]
		guard !selectedLines.isEmpty else { return nil }

		return selectedLines.joined(separator: "\n")
	}

	private static func attributedString(fromMarkdown markdown: String) -> NSAttributedString {
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
			} else if let bulletRange = trimmedLine.range(of: #"^(\*|-|•)\s+"#, options: .regularExpression) {
				text = "• " + Self.removingLeadingBulletMarkers(from: String(trimmedLine[bulletRange.upperBound...]))
				font = bodyFont
			} else if let numberedRange = trimmedLine.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
				text = String(trimmedLine[..<numberedRange.upperBound]) + String(trimmedLine[numberedRange.upperBound...])
				font = bodyFont
			} else {
				text = trimmedLine
				font = bodyFont
			}

			result.append(NSAttributedString(string: text + "\n", attributes: [.font: font]))
		}

		return result
	}

	private static func attributedString(fromHTML html: String, baseURL: URL?) -> ReleaseNotesProvider.ReleaseNotes {
		guard let data = html.data(using: .utf16) else {
			return .failure(LatestError.releaseNotesUnavailable)
		}

		guard let string = Self.attributedString(fromHTMLData: data, baseURL: baseURL) else {
			return .failure(LatestError.releaseNotesUnavailable)
		}

		return .success(string)
	}

	private static func attributedString(fromHTMLData data: Data, baseURL: URL?) -> NSAttributedString? {
		if let baseURL {
			return NSAttributedString(html: data, baseURL: baseURL, documentAttributes: nil)
		}

		return NSAttributedString(html: data, documentAttributes: nil)
	}

	private static func prefersMarkdown(_ string: String) -> Bool {
		guard !string.containsHTMLTag else { return false }

		return string.split(whereSeparator: \.isNewline).contains { line in
			let trimmedLine = line.drop(while: \.isWhitespace)
			return trimmedLine.hasPrefix("#") ||
			trimmedLine.hasPrefix("* ") ||
			trimmedLine.hasPrefix("- ") ||
			trimmedLine.hasPrefix("• ") ||
			trimmedLine.range(of: #"^\d+\. "#, options: .regularExpression) != nil
		}
	}

	private static func removingLeadingBulletMarkers(from string: String) -> String {
		var result = string.trimmingCharacters(in: .whitespaces)

		while let range = result.range(of: #"^(\*|-|•)\s+"#, options: .regularExpression) {
			result = String(result[range.upperBound...]).trimmingCharacters(in: .whitespaces)
		}

		return result
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

		guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
			return result
		}

		let matches = regex.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
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
		line.range(of: #"^[A-Z][a-z]+ \d{1,2}, \d{4}"#, options: .regularExpression) != nil
	}

	private static func looksLikeVersionBoundary(_ line: String) -> Bool {
		line.range(of: #"^#{1,6}\s*v?\d+(\.\d+){1,}"#, options: [.regularExpression, .caseInsensitive]) != nil ||
		line.range(of: #"^v?\d+(\.\d+){1,}(\s|$|-)"#, options: [.regularExpression, .caseInsensitive]) != nil
	}

	private static func looksLikeVersionNavigation(_ line: String) -> Bool {
		let matches = line.matches(of: /\bv?\d+(?:\.\d+){1,}\b/)
		guard matches.count >= 4 else { return false }

		let words = line.matches(of: /[A-Za-z]{3,}/).map { String(line[$0.range]) }
		let navigationWords = Set(["versions", "version", "channel", "stable", "preview", "releases"])
		let meaningfulWords = words.filter { !navigationWords.contains($0.lowercased()) }

		return meaningfulWords.count <= 2
	}

}

private extension String {

	var containsHTMLTag: Bool {
		range(of: #"<\s*/?\s*(html|body|p|br|div|span|ul|ol|li|h[1-6]|a|strong|em|table)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
	}

}
