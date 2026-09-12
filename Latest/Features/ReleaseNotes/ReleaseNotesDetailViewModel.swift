//
//  ReleaseNotesDetailViewModel.swift
//  Latest
//
//  Created by ertyoii on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-01.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import Combine

struct ReleaseNotesMessage: Equatable {
  let title: String?
  let description: String

  init(error: Error) {
    if let localizedError = error as? LocalizedError,
      let failureReason = localizedError.failureReason
    {
      title = localizedError.localizedDescription
      description = failureReason
    } else {
      title = nil
      description = error.localizedDescription
    }
  }

  static let noSelection = ReleaseNotesMessage(
    title: NSLocalizedString(
      "NoAppSelectedTitle",
      comment: "Title of release notes empty state"
    ),
    description: NSLocalizedString(
      "NoAppSelectedDescription",
      comment: "Description of release notes empty state"
    )
  )

  init(title: String?, description: String) {
    self.title = title
    self.description = description
  }
}

enum ReleaseNotesDetailContentState {
  case message(ReleaseNotesMessage)
  case loading
  case text(NSAttributedString)
}

@MainActor
protocol ReleaseNotesProviding: AnyObject {
  func releaseNotes(
    for app: App,
    with completion: @escaping ReleaseNotesProvider.Completion
  )
}

extension ReleaseNotesProvider: ReleaseNotesProviding {}

@MainActor
final class ReleaseNotesDetailViewModel: ObservableObject {
  @Published private(set) var app: App?
  @Published private(set) var contentState: ReleaseNotesDetailContentState = .message(.noSelection)

  private let releaseNotesProvider: ReleaseNotesProviding
  private var loadingTask: Task<Void, Never>?
  private var displayRequestID = UUID()
  private var displayedKey: String?

  init(releaseNotesProvider: ReleaseNotesProviding = ReleaseNotesProvider()) {
    self.releaseNotesProvider = releaseNotesProvider
  }

  deinit {
    loadingTask?.cancel()
  }

  func display(_ app: App?) {
    if self.app !== app { self.app = app }
    let nextKey = app.map(Self.displayKey(for:))
    guard nextKey != displayedKey else { return }
    displayedKey = nextKey

    displayRequestID = UUID()
    let requestID = displayRequestID
    loadingTask?.cancel()
    loadingTask = nil
    MigrationTelemetry.shared.detailCommitted()

    guard let app else {
      contentState = .message(.noSelection)
      return
    }

    loadingTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled,
        let self,
        self.displayRequestID == requestID
      else { return }
      self.contentState = .loading
    }

    releaseNotesProvider.releaseNotes(for: app) { [weak self] result in
      guard let self,
        self.displayRequestID == requestID,
        self.app?.identifier == app.identifier
      else { return }
      self.loadingTask?.cancel()
      self.loadingTask = nil

      switch result {
      case .success(let text)
      where !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
        self.contentState = .text(text)
      case .success:
        self.contentState = .message(
          ReleaseNotesMessage(error: LatestError.releaseNotesUnavailable))
      case .failure(let error):
        self.contentState = .message(ReleaseNotesMessage(error: error))
      }
    }
  }

  static func displayKey(for app: App) -> String {
    ReleaseNotesCacheKey(app: app).stableIdentifier
  }
}
