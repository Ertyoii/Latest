//
//  ReleaseNotesProvider.swift
//  Latest
//
//  Created by Max Langer on 04.03.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import AppKit
import OSLog

private let releaseNotesLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "com.max-langer.Latest",
	category: "ReleaseNotes"
)
private let releaseNotesSignposter = OSSignposter(
	subsystem: Bundle.main.bundleIdentifier ?? "com.max-langer.Latest",
	category: "ReleaseNotesPerformance"
)

private let releaseNotesHTMLCache = ReleaseNotesHTMLCache()
private let releaseNotesGitHubCache = ReleaseNotesGitHubCache()

/// Handles release notes conversion and loading.
///
/// The object provides release notes in a uniform representation and caches remote contents for faster access.
@MainActor
class ReleaseNotesProvider {

	/// The return value, containing either the desired release notes, or an error if unavailable.
	typealias ReleaseNotes = Result<NSAttributedString, Error>
	typealias Completion = @MainActor (ReleaseNotes) -> Void
	typealias ResolvedCompletion = @MainActor (Result<ResolvedReleaseNotes, Error>) -> Void

	/// Initializes the provider.
	init() {
		let cache = NSCache<ReleaseNotesCacheKey, ResolvedReleaseNotesBox>()
		cache.countLimit = 128
		cache.totalCostLimit = 16 * 1_024 * 1_024
		self.cache = cache
	}

	private let pipeline = ReleaseNotesPipeline()

	/// Tracks the currently requested app.
	///
	/// Used to suppress completion calls from older requests.
	private var currentApp: App?

	/// Tracks the currently requested release notes operation.
	private var currentRequestID = UUID()

	/// Tracks URLSession-backed release note work so stale requests can be cancelled.
	private var currentReleaseNotesTask: Task<Void, Never>?

	/// Provides release notes for the given app.
	func releaseNotes(for app: App, with completion: @escaping Completion) {
		resolvedReleaseNotes(for: app) { result in
			completion(result.map(\.content))
		}
	}

