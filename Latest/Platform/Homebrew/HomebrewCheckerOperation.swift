//
//  HomebrewCheckerOperation.swift
//  Latest
//
//  Created by Max Langer on 12.03.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import Foundation

/// Async update checking via Homebrew. The historical type name is retained to
/// avoid needless source churn, but checking is no longer an Operation.
final class HomebrewCheckerOperation: Sendable {

  private let bundle: App.Bundle
  private let repository: UpdateRepository?

  init(with bundle: App.Bundle, repository: UpdateRepository?) {
    self.bundle = bundle
    self.repository = repository
  }

  private enum DirectFeed: String {
    case obsidian = "md.obsidian"
    case delta = "com.zed-industries.delta"
  }

  /// These two vendor feeds perform their own requests. All other lookups share
  /// one Homebrew index, regardless of the number of installed applications.
  static func usesCatalog(for bundle: App.Bundle) -> Bool {
    bundle.source == .none && DirectFeed(rawValue: bundle.bundleIdentifier) == nil
  }

  func check() async throws -> App.Update {
    try Task.checkCancellation()
    switch DirectFeed(rawValue: bundle.bundleIdentifier) {
    case .obsidian:
      return try await ObsidianUpdate.check(bundle)
    case .delta:
      let source = AppDownloadSource.delta
      let release = try await source.release()
      return App.Update(
        app: bundle, remoteVersion: release.version, minimumOSVersion: nil,
        source: .directDownload, date: nil,
        releaseNotes: .changelog(
          urls: [URL(string: "https://delta.dev/docs/whats-in-the-latest")!],
          versionPrefix: release.version.versionNumber, allowsLatestFallback: true,
          fallbackHTML: nil),
        updateAction: .builtIn { app in
          UpdateQueue.shared.addOperation(AppDownloadUpdateOperation(app: app, source: source))
        })
    case nil: break
    }
    guard let repository else {
      throw LatestError.updateInfoUnavailable
    }

    guard let entry = await repository.entry(for: bundle) else {
      throw LatestError.updateInfoUnavailable
    }
    try Task.checkCancellation()
    let version = entry.version
    let releaseNotes =
      ReleaseNotesSourceCatalog.releaseNotes(
        for: bundle,
        remoteVersion: version,
        allowNameFallback: false
      ) ?? entry.releaseNotes
    let downloadSource = AppDownloadSource.homebrewSource(for: bundle, token: entry.token)
    let action: App.Update.Action
    if let downloadSource {
      action = .builtIn { app in
        UpdateQueue.shared.addOperation(
          AppDownloadUpdateOperation(app: app, source: downloadSource))
      }
    } else {
      action = .external(label: bundle.name) { app in
        Task { @MainActor in MacApplicationWorkspace.shared.openApplication(at: app.fileURL) }
      }
    }
    return App.Update(
      app: bundle,
      remoteVersion: version,
      minimumOSVersion: entry.minimumOSVersion,
      source: downloadSource == nil ? .homebrew : .directDownload,
      date: nil,
      releaseNotes: releaseNotes,
      updateAction: action
    )
  }
}
