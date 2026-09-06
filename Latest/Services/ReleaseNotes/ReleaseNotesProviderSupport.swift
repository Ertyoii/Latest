//
//  ReleaseNotesProviderSupport.swift
//  Latest
//
//  Parsing and cache-key support kept separate from provider orchestration.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-09-04.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit

enum ReleaseNotesProviderConstants {
  static let downloadExtensions: Set<String> = [
    "7z", "bz2", "dmg", "exe", "gz", "msi", "pkg", "rar", "tbz", "tgz", "xip", "xz", "zip",
  ]
}

enum FetchHTMLError: Error {
  case unusableText
  case fetchFailed
}

enum GitHubReleaseFetchError: Error {
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
      components[4] == "releases"
    else {
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
    guard
      let markerRange = html.range(of: #"data-test-selector="body-content""#)
        ?? html.range(of: #"data-test-selector='body-content'"#)
    else {
      return nil
    }

    guard
      let openingDivRange = html[..<markerRange.lowerBound].range(
        of: "<div", options: [.backwards, .caseInsensitive]),
      let openingTagEndRange = html.range(
        of: ">", range: openingDivRange.lowerBound..<html.endIndex)
    else {
      return nil
    }

    var depth = 1
    var searchStart = openingTagEndRange.upperBound
    while searchStart < html.endIndex {
      let nextOpeningDiv = html.range(
        of: "<div", options: .caseInsensitive, range: searchStart..<html.endIndex)
      let nextClosingDiv = html.range(
        of: "</div>", options: .caseInsensitive, range: searchStart..<html.endIndex)

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

  nonisolated static func isLikelyDownloadURL(_ url: URL) -> Bool {
    ReleaseNotesProviderConstants.downloadExtensions.contains(url.pathExtension.lowercased())
  }

  nonisolated static func deduplicating(title: String?, in body: String) -> String {
    guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
      return body
    }

    var lines = body.components(separatedBy: .newlines)
    while let firstLine = lines.first,
      ReleaseNotesMarkup.normalizedReleaseLine(firstLine)
        == ReleaseNotesMarkup.normalizedReleaseLine(title)
    {
      lines.removeFirst()
    }

    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

}

struct GitHubRelease: Decodable {
  let name: String?
  let body: String
}

struct ChangelogContent: Sendable {
  let text: String
  let baseURL: URL
}

final class ResolvedReleaseNotesBox: NSObject {
  let value: ResolvedReleaseNotes

  init(_ value: ResolvedReleaseNotes) {
    self.value = value
  }
}

final class ReleaseNotesCacheKey: NSObject {
  private let identifier: App.Bundle.Identifier
  private let localVersion: String
  private let remoteVersion: String
  private let releaseNotes: String
  private let catalogRevision: UInt64
  let stableIdentifier: String

  init(app: App) {
    self.identifier = app.identifier
    self.localVersion = app.version.debugDescription
    self.remoteVersion = app.remoteVersion?.debugDescription ?? ""
    self.releaseNotes = app.releaseNotes?.cacheIdentifier ?? ""
    self.catalogRevision = ReleaseNotesSourceCatalog.revision
    self.stableIdentifier = [
      identifier.absoluteString,
      localVersion,
      remoteVersion,
      releaseNotes,
      String(catalogRevision),
    ].joined(separator: "\u{1f}")
  }

  override var hash: Int {
    var hasher = Hasher()
    hasher.combine(identifier)
    hasher.combine(localVersion)
    hasher.combine(remoteVersion)
    hasher.combine(releaseNotes)
    hasher.combine(catalogRevision)
    return hasher.finalize()
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? ReleaseNotesCacheKey else {
      return false
    }

    return identifier == other.identifier && localVersion == other.localVersion
      && remoteVersion == other.remoteVersion && releaseNotes == other.releaseNotes
      && catalogRevision == other.catalogRevision
  }
}

extension App.Update.ReleaseNotes {
  var cacheIdentifier: String {
    switch self {
    case .url(let url):
      return "url:\(url.absoluteString)"
    case .html(let string):
      return "html:\(ReleaseNotesStableDigest.hex(of: Data(string.utf8)))"
    case .genericMetadata(let string):
      return "homebrew-metadata:\(ReleaseNotesStableDigest.hex(of: Data(string.utf8)))"
    case .encoded(let data):
      return "encoded:\(ReleaseNotesStableDigest.hex(of: data))"
    case .githubRelease(let apiURL, let fallbackHTML):
      let fallbackDigest =
        fallbackHTML.map { ReleaseNotesStableDigest.hex(of: Data($0.utf8)) } ?? ""
      return "github:\(apiURL.absoluteString):\(fallbackDigest)"
    case .changelog(let urls, let versionPrefix, let allowsLatestFallback, let fallbackHTML):
      let urlList = urls.map(\.absoluteString).joined(separator: "|")
      let fallbackDigest =
        fallbackHTML.map { ReleaseNotesStableDigest.hex(of: Data($0.utf8)) } ?? ""
      return "changelog:\(urlList):\(versionPrefix ?? ""):\(allowsLatestFallback):\(fallbackDigest)"
    }
  }
}
