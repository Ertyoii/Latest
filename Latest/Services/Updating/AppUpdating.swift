//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-09-05.
//  Licensed under GPL-3.0; see LICENSE.md.

import Foundation

typealias UpdateStateFeed = (
  current: UpdateProgressState, changes: AsyncStream<UpdateProgressState>
)

/// Feature-facing update boundary. State observation stays on the main actor;
/// queue lookups and actions are safe from any caller.
protocol AppUpdating: AnyObject, Sendable {
  func currentApp(for app: App) -> App?
  func isUpdating(_ app: App) -> Bool
  func update(_ app: App, isBulkUpdate: Bool)
  func cancel(_ app: App)
  @MainActor func retryTermination(_ app: App)
  func state(for identifier: App.Bundle.Identifier) -> UpdateProgressState
  @MainActor func states(for identifier: App.Bundle.Identifier) -> AsyncStream<UpdateProgressState>
  @MainActor func stateChanges(for identifier: App.Bundle.Identifier) -> UpdateStateFeed
}

extension AppUpdating {
  func currentApp(for app: App) -> App? { app }

  @MainActor func presentation(for app: App, progressState: UpdateProgressState)
    -> UpdateActionPresentation
  {
    switch progressState {
    case .none, .error:
      return .make(for: currentApp(for: app) ?? app, progressState: progressState)
    default:
      return .make(for: app, progressState: progressState)
    }
  }

  func update(_ app: App) { update(app, isBulkUpdate: false) }
}

/// The live adapter owns the queue dependency. Domain models contain only update
/// metadata and source-provided actions; they never query global service state.
final class AppUpdateService: AppUpdating {
  static let shared = AppUpdateService(queue: .shared) { app in
    UpdateCheckCoordinator.shared.app(at: app.identifier)
  }
  private let queue: UpdateQueue

  private let resolveApp: @Sendable (App) -> App?

  init(queue: UpdateQueue, resolveApp: @escaping @Sendable (App) -> App? = { $0 }) {
    self.queue = queue
    self.resolveApp = resolveApp
  }

  func currentApp(for app: App) -> App? { resolveApp(app) }

  func isUpdating(_ app: App) -> Bool { queue.contains(app.identifier) }
  func update(_ app: App, isBulkUpdate: Bool) {
    guard let current = currentApp(for: app), current.bundleIdentifier == app.bundleIdentifier,
      current.source == app.source, current.updateAvailable, !isUpdating(current)
    else { return }
    current.updateAction?.perform(with: current.bundle, isBulkUpdate: isBulkUpdate)
  }
  func cancel(_ app: App) { queue.cancelUpdate(for: app.identifier) }
  @MainActor func retryTermination(_ app: App) {
    queue.retryTermination(for: app.identifier)
  }
  func state(for identifier: App.Bundle.Identifier) -> UpdateProgressState {
    queue.state(for: identifier)
  }
  @MainActor func states(for identifier: App.Bundle.Identifier) -> AsyncStream<UpdateProgressState>
  { queue.states(for: identifier) }
  @MainActor func stateChanges(for identifier: App.Bundle.Identifier) -> UpdateStateFeed {
    queue.stateChanges(for: identifier)
  }
}
