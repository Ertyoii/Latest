//
//  TableViewSnapshotDiff.swift
//  Latest
//
//  Created by ertyoii on 05.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-05.
//  Licensed under GPL-3.0; see LICENSE.md.

import Foundation

@MainActor
struct TableViewSnapshotDiff {
  enum Change {
    case reload(IndexSet)
    case append(IndexSet)
    case remove(IndexSet)
    case reloadAll
  }

  let change: Change?

  init(from oldEntries: [AppListSnapshot.Entry], to newEntries: [AppListSnapshot.Entry]) {
    var reloads = IndexSet()
    for index in 0..<min(oldEntries.count, newEntries.count) {
      guard oldEntries[index].isSimilar(to: newEntries[index]) else {
        change = .reloadAll
        return
      }
      if oldEntries[index].needsReload(comparedTo: newEntries[index]) { reloads.insert(index) }
    }

    if oldEntries.count == newEntries.count {
      change = reloads.isEmpty ? nil : .reload(reloads)
    } else if !reloads.isEmpty {
      change = .reloadAll
    } else if oldEntries.count < newEntries.count {
      change = .append(IndexSet(oldEntries.count..<newEntries.count))
    } else {
      change = .remove(IndexSet(newEntries.count..<oldEntries.count))
    }
  }
}

extension AppListSnapshot.Entry {
  fileprivate func needsReload(comparedTo other: AppListSnapshot.Entry) -> Bool {
    switch (self, other) {
    case (.section(let section), .section(let otherSection)):
      return section != otherSection
    case (.app(let app), .app(let otherApp)):
      return app !== otherApp && AppRowDisplayState(app: app) != AppRowDisplayState(app: otherApp)
    default:
      return true
    }
  }
}

private struct AppRowDisplayState: Equatable {
  let name: String
  let localVersion: Version
  let remoteVersion: Version?
  let updateAvailable: Bool
  let updateDate: Date
  let source: App.Source
  let isIgnored: Bool
  let usesBuiltInUpdater: Bool
  let externalUpdaterName: String?
  let errorDescription: String?

  init(app: App) {
    name = app.name
    localVersion = app.version
    remoteVersion = app.remoteVersion
    updateAvailable = app.updateAvailable
    updateDate = app.updateDate
    source = app.source
    isIgnored = app.isIgnored
    usesBuiltInUpdater = app.usesBuiltInUpdater
    externalUpdaterName = app.externalUpdaterName
    errorDescription = app.error.map { String(describing: $0) }
  }
}
