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
    var appsByIdentifier = [App.Bundle.Identifier: App]()
    var settledApps = [App]()
    var pendingCheckGeneration: Int?
    var ignoredAppIdentifiers: Set<String>
    let preferences: Preferences
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

  var apps: [App] { state.withLock { Array($0.appsByIdentifier.values) } }
  var updatableApps: [App] {
    apps.filter { $0.updateAvailable && $0.usesBuiltInUpdater && !$0.isIgnored }
  }
  func countOfAvailableUpdates(where condition: (App) -> Bool) -> Int {
    apps.reduce(into: 0) { count, app in
      if app.updateAvailable && !app.isIgnored && condition(app) { count += 1 }
    }
  }

  /// Discovery identity alone is insufficient: an existing path may have new metadata.
  func containsSameBundles(as bundles: Set<App.Bundle>) -> Bool {
    state.withLock { state in
      state.appsByIdentifier.count == bundles.count
        && bundles.allSatisfy { bundle in
          guard let current = state.appsByIdentifier[bundle.identifier]?.bundle else {
            return false
          }
          return current.matchesMetadata(of: bundle)
        }
    }
  }

  func set(appBundles: Set<App.Bundle>) {
    state.withLock { state in
      var appsByIdentifier = [App.Bundle.Identifier: App]()
      appsByIdentifier.reserveCapacity(appBundles.count)
      for bundle in appBundles {
        let previous = state.appsByIdentifier[bundle.identifier]
        let app =
          previous?.with(bundle: bundle)
          ?? App(
            bundle: bundle, update: nil,
            isIgnored: state.ignoredAppIdentifiers.contains(bundle.bundleIdentifier))
        appsByIdentifier[bundle.identifier] = app
      }
      state.appsByIdentifier = appsByIdentifier
    }
    scheduleFilterUpdate()
  }

  func set(appBundle bundle: App.Bundle) -> App {
    let app = state.withLock { state in
      let app =
        state.appsByIdentifier[bundle.identifier]?.with(bundle: bundle)
        ?? App(
          bundle: bundle, update: nil,
          isIgnored: state.ignoredAppIdentifiers.contains(bundle.bundleIdentifier))
      state.appsByIdentifier[app.identifier] = app
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
      state.appsByIdentifier[app.identifier] = app
      return app
    }
    scheduleFilterUpdate()
    return app
  }

  /// A targeted post-install refresh can change metadata within an ongoing
  /// scan generation. Accept only results for the currently installed bundle.
  func accept(_ update: Result<App.Update, Error>, for bundle: App.Bundle) -> App? {
    let app = state.withLock { state -> App? in
      guard let current = state.appsByIdentifier[bundle.identifier],
        current.bundle.matchesMetadata(of: bundle)
      else { return nil }
      let app = App(bundle: bundle, update: update, isIgnored: current.isIgnored)
      state.appsByIdentifier[app.identifier] = app
      return app
    }
    if app != nil { scheduleFilterUpdate() }
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
      // Preferences belong to an app identifier, including every installed copy.
      // A settled UI row can outlive discovery; never reinsert its removed path.
      for (identifier, current) in state.appsByIdentifier
      where current.bundleIdentifier == app.bundleIdentifier {
        state.appsByIdentifier[identifier] = current.with(ignoredState: ignored)
      }
    }
    scheduleFilterUpdate()
  }

  /// Keep the last complete list visible while discovery and lookups change sort keys.
  func beginUpdateCheck(generation: Int) {
    state.withLock { state in
      if state.pendingCheckGeneration == nil {
        state.settledApps = Array(state.appsByIdentifier.values)
      }
      state.pendingCheckGeneration = generation
    }
  }

  @MainActor func finishUpdateCheck(generation: Int) {
    let apps = scheduledUpdate.withLock { scheduled -> [App]? in
      let apps = state.withLock { state -> [App]? in
        guard state.pendingCheckGeneration == generation else { return nil }
        state.pendingCheckGeneration = nil
        state.settledApps = Array(state.appsByIdentifier.values)
        return state.settledApps
      }
      guard let apps else { return nil }
      scheduled?.cancel()
      scheduled = nil
      return apps
    }
    guard let apps else { return }
    updateStreams.yield(apps)
  }

  @MainActor func updates() -> AsyncStream<[App]> {
    let visibleApps = state.withLock { state in
      state.pendingCheckGeneration == nil
        ? Array(state.appsByIdentifier.values) : state.settledApps
    }
    return updateStreams.stream(initialValue: visibleApps)
  }

  private func scheduleFilterUpdate() {
    guard state.withLock({ $0.pendingCheckGeneration == nil }) else { return }
    scheduledUpdate.withLock { scheduled in
      scheduled?.cancel()
      let work = DispatchWorkItem { [weak self] in
        Task { @MainActor [weak self] in
          guard let self else { return }
          let apps = self.state.withLock { state -> [App]? in
            guard state.pendingCheckGeneration == nil else { return nil }
            return Array(state.appsByIdentifier.values)
          }
          if let apps { self.updateStreams.yield(apps) }
        }
      }
      scheduled = work
      schedulingQueue.asyncAfter(deadline: .now() + Self.updateCoalescingInterval, execute: work)
    }
  }
}
