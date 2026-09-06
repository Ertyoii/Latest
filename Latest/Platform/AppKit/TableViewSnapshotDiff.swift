//
//  TableViewSnapshotDiff.swift
//  Latest
//
//  Created by Codex on 05.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

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
    if oldEntries.count == newEntries.count, oldEntries.identityMatches(newEntries) {
      let indexes = oldEntries.reloadIndexes(comparedTo: newEntries)
      change = indexes.isEmpty ? nil : .reload(indexes)
      return
    }

    if oldEntries.exactlyMatchesPrefix(of: newEntries) {
      change = .append(IndexSet(oldEntries.count..<newEntries.count))
      return
    }

    if newEntries.exactlyMatchesPrefix(of: oldEntries) {
      change = .remove(IndexSet(newEntries.count..<oldEntries.count))
      return
    }

    change = .reloadAll
  }
}
extension Array where Element == AppListSnapshot.Entry {
  fileprivate func identityMatches(_ other: [Element]) -> Bool {
    guard count == other.count else { return false }
    return zip(self, other).allSatisfy { $0.isSimilar(to: $1) }
  }

  fileprivate func exactlyMatchesPrefix(of other: [Element]) -> Bool {
    guard count <= other.count else { return false }
    return zip(self, other).allSatisfy(==)
  }

  fileprivate func reloadIndexes(comparedTo other: [Element]) -> IndexSet {
    var indexes = IndexSet()
    for index in indices where self[index].needsReload(comparedTo: other[index]) {
      indexes.insert(index)
    }
    return indexes
  }
}

extension AppListSnapshot.Entry {
  fileprivate func needsReload(comparedTo other: AppListSnapshot.Entry) -> Bool {
    switch (self, other) {
    case (.section(let section), .section(let otherSection)):
      return section != otherSection
    case (.app(let app), .app(let otherApp)):
      return AppRowDisplayState(app: app) != AppRowDisplayState(app: otherApp)
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
