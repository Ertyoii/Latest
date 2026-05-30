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
		if let releaseNotes = self.cache.object(forKey: cacheKey), !Self.isEffectivelyEmpty(releaseNotes) {
			completion(.success(releaseNotes))
			return
		}

		self.loadReleaseNotes(for: app) { releaseNotes in
			let releaseNotes = Self.validated(releaseNotes)
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
					self.releaseNotes(from: url, relevantVersion: app.remoteVersion?.versionNumber, requestID: currentRequestID, with: completion)
				case .encoded(let data):
					completion(ReleaseNotesMarkup.attributedString(from: data, baseURL: nil, relevantVersion: app.remoteVersion?.versionNumber))
				case .githubRelease(let apiURL, let fallbackHTML):
					Task {
						completion(await self.githubReleaseNotes(from: apiURL, relevantVersion: app.remoteVersion?.versionNumber, fallbackHTML: fallbackHTML))
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

	private nonisolated static func validated(_ releaseNotes: ReleaseNotes) -> ReleaseNotes {
		switch releaseNotes {
		case .success(let text) where isEffectivelyEmpty(text):
			return .failure(LatestError.releaseNotesUnavailable)
		default:
			return releaseNotes
		}
	}

	private nonisolated static func isEffectivelyEmpty(_ text: NSAttributedString) -> Bool {
		text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}


	/// Fetches release notes from the given URL.
	private func releaseNotes(from url: URL, relevantVersion: String?, requestID: UUID, with completion: @escaping Completion) {
		Task { [weak self] in
			guard let self else { return }

			do {
				let html = try await Self.fetchHTML(from: url)
				guard self.isCurrentRequest(requestID) else { return }
				completion(ReleaseNotesMarkup.attributedString(from: html, baseURL: url, relevantVersion: relevantVersion))
				return
			} catch FetchHTMLError.unusableText {
				guard self.isCurrentRequest(requestID) else { return }
				completion(.failure(LatestError.releaseNotesUnavailable))
				return
			} catch {
				guard self.isCurrentRequest(requestID) else { return }
				self.webReleaseNotes(from: url, relevantVersion: relevantVersion, requestID: requestID, with: completion)
			}
		}
	}

	private func webReleaseNotes(from url: URL, relevantVersion: String?, requestID: UUID, with completion: @escaping Completion) {
		activeWebContentLoader.load(from: url) { result in
			guard self.isCurrentRequest(requestID) else { return }

			switch result {
			case .success(let html):
				self.webContentLoader?.cancel()
				completion(ReleaseNotesMarkup.attributedString(from: html, baseURL: url, relevantVersion: relevantVersion))
			case .failure(let error):
				completion(.failure(error))
			}
		}
	}

	private func githubReleaseNotes(from url: URL, relevantVersion: String?, fallbackHTML: String?) async -> ReleaseNotes {
		do {
			let (data, _) = try await URLSession.shared.data(from: url)
			let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
			let body = Self.deduplicating(title: release.name, in: release.body.trimmingCharacters(in: .whitespacesAndNewlines))
			guard ReleaseNotesMarkup.isUsefulReleaseNotesText(body, relevantVersion: relevantVersion) else {
				if let fallbackHTML {
					return ReleaseNotesMarkup.attributedString(from: fallbackHTML, baseURL: nil, relevantVersion: relevantVersion)
				}
				return .failure(LatestError.releaseNotesUnavailable)
			}

			let title = release.name?.trimmingCharacters(in: .whitespacesAndNewlines)
			let markdown = ([title, ReleaseNotesMarkup.relevantText(from: body, version: relevantVersion, allowFirstSectionFallback: true)]
				.compactMap { text in
					guard let text, !text.isEmpty else { return nil }
					return text
				} as [String]).joined(separator: "\n\n")

			let result = ReleaseNotesMarkup.attributedString(from: markdown, baseURL: nil, relevantVersion: relevantVersion)
			if case .failure = result, let fallbackHTML {
				return ReleaseNotesMarkup.attributedString(from: fallbackHTML, baseURL: nil, relevantVersion: relevantVersion)
			}
			return result
		} catch {
			if let fallbackHTML {
				return ReleaseNotesMarkup.attributedString(from: fallbackHTML, baseURL: nil, relevantVersion: relevantVersion)
			}
			return .failure(error)
		}
	}

	private func changelogReleaseNotes(from urls: [URL], versionPrefix: String?, allowsLatestFallback: Bool, fallbackHTML: String?, requestID: UUID, with completion: @escaping Completion) {
		Task { [weak self] in
			guard let self else { return }

			if let content = await Self.fetchChangelogContent(from: urls, versionPrefix: versionPrefix, allowsLatestFallback: allowsLatestFallback) {
				guard self.isCurrentRequest(requestID) else { return }
				completion(ReleaseNotesMarkup.attributedString(from: content.text, baseURL: content.baseURL, relevantVersion: versionPrefix))
				return
			}

			guard self.isCurrentRequest(requestID) else { return }

			if let fallbackHTML {
				completion(ReleaseNotesMarkup.attributedString(from: fallbackHTML, baseURL: nil, relevantVersion: versionPrefix))
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
						finish(ReleaseNotesMarkup.attributedString(from: relevantText, baseURL: url, relevantVersion: versionPrefix))
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
						  let html = try? await Self.fetchHTML(from: url) else {
						return nil
					}

					return await Self.changelogContent(fromHTML: html, url: url, versionPrefix: versionPrefix, allowsLatestFallback: allowsLatestFallback)
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

	private nonisolated static func changelogContent(fromHTML html: String, url: URL, versionPrefix: String?, allowsLatestFallback: Bool) async -> ChangelogContent? {
		if let text = ReleaseNotesMarkup.relevantChangelogText(fromHTML: html, version: versionPrefix, pageURL: url, allowFirstSectionFallback: allowsLatestFallback) {
			return ChangelogContent(text: text, baseURL: url)
		}

		guard let linkedURL = ReleaseNotesMarkup.linkedChangelogURL(fromHTML: html, version: versionPrefix, pageURL: url),
			  linkedURL != url,
			  let linkedHTML = try? await Self.fetchHTML(from: linkedURL) else {
			return nil
		}

		if let text = ReleaseNotesMarkup.relevantChangelogText(fromHTML: linkedHTML, version: versionPrefix, pageURL: linkedURL, allowFirstSectionFallback: true) {
			return ChangelogContent(text: text, baseURL: linkedURL)
		}

		guard let text = ReleaseNotesMarkup.plainText(fromHTML: linkedHTML),
			  ReleaseNotesMarkup.isUsefulReleaseNotesText(text, relevantVersion: versionPrefix) else {
			return nil
		}

		return ChangelogContent(text: text, baseURL: linkedURL)
	}

	private nonisolated static func fetchHTML(from url: URL) async throws -> String {
		try await Self.validateURLCanContainHTML(url)

		var request = URLRequest(url: url)
		request.cachePolicy = .returnCacheDataElseLoad
		request.timeoutInterval = 4
		request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

		let (data, response) = try await URLSession.shared.data(for: request)

		if let response = response as? HTTPURLResponse,
		   !(200..<400).contains(response.statusCode) {
			throw FetchHTMLError.unusableText
		}

		guard Self.responseCanContainText(response),
			  let html = Self.decodedText(from: data, response: response),
			  !ReleaseNotesMarkup.looksLikeBinaryOrMojibakeText(html) else {
			throw FetchHTMLError.unusableText
		}

		return html
	}

}

private enum FetchHTMLError: Error {
	case unusableText
}

private extension ReleaseNotesProvider {

	nonisolated static func validateURLCanContainHTML(_ url: URL) async throws {
		if isLikelyDownloadURL(url) {
			throw FetchHTMLError.unusableText
		}

		var request = URLRequest(url: url)
		request.httpMethod = "HEAD"
		request.cachePolicy = .returnCacheDataElseLoad
		request.timeoutInterval = 4
		request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

		do {
			let (_, response) = try await URLSession.shared.data(for: request)

			if let response = response as? HTTPURLResponse {
				if response.statusCode == 405 || response.statusCode == 501 {
					return
				}

				guard (200..<400).contains(response.statusCode) else {
					throw FetchHTMLError.unusableText
				}
			}

			guard responseCanContainText(response) else {
				throw FetchHTMLError.unusableText
			}
		} catch FetchHTMLError.unusableText {
			throw FetchHTMLError.unusableText
		} catch {
			// Some changelog hosts reject HEAD while serving valid HTML to GET.
			// In that case the body fetch below remains the source of truth.
			return
		}
	}

	nonisolated static func isLikelyDownloadURL(_ url: URL) -> Bool {
		let downloadExtensions: Set<String> = [
			"7z", "bz2", "dmg", "exe", "gz", "msi", "pkg", "rar", "tbz", "tgz", "xip", "xz", "zip"
		]

		return downloadExtensions.contains(url.pathExtension.lowercased())
	}

	nonisolated static func deduplicating(title: String?, in body: String) -> String {
		guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
			return body
		}

		var lines = body.components(separatedBy: .newlines)
		while let firstLine = lines.first, ReleaseNotesMarkup.normalizedReleaseLine(firstLine) == ReleaseNotesMarkup.normalizedReleaseLine(title) {
			lines.removeFirst()
		}

		return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
	}

	nonisolated static func responseCanContainText(_ response: URLResponse) -> Bool {
		guard let mimeType = response.mimeType?.lowercased() else { return true }
		return mimeType.hasPrefix("text/") ||
			mimeType == "application/json" ||
			mimeType == "application/xml" ||
			mimeType == "application/xhtml+xml" ||
			mimeType == "application/rss+xml" ||
			mimeType == "application/atom+xml"
	}

	nonisolated static func decodedText(from data: Data, response: URLResponse) -> String? {
		if let text = String(data: data, encoding: .utf8) {
			return text
		}

		let encodingName = response.textEncodingName?.lowercased() ?? ""
		if encodingName.contains("iso-8859-1") || encodingName.contains("latin1") || encodingName.contains("windows-1252") {
			return String(data: data, encoding: .isoLatin1)
		}

		return nil
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
		case .githubRelease(let apiURL, let fallbackHTML):
			return "github:\(apiURL.absoluteString):\(fallbackHTML?.hashValue ?? 0)"
		case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML):
			let urlList = urls.map(\.absoluteString).joined(separator: "|")
			return "changelog:\(urlList):\(versionPrefix ?? ""):\(allowsLatestFallback):\(fallbackHTML?.hashValue ?? 0)"
		}
	}
}

enum ReleaseNotesMarkup {

	static func attributedString(from markup: String, baseURL: URL?, relevantVersion: String? = nil) -> ReleaseNotesProvider.ReleaseNotes {
		let trimmedMarkup = markup.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedMarkup.isEmpty else {
			return .failure(LatestError.releaseNotesUnavailable)
		}

		let sourceMarkup = trimmedMarkup.containsHTMLTag ? trimmedMarkup : Self.normalizedPlainText(trimmedMarkup)
		let markup: String
		if sourceMarkup.containsHTMLTag,
		   let relevantVersion,
		   let text = Self.relevantChangelogText(fromHTML: sourceMarkup, version: relevantVersion, pageURL: baseURL ?? URL(fileURLWithPath: "/"), allowFirstSectionFallback: false) {
			markup = text
		} else {
			markup = Self.relevantText(from: sourceMarkup, version: relevantVersion, allowFirstSectionFallback: false) ?? sourceMarkup
		}

		let normalizedMarkup = Self.removingDuplicateLeadingLines(markup)
		guard Self.isUsefulReleaseNotesText(normalizedMarkup, relevantVersion: relevantVersion) else {
			return .failure(LatestError.releaseNotesUnavailable)
		}

		if Self.prefersMarkdown(normalizedMarkup) {
			return .success(Self.attributedString(fromMarkdown: normalizedMarkup))
		}

		if !normalizedMarkup.containsHTMLTag {
			return .success(Self.attributedString(fromPlainText: normalizedMarkup))
		}

		return Self.attributedString(fromHTML: normalizedMarkup, baseURL: baseURL)
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
			  Self.isUsefulReleaseNotesText(relevantText, relevantVersion: version) else {
			return nil
		}

		return relevantText
	}

	static func plainText(fromHTML html: String) -> String? {
		var text = html

		text = text.replacingOccurrences(of: #"(?is)<(script|style|noscript|svg)\b.*?</\1>"#, with: "\n", options: .regularExpression)
		text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
		text = text.replacingOccurrences(of: #"(?i)<li\b[^>]*>"#, with: "\n- ", options: .regularExpression)
		text = text.replacingOccurrences(of: #"(?i)<(p|div|h[1-6]|tr|section|article|header|footer|table|ul|ol|dl|dt|dd)\b[^>]*>"#, with: "\n", options: .regularExpression)
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

	static func firstReleaseNotesURL(in markup: String, baseURL: URL?) -> URL? {
		if let hrefURL = Self.firstHrefURL(in: markup, baseURL: baseURL) {
			return hrefURL
		}

		let pattern = #"https?://[^\s<>"']+"#
		guard let regex = try? NSRegularExpression(pattern: pattern) else {
			return nil
		}

		let range = NSRange(markup.startIndex..<markup.endIndex, in: markup)
		guard let match = regex.firstMatch(in: markup, range: range),
			  let matchRange = Range(match.range, in: markup) else {
			return nil
		}

		let urlString = String(markup[matchRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)"))
		return URL(string: urlString)
	}

	static func linkedChangelogURL(fromHTML html: String, version: String?, pageURL: URL) -> URL? {
		let candidates = versionCandidates(from: version)
		guard !candidates.isEmpty else { return nil }

		let pattern = #"(?is)<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#
		guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

		let range = NSRange(html.startIndex..<html.endIndex, in: html)
		let matches = regex.matches(in: html, range: range)
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

			if let url = URL(string: href, relativeTo: pageURL)?.absoluteURL {
				return url
			}
		}

		return nil
	}

	static func isUsefulReleaseNotesText(_ text: String, relevantVersion: String? = nil) -> Bool {
		let displayText = text.containsHTMLTag ? (Self.plainText(fromHTML: text) ?? text) : text
		guard !Self.looksLikeBinaryOrMojibakeText(displayText),
			  !Self.looksLikeWebPageChrome(displayText) else {
			return false
		}

		var informationText = displayText
		informationText = informationText.replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
		informationText = informationText.replacingOccurrences(of: #"\[[^\]]*\]\([^)]+\)"#, with: " ", options: .regularExpression)
		informationText = informationText.replacingOccurrences(of: #"\bv?\d+(?:\.\d+){1,}(?:\.\d+)?\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
		if let relevantVersion, !relevantVersion.isEmpty {
			informationText = informationText.replacingOccurrences(of: relevantVersion, with: " ", options: [.caseInsensitive])
		}
		informationText = informationText.replacingOccurrences(of: #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{4}\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
		informationText = informationText.replacingOccurrences(of: #"\b\d{4}-\d{2}-\d{2}\b"#, with: " ", options: .regularExpression)

		let lowercasedInformationText = informationText.lowercased()
		let words = lowercasedInformationText.matches(of: /[a-z][a-z0-9+-]{1,}/).map { String(lowercasedInformationText[$0.range]) }
		let genericWords: Set<String> = [
			"changelog", "changes", "details", "history", "latest", "link", "links",
			"more", "note", "notes", "public", "recent", "release", "releases",
			"version", "versions", "view", "whats", "what"
		]
		let meaningfulWords = words.filter { !genericWords.contains($0) }

		return meaningfulWords.count >= 2 || meaningfulWords.joined().count >= 14
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

	static func normalizedReleaseLine(_ line: String) -> String {
		var normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
		normalized = normalized.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
		normalized = normalized.replacingOccurrences(of: #"^(\*|-|•)\s+"#, with: "", options: .regularExpression)
		normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
		return normalized.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)).lowercased()
	}

	static func looksLikeBinaryOrMojibakeText(_ text: String) -> Bool {
		let scalars = text.unicodeScalars.filter { !$0.properties.isWhitespace }
		guard scalars.count > 40 else { return false }

		if scalars.contains(where: { scalar in
			(scalar.value < 32 || scalar.value == 127) && scalar.value != 10 && scalar.value != 9 && scalar.value != 13
		}) {
			return true
		}

		let cjkCount = scalars.filter { scalar in
			(0x4E00...0x9FFF).contains(Int(scalar.value)) ||
			(0x3040...0x30FF).contains(Int(scalar.value)) ||
			(0xAC00...0xD7AF).contains(Int(scalar.value))
		}.count
		let cjkRatio = Double(cjkCount) / Double(scalars.count)
		if cjkRatio > 0.2 {
			return false
		}

		let latin1SupplementCount = scalars.filter { (0x00A0...0x00FF).contains(Int($0.value)) }.count
		let nonASCIIPrintableCount = scalars.filter { $0.value > 127 }.count
		let asciiWordCount = text.matches(of: /[A-Za-z][A-Za-z0-9+-]{2,}/).count
		let latin1Ratio = Double(latin1SupplementCount) / Double(scalars.count)
		let nonASCIIRatio = Double(nonASCIIPrintableCount) / Double(scalars.count)

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
		let releaseTerms = ["release", "changelog", "change log", "fixed", "bug", "improved", "added", "security", "resolved"]
		let hasReleaseTerms = releaseTerms.contains { lowercased.contains($0) }
		if lines.count >= 30 && !hasReleaseTerms {
			return true
		}

		let shortNavigationLikeLines = lines.filter { line in
			let wordCount = line.split(separator: " ").count
			return wordCount <= 5 && !line.contains(".") && !line.contains(":")
		}
		return lines.count >= 18 && shortNavigationLikeLines.count >= 12 && !hasReleaseTerms
	}

	private static func removingDuplicateLeadingLines(_ text: String) -> String {
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
		let bodyVerbs: Set<String> = [
			"adds", "allows", "applies", "brings", "changes", "fixes",
			"improves", "introduces", "lets", "makes", "resolves", "updates"
		]
		return bodyVerbs.contains(Self.normalizedToken(firstWord))
	}

	private static func capitalizingFirstLetter(_ text: String) -> String {
		guard let first = text.first else { return text }
		return first.uppercased() + text.dropFirst()
	}

	private static func normalizedPlainText(_ text: String) -> String {
		var result = text
		result = result.replacingOccurrences(of: #"(?i)(\s·\s*Changelog)\s+"#, with: "$1\n", options: .regularExpression)
		result = result.replacingOccurrences(of: #"(?i)(^|\s)(v?\d+(?:\.\d+){1,}\s+[A-Z][a-z]+\s+\d{1,2},\s+\d{4})\s+(?!·)"#, with: "$1$2\n", options: .regularExpression)
		result = result.replacingOccurrences(of: #"(\S)\s+(?=v?\d+(?:\.\d+){1,}\s+[A-Z][a-z]+\s+\d{1,2},\s+\d{4}\b)"#, with: "$1\n", options: [.regularExpression, .caseInsensitive])

		let lines = result.components(separatedBy: .newlines).map { Self.splittingRepeatedHeadingPrefix(in: $0) }
		return lines.joined(separator: "\n")
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

		let bodyVerbs: Set<String> = [
			"adds", "allows", "applies", "are", "brings", "can", "changes",
			"fixes", "has", "have", "improves", "introduces", "is", "lets",
			"makes", "now", "updates", "uses", "was", "were", "will"
		]
		return bodyVerbs.contains(Self.normalizedToken(tokens[tokens.index(after: tokens.startIndex)]))
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

	private static func attributedString(fromPlainText text: String) -> NSAttributedString {
		NSAttributedString(string: text + "\n", attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
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

	private static func firstHrefURL(in html: String, baseURL: URL?) -> URL? {
		let pattern = #"(?is)<a\b[^>]*\bhref\s*=\s*["']([^"']+)["']"#
		guard let regex = try? NSRegularExpression(pattern: pattern) else {
			return nil
		}

		let range = NSRange(html.startIndex..<html.endIndex, in: html)
		guard let match = regex.firstMatch(in: html, range: range),
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
		line.range(of: #"^v?\d+(\.\d+){1,}(\s|$|-)"#, options: [.regularExpression, .caseInsensitive]) != nil ||
		line.range(of: #"^(?![-*•])\D{1,60}v?\d+(\.\d+){1,}(\s|$|-)"#, options: [.regularExpression, .caseInsensitive]) != nil
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