	/// Provides the same UI content together with the source that actually won
	/// fallback selection and its resulting quality.
	func resolvedReleaseNotes(for app: App, with completion: @escaping ResolvedCompletion) {
		let requestID = UUID()
		currentApp = app
		currentRequestID = requestID
		currentReleaseNotesTask?.cancel()
		currentReleaseNotesTask = nil
		webContentLoader?.cancel()

		let cacheKey = ReleaseNotesCacheKey(app: app)
		if let releaseNotes = self.cache.object(forKey: cacheKey)?.value,
		   !Self.isEffectivelyEmpty(releaseNotes.content) {
			completion(.success(releaseNotes))
			return
		}

		self.loadReleaseNotes(for: app) { releaseNotes in
			let releaseNotes = Self.validated(releaseNotes)
			if case .success(let resolved) = releaseNotes {
				self.cache.setObject(
					ResolvedReleaseNotesBox(resolved),
					forKey: cacheKey,
					cost: resolved.content.length * 2
				)
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
	private var cache: NSCache<ReleaseNotesCacheKey, ResolvedReleaseNotesBox>

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

	private func loadReleaseNotes(for app: App, with completion: @escaping ResolvedCompletion) {
		let requestID = currentRequestID
		if let releaseNotes = app.releaseNotes {
			switch releaseNotes {
			case .html(let html):
				currentReleaseNotesTask = Task { [weak self] in
					guard let self else { return }
					let releaseNotes = await self.pipeline.resolve(
						ReleaseNotesCandidate(
							markup: html,
							baseURL: nil,
							provenance: releaseNotes.provenance,
							qualityHint: releaseNotes.qualityHint
						),
						for: ReleaseNotesContext(app: app)
					)
					guard !Task.isCancelled, self.isCurrentRequest(requestID, for: app) else { return }
					completion(releaseNotes)
				}
			case .genericMetadata(let html):
				currentReleaseNotesTask = Task { [weak self] in
					guard let self else { return }
					let releaseNotes = await self.pipeline.resolve(
						ReleaseNotesCandidate(
							markup: html,
							baseURL: nil,
							provenance: .homebrewMetadata,
							qualityHint: .genericMetadata
						),
						for: ReleaseNotesContext(app: app)
					)
					guard !Task.isCancelled, self.isCurrentRequest(requestID, for: app) else { return }
					completion(releaseNotes)
				}
			case .url(let url):
				self.releaseNotes(from: url, relevantVersion: app.remoteVersion?.versionNumber, requestID: requestID, with: completion)
			case .encoded(let data):
				let provenance = releaseNotes.provenance
				let quality = releaseNotes.qualityHint
				currentReleaseNotesTask = Task { [weak self] in
					guard let self else { return }
					let releaseNotes = await ReleaseNotesMarkup.attributedStringByPreparingOffMain(
						from: data,
						baseURL: nil,
						relevantVersion: app.remoteVersion?.versionNumber
					)
					guard !Task.isCancelled, self.isCurrentRequest(requestID, for: app) else { return }
					completion(releaseNotes.map {
						ResolvedReleaseNotes(
							content: $0,
							quality: quality,
							provenance: provenance
						)
					})
				}
			case .githubRelease(let apiURL, let fallbackHTML):
				currentReleaseNotesTask = Task { [weak self] in
					guard let self else { return }
					let releaseNotes = await self.githubReleaseNotes(from: apiURL, relevantVersion: app.remoteVersion?.versionNumber, fallbackHTML: fallbackHTML)
					guard !Task.isCancelled else { return }
					completion(releaseNotes)
				}
			case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML):
				self.changelogReleaseNotes(from: urls, versionPrefix: versionPrefix ?? app.remoteVersion?.versionNumber, allowsLatestFallback: allowsLatestFallback, fallbackHTML: fallbackHTML, requestID: requestID, with: completion)
			}
		} else if app.error != nil {
			// Update-check failures describe the scan, not the content pane. The
			// detail view should state that notes are unavailable instead of
			// presenting a long networking/update error as release-note content.
			completion(.failure(LatestError.releaseNotesUnavailable))
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

	private nonisolated static func validated(
		_ releaseNotes: Result<ResolvedReleaseNotes, Error>
	) -> Result<ResolvedReleaseNotes, Error> {
		switch releaseNotes {
		case .success(let resolved) where isEffectivelyEmpty(resolved.content):
			return .failure(LatestError.releaseNotesUnavailable)
		default:
			return releaseNotes
		}
	}

	private nonisolated static func isEffectivelyEmpty(_ text: NSAttributedString) -> Bool {
		text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}


	/// Fetches release notes from the given URL.
	private func releaseNotes(from url: URL, relevantVersion: String?, requestID: UUID, with completion: @escaping ResolvedCompletion) {
		currentReleaseNotesTask = Task { [weak self] in
			guard let self else { return }

			do {
				let html = try await Self.fetchHTML(from: url)
				let context = ReleaseNotesContext(
					appName: self.currentApp?.name ?? "",
					bundleIdentifier: self.currentApp?.bundleIdentifier ?? "",
					localVersion: self.currentApp?.version.versionNumber,
					remoteVersion: relevantVersion
				)
				let releaseNotes = await self.pipeline.resolve(
					ReleaseNotesCandidate(markup: html, baseURL: url, provenance: .remoteURL),
					for: context
				)
				guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }
				completion(releaseNotes)
				return
			} catch FetchHTMLError.unusableText {
				guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }
				releaseNotesLogger.info(
					"Rejected non-text release notes response from \(url.host ?? "unknown", privacy: .public)"
				)
				completion(.failure(LatestError.releaseNotesUnavailable))
				return
			} catch {
				guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }
				releaseNotesLogger.info(
					"Falling back to WebKit release notes loader for \(url.host ?? "unknown", privacy: .public)"
				)
				self.webReleaseNotes(from: url, relevantVersion: relevantVersion, requestID: requestID, with: completion)
			}
		}
	}

	private func webReleaseNotes(from url: URL, relevantVersion: String?, requestID: UUID, with completion: @escaping ResolvedCompletion) {
		activeWebContentLoader.load(from: url) { result in
			guard self.isCurrentRequest(requestID) else { return }

			switch result {
			case .success(let html):
				self.currentReleaseNotesTask?.cancel()
				self.currentReleaseNotesTask = Task { [weak self] in
					guard let self else { return }
					let releaseNotes = await ReleaseNotesMarkup.attributedStringByPreparingOffMain(
						from: html,
						baseURL: url,
						relevantVersion: relevantVersion
					)
					guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }
					self.webContentLoader?.cancel()
					completion(releaseNotes.map {
						ResolvedReleaseNotes(content: $0, quality: .genuine, provenance: .webKit)
					})
				}
			case .failure(let error):
				completion(.failure(error))
			}
		}
	}

