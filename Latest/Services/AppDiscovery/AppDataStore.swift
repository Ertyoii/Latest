import Foundation
import Synchronization

protocol AppProviding {
  var updatableApps: [App] { get }
  func countOfAvailableUpdates(where condition: (App) -> Bool) -> Int
  @MainActor func updates() -> AsyncStream<[App]>
  func setIgnoredState(_ ignored: Bool, for app: App)
}

/// All collection/index/preference mutations share one mutex. Snapshots leave the
/// lock before caller predicates or main-actor observers run.
final class AppDataStore: AppProviding, Sendable {
  // Foundation documents UserDefaults as thread-safe but does not declare it
  // Sendable. Only this adapter crosses that boundary; accesses use state's mutex.
  private struct Preferences: @unchecked Sendable {
    let value: UserDefaults
  }
  private struct State: Sendable {
    var apps = Set<App>()
    var appsByIdentifier = [App.Bundle.Identifier: App]()
    var ignoredAppIdentifiers: Set<String>
    let preferences: Preferences

    mutating func update(_ app: App) {
      if let old = appsByIdentifier[app.identifier] { apps.remove(old) }
      apps.insert(app)
      appsByIdentifier[app.identifier] = app
    }
  }

  private let state: Mutex<State>
  private let scheduledUpdate = Mutex<DispatchWorkItem?>(nil)
  private let schedulingQueue = DispatchQueue(label: "AppDataStoreUpdateSchedulingQueue")
  private static let updateCoalescingInterval: TimeInterval = 0.15
  private static let ignoredAppsKey = "IgnoredAppsKey"
  @MainActor private let updateStreams = MainActorAsyncStreamRegistry<[App]>()

  init(userDefaults: UserDefaults = .standard) {
    state = Mutex(
      State(
        ignoredAppIdentifiers: Set(userDefaults.stringArray(forKey: Self.ignoredAppsKey) ?? []),
        preferences: Preferences(value: userDefaults)
      ))
  }

  var apps: Set<App> { state.withLock { $0.apps } }
  var updatableApps: [App] {
    apps.filter { $0.updateAvailable && $0.usesBuiltInUpdater && !$0.isIgnored }
  }
  func countOfAvailableUpdates(where condition: (App) -> Bool) -> Int {
    apps.reduce(into: 0) { count, app in
      if app.updateAvailable && !app.isIgnored && condition(app) { count += 1 }
    }
  }

  func set(appBundles: Set<App.Bundle>) -> Set<App> {
    let added = state.withLock { state in
      let oldApps = state.apps
      let apps = Set(
        appBundles.map { bundle in
          state.appsByIdentifier[bundle.identifier]?.with(bundle: bundle)
            ?? App(
              bundle: bundle, update: nil,
              isIgnored: state.ignoredAppIdentifiers.contains(bundle.bundleIdentifier))
        })
      state.apps = apps
      state.appsByIdentifier = apps.reduce(into: [:]) { index, app in
        index[app.identifier] = index[app.identifier] ?? app
      }
      return apps.subtracting(oldApps)
    }
    scheduleFilterUpdate()
    return added
  }

  func set(appBundle bundle: App.Bundle) -> App {
    let app = state.withLock { state in
      let app =
        state.appsByIdentifier[bundle.identifier]?.with(bundle: bundle)
        ?? App(
          bundle: bundle, update: nil,
          isIgnored: state.ignoredAppIdentifiers.contains(bundle.bundleIdentifier))
      state.update(app)
      return app
    }
    scheduleFilterUpdate()
    return app
  }

  func set(_ update: Result<App.Update, Error>?, for bundle: App.Bundle) -> App {
    let app = state.withLock { state in
      let ignored =
        state.appsByIdentifier[bundle.identifier]?.isIgnored
        ?? state.ignoredAppIdentifiers.contains(bundle.bundleIdentifier)
      let app = App(bundle: bundle, update: update, isIgnored: ignored)
      state.update(app)
      return app
    }
    scheduleFilterUpdate()
    return app
  }

  func setIgnoredState(_ ignored: Bool, for app: App) {
    state.withLock { state in
      if ignored {
        state.ignoredAppIdentifiers.insert(app.bundleIdentifier)
      } else {
        state.ignoredAppIdentifiers.remove(app.bundleIdentifier)
      }
      state.preferences.value.set(Array(state.ignoredAppIdentifiers), forKey: Self.ignoredAppsKey)
      state.update(app.with(ignoredState: ignored))
    }
    scheduleFilterUpdate()
  }

  @MainActor func updates() -> AsyncStream<[App]> {
    updateStreams.stream(initialValue: Array(apps))
  }

  private func scheduleFilterUpdate() {
    scheduledUpdate.withLock { scheduled in
      scheduled?.cancel()
      let work = DispatchWorkItem { [weak self] in
        Task { @MainActor [weak self] in
          guard let self else { return }
          self.updateStreams.yield(Array(self.apps))
        }
      }
      scheduled = work
      schedulingQueue.asyncAfter(deadline: .now() + Self.updateCoalescingInterval, execute: work)
    }
  }
}
