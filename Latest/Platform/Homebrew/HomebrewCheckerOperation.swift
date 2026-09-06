//
//  HomebrewCheckerOperation.swift
//  Latest
//
//  Created by Max Langer on 12.03.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import Cocoa

/// Async update checking via Homebrew. The historical type name is retained to
/// avoid needless source churn, but checking is no longer an Operation.
final class HomebrewCheckerOperation: Sendable {

  private let bundle: App.Bundle
  private let repository: UpdateRepository?

  static func canPerformUpdateCheck(forAppAt url: URL) -> Bool {
    true
  }

  init(with bundle: App.Bundle, repository: UpdateRepository?) {
    self.bundle = bundle
    self.repository = repository
  }

  func check() async throws -> App.Update {
    try Task.checkCancellation()
    guard let repository else {
      throw LatestError.updateInfoUnavailable
    }

    let info = await repository.updateInfo(for: bundle)
    try Task.checkCancellation()
    guard let version = info.version else {
      throw LatestError.updateInfoUnavailable
    }
    let releaseNotes =
      ReleaseNotesSourceCatalog.releaseNotes(
        for: info.bundle,
        remoteVersion: version,
        allowNameFallback: false
      ) ?? info.releaseNotes
    return App.Update(
      app: info.bundle,
      remoteVersion: version,
      minimumOSVersion: info.minimumOSVersion,
      source: .homebrew,
      date: nil,
      releaseNotes: releaseNotes,
      updateAction: .external(label: info.bundle.name) { app in
        Task { @MainActor in
          MacApplicationWorkspace.shared.openApplication(at: app.fileURL)
        }
      }
    )
  }
}