	private func githubReleaseNotes(
		from url: URL,
		relevantVersion: String?,
		fallbackHTML: String?
	) async -> Result<ResolvedReleaseNotes, Error> {
		do {
			let data = try await Self.fetchGitHubReleaseData(from: url)
			let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
			if let releaseNotes = await Self.githubReleaseNotes(
				fromBody: release.body,
				title: release.name,
				baseURL: Self.githubReleaseWebURL(fromAPIURL: url),
				relevantVersion: relevantVersion
			) {
				return .success(releaseNotes)
			}

			if let releaseNotes = await Self.githubReleasePageNotes(fromAPIURL: url, relevantVersion: relevantVersion) {
				return .success(releaseNotes)
			}

			if let fallbackHTML {
				releaseNotesLogger.info(
					"Using fallback release notes HTML after GitHub release body was not useful for \(url.host ?? "unknown", privacy: .public)"
				)
				return await ReleaseNotesMarkup.attributedStringByPreparingOffMain(
					from: fallbackHTML,
					baseURL: nil,
					relevantVersion: relevantVersion
				).map {
					ResolvedReleaseNotes(content: $0, quality: .degraded, provenance: .bundledFallback)
				}
			}
			return .failure(LatestError.releaseNotesUnavailable)
		} catch GitHubReleaseFetchError.notFound {
			if let fallbackHTML {
				return await ReleaseNotesMarkup.attributedStringByPreparingOffMain(
					from: fallbackHTML,
					baseURL: nil,
					relevantVersion: relevantVersion
				).map {
					ResolvedReleaseNotes(content: $0, quality: .degraded, provenance: .bundledFallback)
				}
			}
			return .failure(LatestError.releaseNotesUnavailable)
		} catch {
			if let releaseNotes = await Self.githubReleasePageNotes(fromAPIURL: url, relevantVersion: relevantVersion) {
				return .success(releaseNotes)
			}

			if let fallbackHTML {
				releaseNotesLogger.info(
					"Using fallback release notes HTML after GitHub release fetch failed for \(url.host ?? "unknown", privacy: .public)"
				)
				return await ReleaseNotesMarkup.attributedStringByPreparingOffMain(
					from: fallbackHTML,
					baseURL: nil,
					relevantVersion: relevantVersion
				).map {
					ResolvedReleaseNotes(content: $0, quality: .degraded, provenance: .bundledFallback)
				}
			}
			return .failure(error)
		}
	}

	private static func githubReleaseNotes(fromBody body: String, title: String?, baseURL: URL?, relevantVersion: String?) async -> ResolvedReleaseNotes? {
		let body = deduplicating(title: title, in: body.trimmingCharacters(in: .whitespacesAndNewlines))
		if let releaseNotes = await githubReleaseNotes(fromUsefulMarkup: body, title: title, baseURL: baseURL, relevantVersion: relevantVersion) {
			return releaseNotes
		}

		return await linkedReleaseNotes(fromMarkup: body, baseURL: baseURL, relevantVersion: relevantVersion)
	}

	private static func githubReleasePageNotes(fromAPIURL apiURL: URL, relevantVersion: String?) async -> ResolvedReleaseNotes? {
		guard let webURL = githubReleaseWebURL(fromAPIURL: apiURL),
		      let html = try? await fetchHTML(from: webURL) else {
			return nil
		}
		let bodyHTML = await Task.detached(priority: .userInitiated) {
			githubReleaseBodyHTML(fromHTML: html)
		}.value
		guard let bodyHTML else { return nil }

		if let releaseNotes = await githubReleaseNotes(fromUsefulMarkup: bodyHTML, title: nil, baseURL: webURL, relevantVersion: relevantVersion) {
			return releaseNotes
		}

		return await linkedReleaseNotes(fromMarkup: bodyHTML, baseURL: webURL, relevantVersion: relevantVersion)
	}

