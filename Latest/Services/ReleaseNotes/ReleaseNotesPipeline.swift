//
//  ReleaseNotesPipeline.swift
//  Latest
//
//  Created by Codex on 18.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Foundation

enum ReleaseNotesProvenance: String, Sendable {
  case appStore
  case bundledFallback
  case changelog
  case githubRelease
  case homebrewMetadata
  case remoteURL
  case sparkleEmbedded
  case webKit
}

enum ReleaseNotesQuality: Int, Comparable, Sendable {
  case rejected
  case genericMetadata
  case degraded
  case genuine

  static func < (lhs: ReleaseNotesQuality, rhs: ReleaseNotesQuality) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

struct ResolvedReleaseNotes: @unchecked Sendable {
  let content: NSAttributedString
  let quality: ReleaseNotesQuality
  let provenance: ReleaseNotesProvenance
}

struct ReleaseNotesContext: Sendable {
  let appName: String
  let bundleIdentifier: String
  let localVersion: String?
  let remoteVersion: String?
  let platform: String

  init(app: App, platform: String = "macOS") {
    appName = app.name
    bundleIdentifier = app.bundleIdentifier
    localVersion = app.version.versionNumber ?? app.version.buildNumber
    remoteVersion = app.remoteVersion?.versionNumber ?? app.remoteVersion?.buildNumber
    self.platform = platform
  }

  init(
    appName: String,
    bundleIdentifier: String,
    localVersion: String?,
    remoteVersion: String?,
    platform: String = "macOS"
  ) {
    self.appName = appName
    self.bundleIdentifier = bundleIdentifier
    self.localVersion = localVersion
    self.remoteVersion = remoteVersion
    self.platform = platform
  }
}

struct ReleaseNotesCandidate: Sendable {
  let markup: String
  let baseURL: URL?
  let provenance: ReleaseNotesProvenance
  let qualityHint: ReleaseNotesQuality
  let declaredAppIdentifiers: Set<String>
  let declaredVersion: String?
  let declaredPlatforms: Set<String>

  init(
    markup: String,
    baseURL: URL?,
    provenance: ReleaseNotesProvenance,
    qualityHint: ReleaseNotesQuality = .genuine,
    declaredAppIdentifiers: Set<String> = [],
    declaredVersion: String? = nil,
    declaredPlatforms: Set<String> = []
  ) {
    self.markup = markup
    self.baseURL = baseURL
    self.provenance = provenance
    self.qualityHint = qualityHint
    self.declaredAppIdentifiers = declaredAppIdentifiers
    self.declaredVersion = declaredVersion
    self.declaredPlatforms = declaredPlatforms
  }
}

enum ReleaseNotesCandidateRejection: Error, Equatable {
  case empty
  case malformed
  case oversized
  case wrongApplication
  case wrongPlatform
  case wrongVersion
}

struct ReleaseNotesCandidateScorer: Sendable {
  static let maximumMarkupSize = 2 * 1_024 * 1_024

  let maximumMarkupSize: Int

  init(maximumMarkupSize: Int = Self.maximumMarkupSize) {
    self.maximumMarkupSize = maximumMarkupSize
  }

  func quality(
    of candidate: ReleaseNotesCandidate,
    for context: ReleaseNotesContext
  ) throws -> ReleaseNotesQuality {
    let trimmedMarkup = candidate.markup.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedMarkup.isEmpty else {
      throw ReleaseNotesCandidateRejection.empty
    }
    guard candidate.markup.utf8.count <= maximumMarkupSize else {
      throw ReleaseNotesCandidateRejection.oversized
    }
    guard !ReleaseNotesMarkup.looksLikeBinaryOrMojibakeText(trimmedMarkup) else {
      throw ReleaseNotesCandidateRejection.malformed
    }

    if !candidate.declaredAppIdentifiers.isEmpty {
      let expected = Self.normalizedIdentifier(context.bundleIdentifier)
      let identifiers = Set(candidate.declaredAppIdentifiers.map(Self.normalizedIdentifier))
      guard identifiers.contains(expected) else {
        throw ReleaseNotesCandidateRejection.wrongApplication
      }
    }

    if let declaredVersion = candidate.declaredVersion,
      let remoteVersion = context.remoteVersion,
      !Self.versionsMatch(declaredVersion, remoteVersion)
    {
      throw ReleaseNotesCandidateRejection.wrongVersion
    }

    if !candidate.declaredPlatforms.isEmpty {
      let expectedPlatform = context.platform.lowercased()
      guard
        candidate.declaredPlatforms.contains(where: {
          $0.lowercased() == expectedPlatform
        })
      else {
        throw ReleaseNotesCandidateRejection.wrongPlatform
      }
    }

    return candidate.qualityHint
  }

