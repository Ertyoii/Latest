//
//  UpdateCheckCoordinator.swift
//  Latest
//
//  Created by Max Langer on 07.04.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Foundation

/**
 Protocol that defines some methods on reporting the progress of the update checking process.
 */
@MainActor
protocol UpdateCheckProgressReporting: AnyObject {
    /// Indicates that the scan process has been started.
    func updateCheckerDidStartScanningForApps(_ updateChecker: UpdateCheckCoordinator)

    /**
     The process of checking apps for updates has started
     - parameter numberOfApps: The number of apps that will be checked
     */
    func updateChecker(_ updateChecker: UpdateCheckCoordinator, didStartCheckingApps numberOfApps: Int)

    /// Indicates that a single app has been checked.
    func updateChecker(_ updateChecker: UpdateCheckCoordinator, didCheckApp: App)

    /// Called after the update checker finished checking for updates.
    func updateCheckerDidFinishCheckingForUpdates(_ updateChecker: UpdateCheckCoordinator)
}

/**
 UpdateCheckCoordinator handles the logic for checking for updates.
 Each new method of checking for updates should be implemented in its own extension and then included in the `updateMethods` array
 */
final class UpdateCheckCoordinator: @unchecked Sendable {
    typealias UpdateCheckerCallback = (_ app: App.Bundle) -> Void

    /// The object holding the apps found by the checker.
    var appProvider: AppProviding {
        dataStore
    }

    // MARK: - Initialization

    /// The shared instance of the update checker.
    static let shared = UpdateCheckCoordinator()

    // MARK: - Update Checking

    /// Whether the checker is currently waiting for the initial update check.
    private var waitForInitialCheck = true

    /// The delegate for the progress of the entire update checking progress
    weak var progressDelegate: UpdateCheckProgressReporting?

    /// The library containing all bundles loaded from disk.
    private lazy var library: AppLibrary = AppLibrary { bundles in
        // Set new bundles and check for updates
        let newApps = self.dataStore.set(appBundles: Set(bundles))
        self.runUpdateCheck(on: newApps.map(\.bundle))
    }

    /// The data store updated apps should be passed to
    private let dataStore = AppDataStore()

    /// The queue to run update checks on.
    private let updateOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()

        // Allow 10 simultaneous updates
        operationQueue.maxConcurrentOperationCount = 10

        return operationQueue
    }()

    /// Initiate the update check, if not already running.
    func run() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.progressDelegate?.updateCheckerDidStartScanningForApps(self)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.progressDelegate?.updateCheckerDidStartScanningForApps(self)
                }
            }
        }

        if waitForInitialCheck {
            waitForInitialCheck = false
            library.startQuery()
            return
        }

        runUpdateCheck(on: library.bundles)
    }

    /// Performs the update check on the given bundles.
    private func runUpdateCheck(on bundles: [App.Bundle]) {
        let repository: UpdateRepository? = bundles.contains(where: { $0.source == .none }) ? UpdateRepository.newRepository() : nil

        Task {
            await withTaskGroup(of: Void.self) { group in
                for bundle in bundles {
                    group.addTask {
                        await self.check(bundle, using: repository)
                    }
                }
            }

            await MainActor.run {
                self.progressDelegate?.updateCheckerDidFinishCheckingForUpdates(self)
            }
        }
    }

    private func check(_ bundle: App.Bundle, using repository: UpdateRepository?) async {
        await withCheckedContinuation { continuation in
            let operation = Self.operation(forChecking: bundle, repository: repository) { result in
                self.didCheck(bundle, result)
                continuation.resume()
            }

            if let operation {
                self.updateOperationQueue.addOperation(operation)
            } else {
                continuation.resume()
            }
        }
    }

    /// Callback to notify that an app has been updated.
    private func didCheck(_ bundle: App.Bundle, _ update: Result<App.Update, Error>?) {
        let app = dataStore.set(update, for: bundle)

        DispatchQueue.main.async {
            self.progressDelegate?.updateChecker(self, didCheckApp: app)
        }
    }
}

// MARK: - Update Checking Operations

extension UpdateCheckCoordinator {
    /// List of available update checking operations.
    private static var availableOperations: [UpdateCheckerOperation.Type] {
        [
            MacAppStoreUpdateCheckerOperation.self,
            SparkleUpdateCheckerOperation.self,
            HomebrewCheckerOperation.self,
        ]
    }

    /// Returns the update source for the app at the given url.
    static func source(forAppAt url: URL) -> App.Source? {
        availableOperations.first { $0.canPerformUpdateCheck(forAppAt: url) }?.sourceType
    }

    /// Returns the update check operation for the given app bundle.
    static func operation(forChecking bundle: App.Bundle, repository: UpdateRepository?, completion: @escaping UpdateCheckerOperation.UpdateCheckerCompletionBlock) -> UpdateCheckerOperation? {
        availableOperations.first { $0.sourceType == bundle.source }?.init(with: bundle, repository: repository, completionBlock: completion)
    }
}