	private static func githubReleaseNotes(fromUsefulMarkup markup: String, title: String?, baseURL: URL?, relevantVersion: String?) async -> ResolvedReleaseNotes? {
		guard let releaseNotes = await ReleaseNotesMarkup.githubAttributedStringByPreparingOffMain(
			from: markup,
			title: title,
			baseURL: baseURL,
			relevantVersion: relevantVersion
		) else { return nil }
		return try? releaseNotes.get().mapToResolved(quality: .genuine, provenance: .githubRelease)
	}

	private static func linkedReleaseNotes(fromMarkup markup: String, baseURL: URL?, relevantVersion: String?) async -> ResolvedReleaseNotes? {
		guard let linkedURL = ReleaseNotesMarkup.firstReleaseNotesURL(in: markup, baseURL: baseURL),
		      linkedURL != baseURL,
		      let linkedHTML = try? await fetchHTML(from: linkedURL) else {
			return nil
		}

		if let result = await ReleaseNotesMarkup.attributedStringFromChangelogByPreparingOffMain(
			fromHTML: linkedHTML,
			baseURL: linkedURL,
			relevantVersion: relevantVersion,
			allowFirstSectionFallback: true
		) {
			return try? result.get().mapToResolved(quality: .genuine, provenance: .changelog)
		}

		guard let releaseNotes = await ReleaseNotesMarkup.plainTextAttributedStringByPreparingOffMain(
			fromHTML: linkedHTML,
			baseURL: linkedURL,
			relevantVersion: relevantVersion
		) else { return nil }
		return try? releaseNotes.get().mapToResolved(quality: .genuine, provenance: .changelog)
	}

	private func changelogReleaseNotes(from urls: [URL], versionPrefix: String?, allowsLatestFallback: Bool, fallbackHTML: String?, requestID: UUID, with completion: @escaping ResolvedCompletion) {
		currentReleaseNotesTask = Task { [weak self] in
			guard let self else { return }

			if let content = await Self.fetchChangelogContent(from: urls, versionPrefix: versionPrefix, allowsLatestFallback: allowsLatestFallback) {
				let releaseNotes = await ReleaseNotesMarkup.attributedStringByPreparingOffMain(
					from: content.text,
					baseURL: content.baseURL,
					relevantVersion: versionPrefix
				)
				guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }
				completion(releaseNotes.map {
					ResolvedReleaseNotes(content: $0, quality: .genuine, provenance: .changelog)
				})
				return
			}

			guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }

