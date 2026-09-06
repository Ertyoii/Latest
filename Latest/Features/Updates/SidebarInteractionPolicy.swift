//
//  SidebarInteractionPolicy.swift
//  Latest
//
//  Created by ertyoii on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-01.
//  Licensed under GPL-3.0; see LICENSE.md.

import Foundation

/// Renderer-independent sidebar behavior. Keeping these decisions outside the
/// view makes row selection and swipe availability directly testable.
@MainActor
struct SidebarInteractionPolicy {
  enum SwipeEdge {
    case leading
    case trailing
  }

  enum Action: Equatable {
    case update
    case open
    case revealInFinder
  }

  let entries: [AppListSnapshot.Entry]
  var updating: any AppUpdating = AppUpdateService.shared

  func isSelectable(row: Int) -> Bool {
    app(at: row) != nil
  }

  func isSectionHeader(row: Int) -> Bool {
    guard entries.indices.contains(row) else { return false }
    if case .section = entries[row] {
      return true
    }
    return false
  }

  func app(at row: Int) -> App? {
    guard entries.indices.contains(row), case .app(let app) = entries[row] else {
      return nil
    }
    return app
  }

  func targetApp(clickedRow: Int, selectedRow: Int) -> App? {
    if let clickedApp = app(at: clickedRow) {
      return clickedApp
    }
    return app(at: selectedRow)
  }

  func swipeActions(for row: Int, edge: SwipeEdge) -> [Action] {
    guard let app = app(at: row) else { return [] }
    switch edge {
    case .leading:
      return [.open, .revealInFinder]
    case .trailing:
      return app.updateAvailable && !updating.isUpdating(app) ? [.update] : []
    }
  }

  static func accessibilityLabel(for app: App, dateFormatter: DateFormatter) -> String {
    var components = [app.name]
    if let version = app.localizedVersionInformation?.combined(includeNew: app.updateAvailable) {
      components.append(version)
    }
    components.append(dateFormatter.string(from: app.updateDate))
    components.append(app.source.supportState.label)
    if app.updateAvailable {
      components.append(NSLocalizedString("UpdateAction", comment: "Action to update a given app."))
    }
    return components.joined(separator: ", ")
  }
}
