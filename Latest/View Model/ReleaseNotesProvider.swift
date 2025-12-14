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
	
	
	/// Returns rich text from the given HTML string.
	private func releaseNotes(from html: String, baseURL: URL?) -> ReleaseNotes {
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