  private static func normalizedIdentifier(_ value: String) -> String {
    value.lowercased().filter { $0.isLetter || $0.isNumber }
  }

  private static func versionsMatch(_ lhs: String, _ rhs: String) -> Bool {
    let lhs = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
    let rhs = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
    return lhs == rhs || lhs.hasPrefix(rhs + ".") || rhs.hasPrefix(lhs + ".")
  }
}

struct ParsedReleaseNotes: Sendable {
  let markup: String
  let baseURL: URL?
  let relevantVersion: String?
  let provenance: ReleaseNotesProvenance
  let quality: ReleaseNotesQuality
}

struct ScoredReleaseNotesCandidate: Sendable {
  let candidate: ReleaseNotesCandidate
  let quality: ReleaseNotesQuality
}

/// Selects the highest-quality usable candidate while keeping source selection
/// independent from fetching, parsing, and rendering. This supports genuine
/// notes and generic package metadata coexisting without conflating them.
struct ReleaseNotesResolver: Sendable {
  func resolve(
    _ candidates: [ReleaseNotesCandidate],
    for context: ReleaseNotesContext,
    scorer: ReleaseNotesCandidateScorer
  ) throws -> ScoredReleaseNotesCandidate {
    var accepted = [ScoredReleaseNotesCandidate]()
    var firstRejection: Error?

    for candidate in candidates {
      do {
        accepted.append(
          ScoredReleaseNotesCandidate(
            candidate: candidate,
            quality: try scorer.quality(of: candidate, for: context)
          ))
      } catch {
        firstRejection = firstRejection ?? error
      }
    }

    guard let best = accepted.max(by: { $0.quality < $1.quality }) else {
      throw firstRejection ?? ReleaseNotesCandidateRejection.empty
    }
    return best
  }
}

struct ReleaseNotesParser: Sendable {
  func parse(
    _ candidate: ReleaseNotesCandidate,
    context: ReleaseNotesContext,
    quality: ReleaseNotesQuality
  ) -> ParsedReleaseNotes {
    ParsedReleaseNotes(
      markup: candidate.markup,
      baseURL: candidate.baseURL,
      relevantVersion: context.remoteVersion,
      provenance: candidate.provenance,
      quality: quality
    )
  }
}

struct ReleaseNotesRenderer: Sendable {
  @MainActor
  func render(_ parsed: ParsedReleaseNotes) async -> Result<ResolvedReleaseNotes, Error> {
    let rendered = await ReleaseNotesMarkup.attributedStringByPreparingOffMain(
      from: parsed.markup,
      baseURL: parsed.baseURL,
      relevantVersion: parsed.relevantVersion
    )
    return rendered.map {
      ResolvedReleaseNotes(
        content: $0,
        quality: parsed.quality,
        provenance: parsed.provenance
      )
    }
  }
}

struct ReleaseNotesPipeline: Sendable {
  private let resolver: ReleaseNotesResolver
  private let scorer: ReleaseNotesCandidateScorer
  private let parser: ReleaseNotesParser
  private let renderer: ReleaseNotesRenderer

  init(
    resolver: ReleaseNotesResolver = ReleaseNotesResolver(),
    scorer: ReleaseNotesCandidateScorer = ReleaseNotesCandidateScorer(),
    parser: ReleaseNotesParser = ReleaseNotesParser(),
    renderer: ReleaseNotesRenderer = ReleaseNotesRenderer()
  ) {
    self.resolver = resolver
    self.scorer = scorer
    self.parser = parser
    self.renderer = renderer
  }

  func resolve(
    _ candidate: ReleaseNotesCandidate,
    for context: ReleaseNotesContext
  ) async -> Result<ResolvedReleaseNotes, Error> {
    await resolve([candidate], for: context)
  }

