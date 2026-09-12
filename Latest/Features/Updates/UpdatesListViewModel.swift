//
//  UpdatesListViewModel.swift
//  Latest
//
//  Created by ertyoii on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-04.
//  Licensed under GPL-3.0; see LICENSE.md.

import Combine
import Foundation

@MainActor
final class UpdatesListViewModel: ObservableObject {
  private static let badgeNumberFormatter = NumberFormatter()

  @Published private(set) var snapshot: AppListSnapshot
  private(set) var snapshotRevision = 0
  @Published var selectedApp: App?
  @Published var searchQuery = ""
  @Published private(set) var statusText = ""

  private var observationTasks = [Task<Void, Never>]()
  private var selectionWasUserInitiated = false
  private let settings: any AppListSettingsProviding
  private let appProvider: any AppProviding
  private let workspace: any ApplicationWorkspace
  let updating: any AppUpdating

  init(
    snapshot: AppListSnapshot? = nil,
    settings: any AppListSettingsProviding = AppListSettings.shared,
    appProvider: any AppProviding = UpdateCheckCoordinator.shared.appProvider,
    workspace: any ApplicationWorkspace = MacApplicationWorkspace.shared,
    updating: any AppUpdating = AppUpdateService.shared
  ) {
    self.settings = settings
    self.appProvider = appProvider
    self.workspace = workspace
    self.updating = updating
    self.snapshot =
      snapshot
      ?? AppListSnapshot(
        withApps: [],
        filterQuery: nil,
        settings: settings
      )
    updateTitleAndBadge()
  }

  func startObserving() {
    guard observationTasks.isEmpty else { return }
    let settings = settings
    let appProvider = appProvider

    observationTasks = [
      Task { [weak self] in
        for await _ in settings.updates() {
          guard !Task.isCancelled, let self else { break }
          self.refreshSnapshot()
        }
      },
      Task { [weak self] in
        for await apps in appProvider.updates() {
          guard !Task.isCancelled, let self else { break }
          self.replaceSnapshot(
            with: AppListSnapshot(
              withApps: apps,
              filterQuery: self.normalizedSearchQuery,
              settings: self.settings
            ))
          self.maintainSelectionAfterSnapshotChange()
          self.updateTitleAndBadge()
        }
      },
    ]
  }

  func stopObserving() {
    observationTasks.forEach { $0.cancel() }
    observationTasks.removeAll()
  }

  func setSearchQuery(_ query: String) {
    guard query != searchQuery else { return }
    searchQuery = query
    let filteredSnapshot = MigrationTelemetry.shared.measureFilter(rowCount: snapshot.entries.count)
    {
      snapshot.refiltered(with: normalizedSearchQuery)
    }
    replaceSnapshot(with: filteredSnapshot)
    maintainSelectionAfterSnapshotChange()
  }

  func select(_ app: App?) {
    guard app?.identifier != selectedApp?.identifier else { return }
    selectionWasUserInitiated = true
    if let app, app !== selectedApp {
      MigrationTelemetry.shared.selectionStarted(appName: app.name)
    }
    selectedApp = app
  }

  func select(identifier: App.Bundle.Identifier?) {
    select(snapshot.app(withIdentifier: identifier))
  }

  func update(_ app: App) {
    updating.update(app)
  }

  func open(_ app: App) {
    workspace.openApplication(at: app.fileURL)
  }

  func revealInFinder(_ app: App) {
    workspace.revealInFinder([app.fileURL])
  }

  func setIgnored(_ ignored: Bool, for app: App) {
    appProvider.setIgnoredState(ignored, for: app)
  }

  var hasUpdatesAvailable: Bool {
    !appProvider.updatableApps.isEmpty
  }

  var showsSupportStatus: Bool {
    settings.includeAppsWithLimitedSupport || settings.includeUnsupportedApps
  }

  private var normalizedSearchQuery: String? {
    searchQuery.isEmpty ? nil : searchQuery
  }

  private func refreshSnapshot() {
    replaceSnapshot(with: snapshot.updated(with: normalizedSearchQuery))
    maintainSelectionAfterSnapshotChange()
    updateTitleAndBadge()
  }

  private func replaceSnapshot(with snapshot: AppListSnapshot) {
    snapshotRevision &+= 1
    self.snapshot = snapshot
    MigrationTelemetry.shared.snapshotCommitted(
      rowCount: snapshot.entries.count,
      appCount: snapshot.apps.count
    )
  }

  private func maintainSelectionAfterSnapshotChange() {
    if selectionWasUserInitiated,
      let selectedApp,
      snapshot.firstIndex(of: selectedApp) != nil
    {
      let refreshedApp = snapshot.app(withIdentifier: selectedApp.identifier)
      if refreshedApp !== selectedApp { self.selectedApp = refreshedApp }
      return
    }

    if selectionWasUserInitiated {
      selectionWasUserInitiated = false
    }
    selectedApp = snapshot.sections.first?.apps.first
  }

  private func updateTitleAndBadge() {
    let showExternalUpdates = settings.includeAppsWithLimitedSupport
    let count = appProvider.countOfAvailableUpdates { app in
      showExternalUpdates || app.usesBuiltInUpdater
    }

    workspace.setDockBadge(
      count == 0
        ? nil
        : Self.badgeNumberFormatter.string(from: count as NSNumber))

    let format = NSLocalizedString(
      "NumberOfUpdatesAvailable", comment: "number of updates available")
    statusText = String.localizedStringWithFormat(format, count)
  }
}