			if let fallbackHTML {
				releaseNotesLogger.info("Using fallback release notes HTML after direct changelog fetch failed")
				let releaseNotes = await ReleaseNotesMarkup.attributedStringByPreparingOffMain(
					from: fallbackHTML,
					baseURL: nil,
					relevantVersion: versionPrefix
				)
				guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }
				completion(releaseNotes.map {
					ResolvedReleaseNotes(content: $0, quality: .degraded, provenance: .bundledFallback)
				})
				return
			}

			releaseNotesLogger.info("Falling back to WebKit changelog loader after direct changelog fetch failed")
			self.webChangelogReleaseNotes(from: urls, versionPrefix: versionPrefix, allowsLatestFallback: allowsLatestFallback, requestID: requestID, with: completion)
		}
	}

	private func webChangelogReleaseNotes(from urls: [URL], versionPrefix: String?, allowsLatestFallback: Bool, requestID: UUID, with completion: @escaping ResolvedCompletion) {
		var remainingURLs = urls
		var activeAttemptID = UUID()
		var didComplete = false

		func finish(_ releaseNotes: Result<ResolvedReleaseNotes, Error>) {
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
					self.currentReleaseNotesTask?.cancel()
					self.currentReleaseNotesTask = Task { [weak self] in
						guard let self else { return }
						let releaseNotes = await ReleaseNotesMarkup.attributedStringFromChangelogByPreparingOffMain(
							fromHTML: html,
							baseURL: url,
							relevantVersion: versionPrefix,
							allowFirstSectionFallback: allowsLatestFallback
						)
						guard !Task.isCancelled,
						      self.isCurrentRequest(requestID),
						      activeAttemptID == attemptID,
						      !didComplete else { return }
						if let releaseNotes {
							finish(releaseNotes.map {
								ResolvedReleaseNotes(content: $0, quality: .genuine, provenance: .webKit)
							})
						} else {
							loadNext()
						}
					}
				case .failure:
					self.currentReleaseNotesTask?.cancel()
					loadNext()
				}
			}
		}

		loadNext()
	}

	private nonisolated static func fetchChangelogContent(from urls: [URL], versionPrefix: String?, allowsLatestFallback: Bool) async -> ChangelogContent? {
		await withTaskGroup(of: ChangelogContent?.self) { group in
			let maximumConcurrentFetches = 2
			var remainingURLs = ArraySlice(urls)
			var activeFetches = 0

			func addNextFetch() {
				guard let url = remainingURLs.popFirst() else { return }
				activeFetches += 1
				group.addTask {
					guard !Task.isCancelled,
						  let html = try? await Self.fetchHTML(from: url) else {
						return nil
					}

					return await Self.changelogContent(fromHTML: html, url: url, versionPrefix: versionPrefix, allowsLatestFallback: allowsLatestFallback)
				}
			}

			while activeFetches < maximumConcurrentFetches, !remainingURLs.isEmpty {
				addNextFetch()
			}

			while activeFetches > 0 {
				guard let content = await group.next() else { break }
				activeFetches -= 1
				if let content {
					group.cancelAll()
					return content
				}
				addNextFetch()
			}

			return nil
		}
	}

	private nonisolated static func changelogContent(fromHTML html: String, url: URL, versionPrefix: String?, allowsLatestFallback: Bool) async -> ChangelogContent? {
		if ReleaseNotesMarkup.usesSourceSpecificTextExtraction(for: url),
		   let text = ReleaseNotesMarkup.relevantChangelogText(fromHTML: html, version: versionPrefix, pageURL: url, allowFirstSectionFallback: allowsLatestFallback) {
			return ChangelogContent(text: text, baseURL: url)
		}

		if let releaseHTML = ReleaseNotesMarkup.releaseContentHTML(fromHTML: html, version: versionPrefix, pageURL: url) {
			return ChangelogContent(text: releaseHTML, baseURL: url)
		}

		if url.host?.localizedCaseInsensitiveContains("chromereleases.googleblog.com") == true,
		   let text = ReleaseNotesMarkup.relevantChangelogText(fromHTML: html, version: versionPrefix, pageURL: url, allowFirstSectionFallback: allowsLatestFallback) {
			return ChangelogContent(text: text, baseURL: url)
		}

		if let linkedURL = ReleaseNotesMarkup.linkedChangelogURL(fromHTML: html, version: versionPrefix, pageURL: url),
		   linkedURL != url,
		   let linkedHTML = try? await Self.fetchHTML(from: linkedURL) {
			if let releaseHTML = ReleaseNotesMarkup.releaseContentHTML(fromHTML: linkedHTML, version: versionPrefix, pageURL: linkedURL) {
				return ChangelogContent(text: releaseHTML, baseURL: linkedURL)
			}

			if let text = ReleaseNotesMarkup.relevantChangelogText(fromHTML: linkedHTML, version: versionPrefix, pageURL: linkedURL, allowFirstSectionFallback: true) {
				return ChangelogContent(text: text, baseURL: linkedURL)
			}

			if let text = ReleaseNotesMarkup.plainText(fromHTML: linkedHTML),
			   ReleaseNotesMarkup.isUsefulReleaseNotesText(text, relevantVersion: versionPrefix) {
				return ChangelogContent(text: text, baseURL: linkedURL)
			}
		}

		if let text = ReleaseNotesMarkup.relevantChangelogText(fromHTML: html, version: versionPrefix, pageURL: url, allowFirstSectionFallback: allowsLatestFallback) {
			return ChangelogContent(text: text, baseURL: url)
		}

		return nil
	}

	private nonisolated static func fetchHTML(from url: URL) async throws -> String {
		if isLikelyDownloadURL(url) {
			throw FetchHTMLError.unusableText
		}

		return try await releaseNotesHTMLCache.html(for: url) {
			try await Self.fetchFreshHTML(from: url)
		}
	}

	private nonisolated static func fetchFreshHTML(from url: URL) async throws -> String {
		do {
			return try await ReleaseNotesFetcher().fetchMarkup(from: url)
		} catch is ReleaseNotesFetchError {
			throw FetchHTMLError.unusableText
		}
	}

	private nonisolated static func fetchGitHubReleaseData(from url: URL) async throws -> Data {
		try await releaseNotesGitHubCache.data(for: url) {
			var request = URLRequest(url: url)
			request.cachePolicy = .useProtocolCachePolicy
			request.timeoutInterval = 6
			request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
			request.setValue("Latest", forHTTPHeaderField: "User-Agent")

			let (data, response) = try await URLSession.shared.data(for: request)
			if let response = response as? HTTPURLResponse {
				if response.statusCode == 404 {
					throw GitHubReleaseFetchError.notFound
				}
				if !(200..<300).contains(response.statusCode) {
					throw FetchHTMLError.unusableText
				}
			}

			return data
		}
	}

}

