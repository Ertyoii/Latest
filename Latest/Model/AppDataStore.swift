//
//  AppDataStore.swift
//  Latest
//
//  Created by Max Langer on 15.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import Foundation

/// An interface for objects providing apps.
protocol AppProviding {
    /// Returns a list of apps with available updates that can be updated from within Latest.
    var updatableApps: [App] { get }

    /// Returns the number of apps with updates available.
    func countOfAvailableUpdates(where condition: (App) -> Bool) -> Int

    /// The handler for notifying observers about changes to the update state.
    typealias ObserverHandler = @MainActor @Sendable (_ newValue: [App]) -> Void

    /// Adds the observer if it is not already registered.
    @MainActor func addObserver(_ observer: NSObject, handler: @escaping ObserverHandler)

    /// Removes the observer.
    @MainActor func removeObserver(_ observer: NSObject)

    /// Sets the ignored state for the given app.
    func setIgnoredState(_ ignored: Bool, for app: App)
}

/// The collection handling app bundles alongside there update representations.
final class AppDataStore: AppProviding, @unchecked Sendable {
    /// The queue on which updates to the collection are being performed.
    private var updateQueue = DispatchQueue(label: "DataStoreQueue")

    init() {
        updateScheduler = DispatchSource.makeUserDataAddSource(queue: .global())
        setupScheduler()
    }

    // MARK: - Delegate Scheduling

    /// Schedules an update notification.
    private let updateScheduler: DispatchSourceUserDataAdd

    /// Sets up the scheduler.
    private func setupScheduler() {
        // Delay notifying observers to only let that notification occur in a certain interval
        updateScheduler.setEventHandler { [weak self] in
            guard let self else { return }

            let apps = updateQueue.sync { Array(self.apps) }
            Task { @MainActor in
                self.notifyObservers(apps)
            }

            // Delay the next call for 0.6 seconds
            Thread.sleep(forTimeInterval: 0.6)
        }

        updateScheduler.activate()
    }

    /// Schedules an filter update and notifies observers of the updated app list
    private func scheduleFilterUpdate() {
        updateScheduler.add(data: 1)
    }

    // MARK: - App Providing

    /// The collection holding all apps that have been found.
    private(set) var apps = Set<App>() {
        didSet {
            // Schedule an update for observers
            self.scheduleFilterUpdate()
        }
    }

    /// A subset of apps that can be updated. Ignored apps are not part of this list.
    var updatableApps: [App] {
        updateQueue.sync {
            self.apps.filter { $0.updateAvailable && $0.usesBuiltInUpdater && !$0.isIgnored }
        }
    }

    /// The cached count of apps with updates available
    func countOfAvailableUpdates(where condition: (App) -> Bool) -> Int {
        updateQueue.sync {
            self.apps.filter { $0.updateAvailable && !$0.isIgnored && condition($0) }.count
        }
    }

    /// Updates the store with the given set of app bundles.
    ///
    /// It returns a set with matching app objects, containing the given bundles with their associated updates.
    func set(appBundles: Set<App.Bundle>) -> Set<App> {
        updateQueue.sync {
            let oldApps = self.apps
            let cachedUpdatableApps = self.cachedUpdatableAppIdentifiers

            self.apps = Set(appBundles.map { bundle in
                if let app = oldApps.first(where: { $0.identifier == bundle.identifier }) {
                    return app.with(bundle: bundle)
                }

                // New apps start as pending check if they were known to have updates
                let isPendingCheck = cachedUpdatableApps.contains(bundle.bundleIdentifier)
                return App(bundle: bundle, update: nil, isIgnored: self.isIdentifierIgnored(bundle.bundleIdentifier), isPendingCheck: isPendingCheck)
            })

            return self.apps.subtracting(oldApps)
        }
    }

    /// Sets the given update for the given bundle and returns the combined object.
    func set(_ update: Result<App.Update, Error>?, for bundle: App.Bundle) -> App {
        updateQueue.sync {
            guard let oldApp = self.apps.first(where: { $0.bundle == bundle }) else {
                fatalError("App not in data store")
            }

            let app = App(bundle: bundle, update: update, isIgnored: oldApp.isIgnored, isPendingCheck: false)
            self.update(app)

            return app
        }
    }

    /// Replaces an existing app entry in the data store with the given one.
    private func update(_ app: App) {
        if let oldApp = apps.first(where: { $0.identifier == app.identifier }) {
            apps.remove(oldApp)
        }

        apps.insert(app)
    }

    // MARK: - Ignoring Apps

    /// The key for storing a list of ignored apps.
    private static let IgnoredAppsKey = "IgnoredAppsKey"

    /// Returns whether the given identifier is marked as ignored.
    private func isIdentifierIgnored(_ identifier: String) -> Bool {
        ignoredAppIdentifiers.contains(identifier)
    }

    /// Sets the ignored state of the given app.
    func setIgnoredState(_ ignored: Bool, for app: App) {
        var ignoredApps = ignoredAppIdentifiers

        if ignored {
            ignoredApps.insert(app.bundleIdentifier)
        } else {
            ignoredApps.remove(app.bundleIdentifier)
        }

        UserDefaults.standard.set(Array(ignoredApps), forKey: Self.IgnoredAppsKey)

        updateQueue.sync {
            self.update(app.with(ignoredState: ignored))
        }
    }

    /// Returns the identifiers of ignored apps.
    private var ignoredAppIdentifiers: Set<String> {
        Set((UserDefaults.standard.array(forKey: Self.IgnoredAppsKey) as? [String]) ?? [])
    }

    // MARK: - Update Caching

    /// The key for storing a list of apps that had updates in the last session.
    private static let CachedUpdatesKey = "CachedUpdatesKey"

    /// Returns the identifiers of apps that had updates in the last session.
    private var cachedUpdatableAppIdentifiers: Set<String> {
        Set((UserDefaults.standard.array(forKey: Self.CachedUpdatesKey) as? [String]) ?? [])
    }

    private func cacheUpdatableApps(_ apps: [App]) {
        let identifiers = apps.filter { $0.updateAvailable && !$0.isIgnored }.map(\.bundleIdentifier)
        UserDefaults.standard.set(identifiers, forKey: Self.CachedUpdatesKey)
    }

    // MARK: - Observer Handling

    /// A mapping of observers associated with apps.
    @MainActor private var observers = [NSObject: ObserverHandler]()

    /// Adds the observer if it is not already registered.
    @MainActor func addObserver(_ observer: NSObject, handler: @escaping ObserverHandler) {
        guard !observers.keys.contains(observer) else { return }
        observers[observer] = handler

        // Call handler immediately to propagate initial state
        let apps = updateQueue.sync { Array(self.apps) }
        handler(apps)
    }

    /// Removes the observer.
    @MainActor func removeObserver(_ observer: NSObject) {
        observers.removeValue(forKey: observer)
    }

    /// Notifies observers about state changes.
    @MainActor private func notifyObservers(_ apps: [App]) {
        // Cache the current state for the next launch
        cacheUpdatableApps(apps)
        observers.values.forEach { $0(apps) }
    }
}