  func resolve(
    _ candidates: [ReleaseNotesCandidate],
    for context: ReleaseNotesContext
  ) async -> Result<ResolvedReleaseNotes, Error> {
    do {
      let resolved = try resolver.resolve(candidates, for: context, scorer: scorer)
      let parsed = parser.parse(resolved.candidate, context: context, quality: resolved.quality)
      return await renderer.render(parsed)
    } catch {
      return .failure(error)
    }
  }
}

struct ReleaseNotesFetchResponse: Sendable {
  let data: Data
  let response: URLResponse
}

protocol ReleaseNotesHTTPDataLoading: Sendable {
  func load(_ request: URLRequest, maximumResponseSize: Int) async throws
    -> ReleaseNotesFetchResponse
}

struct URLSessionReleaseNotesHTTPDataLoader: ReleaseNotesHTTPDataLoading {
  let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func load(_ request: URLRequest, maximumResponseSize: Int) async throws
    -> ReleaseNotesFetchResponse
  {
    let (bytes, response) = try await session.bytes(for: request)
    if response.expectedContentLength > Int64(maximumResponseSize) {
      throw ReleaseNotesFetchError.oversized
    }

    var data = Data()
    if response.expectedContentLength > 0 {
      data.reserveCapacity(min(Int(response.expectedContentLength), maximumResponseSize))
    }
    for try await byte in bytes {
      guard data.count < maximumResponseSize else {
        throw ReleaseNotesFetchError.oversized
      }
      data.append(byte)
    }
    return ReleaseNotesFetchResponse(data: data, response: response)
  }
}

enum ReleaseNotesFetchError: Error, Equatable {
  case invalidResponse
  case oversized
  case unusableText
}

struct ReleaseNotesFetcher: Sendable {
  private let loader: any ReleaseNotesHTTPDataLoading
  private let maximumResponseSize: Int

  init(
    loader: any ReleaseNotesHTTPDataLoading = URLSessionReleaseNotesHTTPDataLoader(),
    maximumResponseSize: Int = ReleaseNotesCandidateScorer.maximumMarkupSize
  ) {
    self.loader = loader
    self.maximumResponseSize = maximumResponseSize
  }

  func fetchMarkup(
    from url: URL,
    accept: String = "text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.9"
  ) async throws -> String {
    guard url.scheme?.lowercased() == "https" else {
      throw ReleaseNotesFetchError.invalidResponse
    }

    var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 6)
    request.setValue(accept, forHTTPHeaderField: "Accept")
    request.setValue("Latest", forHTTPHeaderField: "User-Agent")
    let result = try await loader.load(request, maximumResponseSize: maximumResponseSize)

    if let response = result.response as? HTTPURLResponse {
      guard (200..<400).contains(response.statusCode) else {
        throw ReleaseNotesFetchError.invalidResponse
      }
      if response.expectedContentLength > Int64(maximumResponseSize) {
        throw ReleaseNotesFetchError.oversized
      }
    }
    guard result.data.count <= maximumResponseSize else {
      throw ReleaseNotesFetchError.oversized
    }
    if let mimeType = result.response.mimeType?.lowercased(),
      !mimeType.hasPrefix("text/"),
      ![
        "application/atom+xml",
        "application/json",
        "application/rss+xml",
        "application/xhtml+xml",
        "application/xml",
      ].contains(mimeType)
    {
      throw ReleaseNotesFetchError.invalidResponse
    }

    let declaredEncoding = result.response.textEncodingName.flatMap(
      String.Encoding.ianaCharacterSetName)
    let text =
      declaredEncoding.flatMap { String(data: result.data, encoding: $0) } ?? String(
        data: result.data, encoding: .utf8) ?? String(data: result.data, encoding: .isoLatin1)
    guard let text,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !ReleaseNotesMarkup.looksLikeBinaryOrMojibakeText(text)
    else {
      throw ReleaseNotesFetchError.unusableText
    }
    return text
  }
}

extension String.Encoding {
  fileprivate static func ianaCharacterSetName(_ name: String) -> String.Encoding? {
    let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
    guard encoding != kCFStringEncodingInvalidId else { return nil }
    return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
  }
}

extension App.Update.ReleaseNotes {
  var provenance: ReleaseNotesProvenance {
    switch self {
    case .encoded, .html:
      return .sparkleEmbedded
    case .genericMetadata:
      return .homebrewMetadata
    case .url:
      return .remoteURL
    case .githubRelease:
      return .githubRelease
    case .changelog:
      return .changelog
    }
  }

  var qualityHint: ReleaseNotesQuality {
    if case .genericMetadata = self {
      return .genericMetadata
    }
    return .genuine
  }
}