private actor ReleaseNotesGitHubCache {
	private struct Entry {
		let data: Data
		let expiresAt: Date
		var lastAccessedAt: Date
	}

	private var entries = [URL: Entry]()
	private var inFlightTasks = [URL: Task<Data, Error>]()
	private var storedBytes = 0
	private let lifetime: TimeInterval = 15 * 60
	private let maximumEntryCount = 128
	private let maximumStoredBytes = 8 * 1_024 * 1_024

	func data(for url: URL, loader: @escaping @Sendable () async throws -> Data) async throws -> Data {
		let now = Date()
		if var entry = entries[url], entry.expiresAt > now {
			entry.lastAccessedAt = now
			entries[url] = entry
			return entry.data
		}
		if let entry = entries.removeValue(forKey: url) {
			storedBytes -= entry.data.count
		}
		if let task = inFlightTasks[url] {
			return try await task.value
		}

		let task = Task { try await loader() }
		inFlightTasks[url] = task
		defer { inFlightTasks[url] = nil }
		let data = try await task.value
		entries[url] = Entry(data: data, expiresAt: now.addingTimeInterval(lifetime), lastAccessedAt: now)
		storedBytes += data.count
		evictIfNeeded()
		return data
	}

	private func evictIfNeeded() {
		while entries.count > maximumEntryCount || storedBytes > maximumStoredBytes {
			guard let oldest = entries.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt }) else {
				return
			}
			storedBytes -= oldest.value.data.count
			entries[oldest.key] = nil
		}
	}
}

