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

/// Available actions for an app, shared by gesture handling and presentation.
@MainActor
struct SidebarInteractionPolicy {
  enum SwipeEdge {
    case leading
    case trailing
  }

  enum Action: Hashable {
    case update
    case open
    case revealInFinder
  }

  var updating: any AppUpdating = AppUpdateService.shared

  func swipeActions(for app: App, edge: SwipeEdge) -> [Action] {
    switch edge {
    case .leading:
      return [.open, .revealInFinder]
    case .trailing:
      return app.updateAvailable && !updating.isUpdating(app) ? [.update] : []
    }
  }
}

@MainActor
enum SidebarUpdateActionTitle {
  static func text(for app: App) -> String {
    if let externalUpdater = app.externalUpdaterName {
      return String(
        format: NSLocalizedString(
          "ExternalUpdateAction",
          comment:
            "Action to update a given app outside of Latest. The placeholder is the external updater."
        ),
        externalUpdater
      )
    }

    return NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
  }
}
