//
//  ApplicationWorkspace.swift
//  Latest
//
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit

/// Narrow boundary for process-wide macOS actions initiated by app features.
/// Domain values and view models describe the intent; AppKit performs it here.
@MainActor
protocol ApplicationWorkspace: AnyObject {
  func openApplication(at url: URL)
  func revealInFinder(_ urls: [URL])
  func open(_ url: URL)
  func setDockBadge(_ label: String?)
}

@MainActor
final class MacApplicationWorkspace: ApplicationWorkspace {
  static let shared = MacApplicationWorkspace()

  private let workspace: NSWorkspace
  private let application: NSApplication

  init(
    workspace: NSWorkspace = .shared,
    application: NSApplication = .shared
  ) {
    self.workspace = workspace
    self.application = application
  }

  func openApplication(at url: URL) {
    workspace.openApplication(
      at: url,
      configuration: NSWorkspace.OpenConfiguration(),
      completionHandler: nil
    )
  }

  func revealInFinder(_ urls: [URL]) {
    workspace.activateFileViewerSelecting(urls)
  }

  func open(_ url: URL) {
    workspace.open(url)
  }

  func setDockBadge(_ label: String?) {
    application.dockTile.badgeLabel = label
  }
}