private actor ReleaseNotesHTMLCache {

	private struct Entry {
		let value: Value
		let expiresAt: Date
		var lastAccessedAt: Date
		let cost: Int
	}

	private enum Value {
		case success(String)
		case failure(FetchHTMLError)

		func get() throws -> String {
			switch self {
			case .success(let html):
				return html
			case .failure(let error):
				throw error
			}
		}

		var cost: Int {
			switch self {
			case .success(let html):
				return html.utf8.count
			case .failure:
				return 0
			}
		}
	}

	private var entries = [URL: Entry]()
	private var inFlightTasks = [URL: Task<String, Error>]()
	private var storedHTMLBytes = 0
	private let successfulResponseLifetime: TimeInterval = 30 * 60
	private let failedResponseLifetime: TimeInterval = 5 * 60
	private let maximumEntryCount = 128
	private let maximumStoredHTMLBytes = 8 * 1_024 * 1_024

	func html(for url: URL, loader: @escaping @Sendable () async throws -> String) async throws -> String {
		let now = Date()
		pruneExpiredEntries(at: now)
		if var entry = entries[url] {
			entry.lastAccessedAt = now
			entries[url] = entry
			return try entry.value.get()
		}

		if let task = inFlightTasks[url] {
			return try await task.value
		}

		let task = Task {
			try await loader()
		}
		inFlightTasks[url] = task

		do {
			let html = try await task.value
			store(.success(html), for: url, lifetime: successfulResponseLifetime)
			inFlightTasks[url] = nil
			return html
		} catch FetchHTMLError.unusableText {
			store(.failure(.unusableText), for: url, lifetime: failedResponseLifetime)
			inFlightTasks[url] = nil
			throw FetchHTMLError.unusableText
		} catch {
			store(.failure(.fetchFailed), for: url, lifetime: failedResponseLifetime)
			inFlightTasks[url] = nil
			throw error
		}
	}

	private func store(_ value: Value, for url: URL, lifetime: TimeInterval) {
		let now = Date()
		pruneExpiredEntries(at: now)
		removeEntry(for: url)

		let cost = value.cost
		guard cost <= maximumStoredHTMLBytes else { return }
		entries[url] = Entry(
			value: value,
			expiresAt: now.addingTimeInterval(lifetime),
			lastAccessedAt: now,
			cost: cost
		)
		storedHTMLBytes += cost
		trimToLimits()
	}

	private func pruneExpiredEntries(at date: Date) {
		let expiredURLs = entries.compactMap { url, entry in
			entry.expiresAt <= date ? url : nil
		}
		for url in expiredURLs {
			removeEntry(for: url)
		}
	}

	private func trimToLimits() {
		while entries.count > maximumEntryCount || storedHTMLBytes > maximumStoredHTMLBytes {
			guard let leastRecentlyUsedURL = entries.min(by: {
				$0.value.lastAccessedAt < $1.value.lastAccessedAt
			})?.key else { return }
			removeEntry(for: leastRecentlyUsedURL)
		}
	}

	private func removeEntry(for url: URL) {
		guard let entry = entries.removeValue(forKey: url) else { return }
		storedHTMLBytes -= entry.cost
	}

}

private enum ReleaseNotesProviderConstants {
	static let downloadExtensions: Set<String> = [
		"7z", "bz2", "dmg", "exe", "gz", "msi", "pkg", "rar", "tbz", "tgz", "xip", "xz", "zip"
	]
}

private enum FetchHTMLError: Error {
	case unusableText
	case fetchFailed
}

private enum GitHubReleaseFetchError: Error {
	case notFound
}

extension ReleaseNotesProvider {

	nonisolated static func githubReleaseWebURL(fromAPIURL apiURL: URL) -> URL? {
		guard apiURL.host?.caseInsensitiveCompare("api.github.com") == .orderedSame else {
			return nil
		}

		let components = apiURL.pathComponents
		guard components.count >= 6,
		      components[1] == "repos",
		      components[4] == "releases" else {
			return nil
		}

		let owner = components[2]
		let repository = components[3]
		if components[5] == "latest" {
			return URL(string: "https://github.com/\(owner)/\(repository)/releases/latest")
		}

		guard components.count >= 7, components[5] == "tags" else { return nil }
		let tag = components[6]
		return URL(string: "https://github.com/\(owner)/\(repository)/releases/tag/\(tag)")
	}

	nonisolated static func githubReleaseBodyHTML(fromHTML html: String) -> String? {
		guard let markerRange = html.range(of: #"data-test-selector="body-content""#) ??
				html.range(of: #"data-test-selector='body-content'"#) else {
			return nil
		}

		guard let openingDivRange = html[..<markerRange.lowerBound].range(of: "<div", options: [.backwards, .caseInsensitive]),
		      let openingTagEndRange = html.range(of: ">", range: openingDivRange.lowerBound..<html.endIndex) else {
			return nil
		}

		var depth = 1
		var searchStart = openingTagEndRange.upperBound
		while searchStart < html.endIndex {
			let nextOpeningDiv = html.range(of: "<div", options: .caseInsensitive, range: searchStart..<html.endIndex)
			let nextClosingDiv = html.range(of: "</div>", options: .caseInsensitive, range: searchStart..<html.endIndex)

			guard let closingDiv = nextClosingDiv else {
				return nil
			}

			if let openingDiv = nextOpeningDiv, openingDiv.lowerBound < closingDiv.lowerBound {
				depth += 1
				searchStart = openingDiv.upperBound
				continue
			}

			depth -= 1
			if depth == 0 {
				return String(html[openingTagEndRange.upperBound..<closingDiv.lowerBound])
					.trimmingCharacters(in: .whitespacesAndNewlines)
			}

			searchStart = closingDiv.upperBound
		}

		return nil
	}

}

private extension ReleaseNotesProvider {

