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
class ReleaseNotesProvider {
	
	/// The return value, containing either the desired release notes, or an error if unavailable.
	typealias ReleaseNotes = Result<NSAttributedString, Error>
	
	/// Initializes the provider.
	init() {
		self.cache = NSCache()
	}
	
	/// Tracks the currently requested app.
	///
	/// Used to suppress completion calls from older requests.
	private var currentApp: App?
	
	/// Provides release notes for the given app.
	func releaseNotes(for app: App, with completion: @escaping (ReleaseNotes) -> Void) {
		currentApp = app
		
		if let releaseNotes = self.cache.object(forKey: app) {
			completion(.success(releaseNotes))
			return
		}

		self.loadReleaseNotes(for: app) { releaseNotes in
			if case .success(let text) = releaseNotes {
				self.cache.setObject(text, forKey: app)
			}
			
			/// Release notes may be returned late or updated while another app was already requested. Don't forward this update, just cache in case of success.
			guard self.currentApp == app else { return }
			
			completion(releaseNotes)
		}
	}
	
	
	// MARK: - Release Notes Handling
	
	/// The cache for release notes content.
	///
	/// All content is cached, since any given release notes object requires some sort of modification.
	private var cache: NSCache<App, NSAttributedString>
	
	/// Object loading HTML content for any given URL.
	private lazy var webContentLoader = WebContentLoader()
	
	private func loadReleaseNotes(for app: App, with completion: @escaping (ReleaseNotes) -> Void) {
		if let releaseNotes = app.releaseNotes {
			switch releaseNotes {
				case .html(let html):
					completion(ReleaseNotesMarkup.attributedString(from: html, baseURL: nil, relevantVersion: app.remoteVersion?.versionNumber))
				case .url(let url):
					self.releaseNotes(from: url, with: completion)
				case .encoded(let data):
					completion(ReleaseNotesMarkup.attributedString(from: data, baseURL: nil))
				case .githubRelease(let apiURL):
					self.githubReleaseNotes(from: apiURL, relevantVersion: app.remoteVersion?.versionNumber, with: completion)
				case .changelog(let urls, let versionPrefix, let allowsLatestFallback):
					self.changelogReleaseNotes(from: urls, versionPrefix: versionPrefix ?? app.remoteVersion?.versionNumber, allowsLatestFallback: allowsLatestFallback, with: completion)
			}
		} else if let error = app.error {
			completion(.failure(error))
		} else {
			completion(.failure(LatestError.releaseNotesUnavailable))
		}
	}
	
	
	/// Fetches release notes from the given URL.
	private func releaseNotes(from url: URL, with completion: @escaping (ReleaseNotes) -> Void) {
		webContentLoader.load(from: url) { result in
			switch result {
			case .success(let html):
				completion(ReleaseNotesMarkup.attributedString(from: html, baseURL: url))
			case .failure(let error):
				completion(.failure(error))
			}
		}
	}

	private func githubReleaseNotes(from url: URL, relevantVersion: String?, with completion: @escaping (ReleaseNotes) -> Void) {
		URLSession.shared.dataTask(with: url) { data, _, error in
			DispatchQueue.main.async {
				if let error {
					completion(.failure(error))
					return
				}

				guard let data else {
					completion(.failure(LatestError.releaseNotesUnavailable))
					return
				}

				do {
					let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
					let body = release.body.trimmingCharacters(in: .whitespacesAndNewlines)
					guard !body.isEmpty else {
						completion(.failure(LatestError.releaseNotesUnavailable))
						return
					}

					let title = release.name?.trimmingCharacters(in: .whitespacesAndNewlines)
					let markdown = ([title, ReleaseNotesMarkup.relevantText(from: body, version: relevantVersion, allowFirstSectionFallback: true)]
						.compactMap { text in
							guard let text, !text.isEmpty else { return nil }
							return text
						} as [String]).joined(separator: "\n\n")

					completion(ReleaseNotesMarkup.attributedString(from: markdown, baseURL: nil))
				} catch {
					completion(.failure(error))
				}
			}
		}.resume()
	}

	private func changelogReleaseNotes(from urls: [URL], versionPrefix: String?, allowsLatestFallback: Bool, with completion: @escaping (ReleaseNotes) -> Void) {
		var remainingURLs = urls

		func loadNext() {
			guard !remainingURLs.isEmpty else {
				completion(.failure(LatestError.releaseNotesUnavailable))
				return
			}

			let url = remainingURLs.removeFirst()
			webContentLoader.load(from: url) { result in
				switch result {
				case .success(let html):
					guard let text = ReleaseNotesMarkup.plainText(fromHTML: html),
						  let relevantText = ReleaseNotesMarkup.relevantText(from: text, version: versionPrefix, allowFirstSectionFallback: allowsLatestFallback),
						  !relevantText.isEmpty else {
						loadNext()
						return
					}

					completion(ReleaseNotesMarkup.attributedString(from: relevantText, baseURL: url))
				case .failure:
					loadNext()
				}
			}
		}

		loadNext()
	}

}

private struct GitHubRelease: Decodable {
	let name: String?
	let body: String
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

	static func plainText(fromHTML html: String) -> String? {
		guard let data = html.data(using: .utf16),
			  let string = NSAttributedString(html: data, documentAttributes: nil) else {
			return nil
		}

		return string.string
	}

	static func relevantText(from text: String, version: String?, allowFirstSectionFallback: Bool) -> String? {
		let lines = text.components(separatedBy: .newlines).map {
			$0.trimmingCharacters(in: .whitespacesAndNewlines)
		}.filter { !$0.isEmpty }

		guard !lines.isEmpty else { return nil }

		let versionCandidates = Self.versionCandidates(from: version)
		var startIndex: Int?

		if !versionCandidates.isEmpty {
			startIndex = lines.firstIndex { line in
				versionCandidates.contains { version in
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
		let endIndex = lines[(startIndex + 1)...].firstIndex { line in
			Self.looksLikeReleaseBoundary(line) && !versionCandidates.contains { version in
				line.localizedCaseInsensitiveContains(version)
			}
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

		if let baseURL, let string = NSAttributedString(html: data, baseURL: baseURL, documentAttributes: nil) {
			return .success(string)
		}

		guard let string = NSAttributedString(html: data, documentAttributes: nil) else {
			return .failure(LatestError.releaseNotesUnavailable)
		}

		return .success(string)
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
		line.range(of: #"^#{1,6}\s*v?\d+(\.\d+){1,}"#, options: [.regularExpression, .caseInsensitive]) != nil ||
		line.range(of: #"^v?\d+(\.\d+){1,}(\s|$|-)"#, options: [.regularExpression, .caseInsensitive]) != nil ||
		line.range(of: #"^[A-Z][a-z]+ \d{1,2}, \d{4}"#, options: .regularExpression) != nil
	}

}

private extension String {

	var containsHTMLTag: Bool {
		range(of: #"<\s*/?\s*(html|body|p|br|div|span|ul|ol|li|h[1-6]|a|strong|em|table)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
	}

}
