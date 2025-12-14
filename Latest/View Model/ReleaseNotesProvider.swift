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
	
	/// A wrapper to transfer NSAttributedString across concurrency boundaries.
	struct ReleaseNotesContent: @unchecked Sendable {
		let attributedString: NSAttributedString
	}
	
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
					completion(self.releaseNotes(from: html, baseURL: nil))
				case .url(let url):
					self.releaseNotes(from: url, with: completion)
				case .encoded(let data):
					completion(self.releaseNotes(from: data))
			}
		} else if let error = app.error {
			completion(.failure(error))
		} else {
			completion(.failure(LatestError.releaseNotesUnavailable))
		}
	}
	
	func releaseNotes(for app: App) -> AsyncThrowingStream<ReleaseNotesContent, Error> {
		if let releaseNotes = app.releaseNotes {
			switch releaseNotes {
			case .html(let html):
				// Parse on MainActor (current context)
				let result = self.releaseNotes(from: html, baseURL: nil)
				return AsyncThrowingStream { continuation in
					switch result {
					case .success(let str):
						continuation.yield(ReleaseNotesContent(attributedString: str))
					case .failure(let err):
						continuation.finish(throwing: err)
					}
					continuation.finish()
				}
			case .url(let url):
				return self.releaseNotes(from: url)
			case .encoded(let data):
				// Parse on MainActor (current context)
				let result = self.releaseNotes(from: data)
				return AsyncThrowingStream { continuation in
					switch result {
					case .success(let str):
						continuation.yield(ReleaseNotesContent(attributedString: str))
					case .failure(let err):
						continuation.finish(throwing: err)
					}
					continuation.finish()
				}
			}
		} else if let error = app.error {
			return AsyncThrowingStream { $0.finish(throwing: error) }
		} else {
			return AsyncThrowingStream { $0.finish(throwing: LatestError.releaseNotesUnavailable) }
		}
	}
	
	
	/// Fetches release notes from the given URL.
	private func releaseNotes(from url: URL, with completion: @escaping (ReleaseNotes) -> Void) {
		Task { @MainActor in
			do {
				for try await content in self.releaseNotes(from: url) {
					completion(.success(content.attributedString))
					// We only need the first result for the completion handler version
					break
				}
			} catch {
				completion(.failure(error))
			}
		}
	}
	
	/// Fetches release notes from the given URL as stream.
	private func releaseNotes(from url: URL) -> AsyncThrowingStream<ReleaseNotesContent, Error> {
		if let github = GitHubReleaseRequest.from(url: url) {
			return self.releaseNotes(fromGitHub: github)
		}
		
		let upstream = webContentLoader.events(for: url)
		return AsyncThrowingStream { continuation in
			Task { @MainActor in
				do {
					for try await html in upstream {
						let result = self.releaseNotes(from: html, baseURL: url)
						switch result {
						case .success(let string):
							continuation.yield(ReleaseNotesContent(attributedString: string))
						case .failure(let error):
							continuation.finish(throwing: error)
							return
						}
					}
					continuation.finish()
				} catch {
					continuation.finish(throwing: error)
				}
			}
		}
	}
	
	private func releaseNotes(fromGitHub request: GitHubReleaseRequest) -> AsyncThrowingStream<ReleaseNotesContent, Error> {
		return AsyncThrowingStream { continuation in
			Task { @MainActor in
				do {
					let release = try await GitHubAPI.fetchRelease(request: request)
					
					let title = release.name?.trimmingCharacters(in: .whitespacesAndNewlines)
					let tag = release.tagName?.trimmingCharacters(in: .whitespacesAndNewlines)
					
					let header: String = {
						switch (title, tag) {
						case (nil, nil):
							return ""
						case (let t?, nil):
							return t
						case (nil, let t?):
							return t
						case (let a?, let b?) where a == b:
							return a
						case (let a?, let b?):
							return "\(a) · \(b)"
						}
					}()
					
					let bodyHTML: String
					if let rendered = release.bodyHTML, !rendered.isEmpty {
						bodyHTML = Self.normalizeGitHubBodyHTML(rendered)
					} else if let body = release.body, !body.isEmpty {
						bodyHTML = "<pre style=\"white-space: pre-wrap; font-family: -apple-system; font-size: 13px;\">\(Self.escapeHTML(body))</pre>"
					} else {
						throw LatestError.releaseNotesUnavailable
					}
					
					let linkHTML: String = if let url = release.htmlURL?.absoluteString {
						"<p><a href=\"\(Self.escapeHTML(url))\">View on GitHub</a></p>"
					} else {
						""
					}
					
					let headerHTML: String = header.isEmpty ? "" : "<h3>\(Self.escapeHTML(header))</h3>"
					let styleHTML = """
					<style>
					  :root { color-scheme: light dark; }
					  body { font-family: -apple-system; font-size: 13px; line-height: 1.4; margin: 0; }
					  h3 { margin: 0 0 10px 0; font-size: 15px; font-weight: 600; }
					  p { margin: 8px 0; }
					  ul, ol { margin: 8px 0 8px 18px; padding: 0; }
					  li { margin: 4px 0; }
					  pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
					  pre { background: color-mix(in srgb, currentColor 6%, transparent); padding: 10px; border-radius: 8px; overflow-wrap: anywhere; }
					  a { text-decoration: none; }
					</style>
					"""
					let html = """
					<html>
					  <head>
					    <meta name="viewport" content="width=device-width, initial-scale=1.0">
					    \(styleHTML)
					  </head>
					  <body>
					    \(headerHTML)
					    \(bodyHTML)
					    \(linkHTML)
					  </body>
					</html>
					"""
					
					let result = self.releaseNotes(from: html, baseURL: nil)
					switch result {
					case .success(let string):
						continuation.yield(ReleaseNotesContent(attributedString: string))
						continuation.finish()
					case .failure(let error):
						continuation.finish(throwing: error)
					}
				} catch {
					continuation.finish(throwing: error)
				}
			}
		}
	}
	
	
	/// Returns rich text from the given HTML string.
	private func releaseNotes(from html: String, baseURL: URL?) -> ReleaseNotes {
		let normalizedHTML = Self.normalizeHTMLForAttributedString(html)
		
		guard let data = normalizedHTML.data(using: .utf16) else {
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

	/// Extracts release notes from the given data.
	private func releaseNotes(from data: Data) -> ReleaseNotes {
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

}

private extension ReleaseNotesProvider {
	static func escapeHTML(_ string: String) -> String {
		var escaped = string
		escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
		escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
		escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
		escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
		return escaped
	}
	
	static func normalizeHTMLForAttributedString(_ html: String) -> String {
		// Only touch HTML that contains lists; this avoids unexpected changes for simple release notes.
		guard html.range(of: "<li", options: [.caseInsensitive]) != nil else { return html }
		
		var normalized = html
		
		// Normalize paragraph-based list items.
		normalized = normalized.replacingOccurrences(
			of: "<li\\s*>\\s*<p\\s*>",
			with: "<li>",
			options: [.regularExpression, .caseInsensitive]
		)
		
		normalized = normalized.replacingOccurrences(
			of: "</p\\s*>\\s*</li\\s*>",
			with: "</li>",
			options: [.regularExpression, .caseInsensitive]
		)
		
		normalized = normalized.replacingOccurrences(
			of: "</p\\s*>\\s*<p\\s*>",
			with: "<br>",
			options: [.regularExpression, .caseInsensitive]
		)
		
		// Flatten all HTML lists into bullet paragraphs:
		// - <ul>/<ol> are removed
		// - <li> becomes <p>• …</p>
		//
		// This keeps links intact while avoiding list indentation/bullet duplication issues in
		// NSAttributedString's HTML importer.
		normalized = normalized.replacingOccurrences(
			of: "<(ul|ol)(\\s+[^>]*)?>",
			with: "",
			options: [.regularExpression, .caseInsensitive]
		)
		normalized = normalized.replacingOccurrences(
			of: "</(ul|ol)\\s*>",
			with: "",
			options: [.regularExpression, .caseInsensitive]
		)
		normalized = normalized.replacingOccurrences(
			of: "<li(\\s+[^>]*)?>\\s*",
			with: "<p>• ",
			options: [.regularExpression, .caseInsensitive]
		)
		normalized = normalized.replacingOccurrences(
			of: "</li\\s*>",
			with: "</p>",
			options: [.regularExpression, .caseInsensitive]
		)
		
		// Drop empty paragraphs that can lead to odd spacing.
		normalized = normalized.replacingOccurrences(
			of: "<p\\s*>\\s*</p\\s*>",
			with: "",
			options: [.regularExpression, .caseInsensitive]
		)
		
		return normalized
	}
	
	static func normalizeGitHubBodyHTML(_ html: String) -> String {
		// GitHub renders Markdown list items as <li><p>…</p><p>…</p></li> which often looks like multiple bullets in
		// NSAttributedString's HTML renderer. Flatten paragraphs inside list items, then render lists as plain bullet
		// paragraphs to avoid the list layout quirks of the HTML renderer.
		return normalizeHTMLForAttributedString(html)
	}
}

private struct GitHubReleaseRequest: Sendable {
	let owner: String
	let repo: String
	let tag: String?
	
	var apiURL: URL {
		if let tag, !tag.isEmpty {
			return URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(tag)")!
		}
		return URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
	}
	
	static func from(url: URL) -> GitHubReleaseRequest? {
		guard (url.host ?? "").lowercased() == "github.com" else { return nil }
		
		let components = url.pathComponents.filter { $0 != "/" }
		guard components.count >= 3 else { return nil }
		
		// Expect /<owner>/<repo>/releases...
		let owner = components[0]
		let repo = components[1]
		guard !owner.isEmpty, !repo.isEmpty else { return nil }
		guard components[2] == "releases" else { return nil }
		
		var tag: String? = nil
		if components.count >= 5, components[3] == "tag" {
			tag = components[4]
		}
		
		return GitHubReleaseRequest(owner: owner, repo: repo, tag: tag)
	}
}

private enum GitHubAPI {
	struct Release: Decodable {
		let name: String?
		let tagName: String?
		let body: String?
		let bodyHTML: String?
		let htmlURL: URL?
		
		enum CodingKeys: String, CodingKey {
			case name
			case tagName = "tag_name"
			case body
			case bodyHTML = "body_html"
			case htmlURL = "html_url"
		}
	}
	
	static func fetchRelease(request: GitHubReleaseRequest) async throws -> Release {
		var requestURL = request.apiURL
		
		func fetch(url: URL) async throws -> (Release, HTTPURLResponse) {
			var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
			req.setValue("application/vnd.github.v3.html+json", forHTTPHeaderField: "Accept")
			req.setValue("Latest", forHTTPHeaderField: "User-Agent")
			
			let (data, response) = try await URLSession.shared.data(for: req)
			guard let http = response as? HTTPURLResponse else { throw LatestError.releaseNotesUnavailable }
			let release = try JSONDecoder().decode(Release.self, from: data)
			return (release, http)
		}
		
		do {
			let (release, http) = try await fetch(url: requestURL)
			guard (200..<300).contains(http.statusCode) else { throw LatestError.releaseNotesUnavailable }
			return release
		} catch {
			// If the tag lookup failed (e.g. tag not found), try latest as fallback.
			if request.tag != nil {
				requestURL = URL(string: "https://api.github.com/repos/\(request.owner)/\(request.repo)/releases/latest")!
				let (release, http) = try await fetch(url: requestURL)
				guard (200..<300).contains(http.statusCode) else { throw LatestError.releaseNotesUnavailable }
				return release
			}
			throw error
		}
	}
}