	nonisolated static func isLikelyDownloadURL(_ url: URL) -> Bool {
		return ReleaseNotesProviderConstants.downloadExtensions.contains(url.pathExtension.lowercased())
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

}

private struct GitHubRelease: Decodable {
	let name: String?
	let body: String
}

private struct ChangelogContent: Sendable {
	let text: String
	let baseURL: URL
}

private struct StructuredArticle: Decodable {
	let articleBody: String?
}

private final class ResolvedReleaseNotesBox: NSObject {
	let value: ResolvedReleaseNotes

	init(_ value: ResolvedReleaseNotes) {
		self.value = value
	}
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
		case .genericMetadata(let string):
			return "homebrew-metadata:\(string.hashValue)"
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

	private enum Regexes {
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

	private static func replacingMatches(
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

	private static let genericReleaseNoteWords: Set<String> = [
		"changelog", "changes", "details", "history", "latest", "link", "links",
		"more", "note", "notes", "public", "recent", "release", "releases",
		"version", "versions", "view", "whats", "what"
	]
	private static let releaseSentenceBodyVerbs: Set<String> = [
		"adds", "allows", "applies", "brings", "changes", "fixes",
		"improves", "introduces", "lets", "makes", "resolves", "updates"
	]
	private static let repeatedHeadingBodyVerbs: Set<String> = [
		"adds", "allows", "applies", "are", "brings", "can", "changes",
		"fixes", "has", "have", "improves", "introduces", "is", "lets",
		"makes", "now", "updates", "uses", "was", "were", "will"
	]
	private static let versionNavigationWords: Set<String> = [
		"versions", "version", "channel", "stable", "preview", "releases"
	]
	private static let zedReleaseChromeLines: Set<String> = [
		"linux", "loading...", "loading…", "macos", "windows"
	]
	private static let webPageChromeReleaseTerms = [
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
			Self.isUsefulZedReleaseArticleText(normalizedMarkup)
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
			host.contains("zed.dev") ||
			host.contains("zoom.com")
	}

	static func relevantChangelogText(fromHTML html: String, version: String?, pageURL: URL, allowFirstSectionFallback: Bool) -> String? {
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
		return Self.releaseSentenceBodyVerbs.contains(Self.normalizedToken(firstWord))
	}

	private static func capitalizingFirstLetter(_ text: String) -> String {
		guard let first = text.first else { return text }
		return first.uppercased() + text.dropFirst()
	}

	private static func normalizedPlainText(_ text: String) -> String {
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

	private static func cleaningInlineMarkdown(in text: String) -> String {
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

		if let string = Self.attributedString(fromHTMLData: data, baseURL: baseURL) {
			return .success(string)
		}

		guard let plainText = Self.plainText(fromHTML: html),
		      Self.isUsefulReleaseNotesText(plainText) else {
			return .failure(LatestError.releaseNotesUnavailable)
		}
		return .success(Self.attributedString(fromPlainText: plainText))
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

	private static func isUsefulZedReleaseArticleText(_ text: String) -> Bool {
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

private extension String {

	var containsHTMLTag: Bool {
		range(of: #"<\s*/?\s*(html|body|p|br|div|span|ul|ol|li|h[1-6]|a|strong|em|table)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
	}

}

private extension NSAttributedString {
	func mapToResolved(
		quality: ReleaseNotesQuality,
		provenance: ReleaseNotesProvenance
	) -> ResolvedReleaseNotes {
		ResolvedReleaseNotes(content: self, quality: quality, provenance: provenance)
	}
}
