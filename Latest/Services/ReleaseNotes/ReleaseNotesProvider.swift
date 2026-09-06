//
//  ReleaseNotesProvider.swift
//  Latest
//
//  Created by Max Langer on 04.03.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-29.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import CryptoKit
import OSLog

let releaseNotesLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "com.max-langer.Latest",
  category: "ReleaseNotes"
)
let releaseNotesSignposter = OSSignposter(
  subsystem: Bundle.main.bundleIdentifier ?? "com.max-langer.Latest",
  category: "ReleaseNotesPerformance"
)

private let releaseNotesHTMLCache = ReleaseNotesHTMLCache()
private let releaseNotesGitHubCache = ReleaseNotesGitHubCache()
private let releaseNotesPersistentCache = ReleaseNotesPersistentCache()

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
    if app.error != nil, app.releaseNotes == nil {
      completion(.failure(LatestError.releaseNotesUnavailable))
      return
    }

    let cacheKey = ReleaseNotesCacheKey(app: app)
    if let releaseNotes = self.cache.object(forKey: cacheKey)?.value,
      !Self.isEffectivelyEmpty(releaseNotes.content)
    {
      completion(.success(releaseNotes))
      return
    }

    let finish: ResolvedCompletion = { releaseNotes in
      let releaseNotes = Self.validated(releaseNotes)
      if case .success(let resolved) = releaseNotes {
        self.cache.setObject(
          ResolvedReleaseNotesBox(resolved),
          forKey: cacheKey,
          cost: resolved.content.length * 2
        )
        if let payload = ReleaseNotesPersistentCache.payload(from: resolved) {
          Task {
            await releaseNotesPersistentCache.store(payload, forKey: cacheKey.stableIdentifier)
          }
        }
      }

      /// Release notes may be returned late or updated while another app was already requested. Don't forward this update, just cache in case of success.
      guard self.isCurrentRequest(requestID, for: app) else { return }

      completion(releaseNotes)
    }

    currentReleaseNotesTask = Task { [weak self] in
      guard let self else { return }
      if let payload = await releaseNotesPersistentCache.payload(forKey: cacheKey.stableIdentifier),
        let resolved = ReleaseNotesPersistentCache.resolvedReleaseNotes(from: payload)
      {
        guard !Task.isCancelled, self.isCurrentRequest(requestID, for: app) else { return }
        finish(.success(resolved))
        return
      }

      guard !Task.isCancelled, self.isCurrentRequest(requestID, for: app) else { return }
      self.loadReleaseNotes(for: app, with: finish)
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
        self.releaseNotes(
          from: url, relevantVersion: app.remoteVersion?.versionNumber, requestID: requestID,
          with: completion)
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
          completion(
            releaseNotes.map {
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
          let releaseNotes = await self.githubReleaseNotes(
            from: apiURL, relevantVersion: app.remoteVersion?.versionNumber,
            fallbackHTML: fallbackHTML)
          guard !Task.isCancelled else { return }
          completion(releaseNotes)
        }
      case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML):
        self.changelogReleaseNotes(
          from: urls, versionPrefix: versionPrefix ?? app.remoteVersion?.versionNumber,
          allowsLatestFallback: allowsLatestFallback, fallbackHTML: fallbackHTML,
          requestID: requestID, with: completion)
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
  private func releaseNotes(
    from url: URL, relevantVersion: String?, requestID: UUID,
    with completion: @escaping ResolvedCompletion
  ) {
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
        self.webReleaseNotes(
          from: url, relevantVersion: relevantVersion, requestID: requestID, with: completion)
      }
    }
  }

  private func webReleaseNotes(
    from url: URL, relevantVersion: String?, requestID: UUID,
    with completion: @escaping ResolvedCompletion
  ) {
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
          completion(
            releaseNotes.map {
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

      if let releaseNotes = await Self.githubReleasePageNotes(
        fromAPIURL: url, relevantVersion: relevantVersion)
      {
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
      if let releaseNotes = await Self.githubReleasePageNotes(
        fromAPIURL: url, relevantVersion: relevantVersion)
      {
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

  private static func githubReleaseNotes(
    fromBody body: String, title: String?, baseURL: URL?, relevantVersion: String?
  ) async -> ResolvedReleaseNotes? {
    let body = deduplicating(title: title, in: body.trimmingCharacters(in: .whitespacesAndNewlines))
    if let releaseNotes = await githubReleaseNotes(
      fromUsefulMarkup: body, title: title, baseURL: baseURL, relevantVersion: relevantVersion)
    {
      return releaseNotes
    }

    return await linkedReleaseNotes(
      fromMarkup: body, baseURL: baseURL, relevantVersion: relevantVersion)
  }

  private static func githubReleasePageNotes(fromAPIURL apiURL: URL, relevantVersion: String?) async
    -> ResolvedReleaseNotes?
  {
    guard let webURL = githubReleaseWebURL(fromAPIURL: apiURL),
      let html = try? await fetchHTML(from: webURL)
    else {
      return nil
    }
    let bodyHTML = await Task.detached(priority: .userInitiated) {
      githubReleaseBodyHTML(fromHTML: html)
    }.value
    guard let bodyHTML else { return nil }

    if let releaseNotes = await githubReleaseNotes(
      fromUsefulMarkup: bodyHTML, title: nil, baseURL: webURL, relevantVersion: relevantVersion)
    {
      return releaseNotes
    }

    return await linkedReleaseNotes(
      fromMarkup: bodyHTML, baseURL: webURL, relevantVersion: relevantVersion)
  }

  private static func githubReleaseNotes(
    fromUsefulMarkup markup: String, title: String?, baseURL: URL?, relevantVersion: String?
  ) async -> ResolvedReleaseNotes? {
    guard
      let releaseNotes = await ReleaseNotesMarkup.githubAttributedStringByPreparingOffMain(
        from: markup,
        title: title,
        baseURL: baseURL,
        relevantVersion: relevantVersion
      )
    else { return nil }
    return try? releaseNotes.get().mapToResolved(quality: .genuine, provenance: .githubRelease)
  }

  private static func linkedReleaseNotes(
    fromMarkup markup: String, baseURL: URL?, relevantVersion: String?
  ) async -> ResolvedReleaseNotes? {
    guard let linkedURL = ReleaseNotesMarkup.firstReleaseNotesURL(in: markup, baseURL: baseURL),
      linkedURL != baseURL,
      let linkedHTML = try? await fetchHTML(from: linkedURL)
    else {
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

    guard
      let releaseNotes = await ReleaseNotesMarkup.plainTextAttributedStringByPreparingOffMain(
        fromHTML: linkedHTML,
        baseURL: linkedURL,
        relevantVersion: relevantVersion
      )
    else { return nil }
    return try? releaseNotes.get().mapToResolved(quality: .genuine, provenance: .changelog)
  }

  private func changelogReleaseNotes(
    from urls: [URL], versionPrefix: String?, allowsLatestFallback: Bool, fallbackHTML: String?,
    requestID: UUID, with completion: @escaping ResolvedCompletion
  ) {
    currentReleaseNotesTask = Task { [weak self] in
      guard let self else { return }

      if let content = await Self.fetchChangelogContent(
        from: urls, versionPrefix: versionPrefix, allowsLatestFallback: allowsLatestFallback)
      {
        let releaseNotes = await ReleaseNotesMarkup.attributedStringByPreparingOffMain(
          from: content.text,
          baseURL: content.baseURL,
          relevantVersion: versionPrefix
        )
        guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }
        completion(
          releaseNotes.map {
            ResolvedReleaseNotes(content: $0, quality: .genuine, provenance: .changelog)
          })
        return
      }

      guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }

      if let fallbackHTML {
        releaseNotesLogger.info(
          "Using fallback release notes HTML after direct changelog fetch failed")
        let releaseNotes = await ReleaseNotesMarkup.attributedStringByPreparingOffMain(
          from: fallbackHTML,
          baseURL: nil,
          relevantVersion: versionPrefix
        )
        guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }
        completion(
          releaseNotes.map {
            ResolvedReleaseNotes(content: $0, quality: .degraded, provenance: .bundledFallback)
          })
        return
      }

      releaseNotesLogger.info(
        "Falling back to WebKit changelog loader after direct changelog fetch failed")
      self.webChangelogReleaseNotes(
        from: urls, versionPrefix: versionPrefix, allowsLatestFallback: allowsLatestFallback,
        requestID: requestID, with: completion)
    }
  }

  private func webChangelogReleaseNotes(
    from urls: [URL], versionPrefix: String?, allowsLatestFallback: Bool, requestID: UUID,
    with completion: @escaping ResolvedCompletion
  ) {
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
        guard self.isCurrentRequest(requestID), activeAttemptID == attemptID, !didComplete else {
          return
        }

        switch result {
        case .success(let html):
          self.currentReleaseNotesTask?.cancel()
          self.currentReleaseNotesTask = Task { [weak self] in
            guard let self else { return }
            let releaseNotes =
              await ReleaseNotesMarkup.attributedStringFromChangelogByPreparingOffMain(
                fromHTML: html,
                baseURL: url,
                relevantVersion: versionPrefix,
                allowFirstSectionFallback: allowsLatestFallback
              )
            guard !Task.isCancelled,
              self.isCurrentRequest(requestID),
              activeAttemptID == attemptID,
              !didComplete
            else { return }
            if let releaseNotes {
              finish(
                releaseNotes.map {
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

  private nonisolated static func fetchChangelogContent(
    from urls: [URL], versionPrefix: String?, allowsLatestFallback: Bool
  ) async -> ChangelogContent? {
    await withTaskGroup(of: ChangelogContent?.self) { group in
      let maximumConcurrentFetches = 2
      var remainingURLs = ArraySlice(urls)
      var activeFetches = 0

      func addNextFetch() {
        guard let url = remainingURLs.popFirst() else { return }
        activeFetches += 1
        group.addTask {
          guard !Task.isCancelled,
            let html = try? await Self.fetchHTML(from: url)
          else {
            return nil
          }

          return await Self.changelogContent(
            fromHTML: html, url: url, versionPrefix: versionPrefix,
            allowsLatestFallback: allowsLatestFallback)
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

  private nonisolated static func changelogContent(
    fromHTML html: String, url: URL, versionPrefix: String?, allowsLatestFallback: Bool
  ) async -> ChangelogContent? {
    if ReleaseNotesMarkup.usesSourceSpecificTextExtraction(for: url),
      let text = ReleaseNotesMarkup.relevantChangelogText(
        fromHTML: html, version: versionPrefix, pageURL: url,
        allowFirstSectionFallback: allowsLatestFallback)
    {
      return ChangelogContent(text: text, baseURL: url)
    }

    if let releaseHTML = ReleaseNotesMarkup.releaseContentHTML(
      fromHTML: html, version: versionPrefix, pageURL: url)
    {
      return ChangelogContent(text: releaseHTML, baseURL: url)
    }

    if url.host?.localizedCaseInsensitiveContains("chromereleases.googleblog.com") == true,
      let text = ReleaseNotesMarkup.relevantChangelogText(
        fromHTML: html, version: versionPrefix, pageURL: url,
        allowFirstSectionFallback: allowsLatestFallback)
    {
      return ChangelogContent(text: text, baseURL: url)
    }

    if let linkedURL = ReleaseNotesMarkup.linkedChangelogURL(
      fromHTML: html, version: versionPrefix, pageURL: url),
      linkedURL != url,
      let linkedHTML = try? await Self.fetchHTML(from: linkedURL)
    {
      if let releaseHTML = ReleaseNotesMarkup.releaseContentHTML(
        fromHTML: linkedHTML, version: versionPrefix, pageURL: linkedURL)
      {
        return ChangelogContent(text: releaseHTML, baseURL: linkedURL)
      }

      if let text = ReleaseNotesMarkup.relevantChangelogText(
        fromHTML: linkedHTML, version: versionPrefix, pageURL: linkedURL,
        allowFirstSectionFallback: true)
      {
        return ChangelogContent(text: text, baseURL: linkedURL)
      }

      if let text = ReleaseNotesMarkup.plainText(fromHTML: linkedHTML),
        ReleaseNotesMarkup.isUsefulReleaseNotesText(text, relevantVersion: versionPrefix)
      {
        return ChangelogContent(text: text, baseURL: linkedURL)
      }
    }

    if let text = ReleaseNotesMarkup.relevantChangelogText(
      fromHTML: html, version: versionPrefix, pageURL: url,
      allowFirstSectionFallback: allowsLatestFallback)
    {
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

      let result = try await URLSessionReleaseNotesHTTPDataLoader().load(
        request,
        maximumResponseSize: ReleaseNotesCandidateScorer.maximumMarkupSize
      )
      if let response = result.response as? HTTPURLResponse {
        if response.statusCode == 404 {
          throw GitHubReleaseFetchError.notFound
        }
        if !(200..<300).contains(response.statusCode) {
          throw FetchHTMLError.unusableText
        }
      }

      return result.data
    }
  }

}
