//
//  UpdateCheckCoordinator.swift
//  Latest
//
//  Created by Max Langer on 07.04.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Foundation
import OSLog
import Synchronization

private let updateCheckLogger = Logger(
	subsystem: Foundation.Bundle.main.bundleIdentifier ?? "com.max-langer.Latest",
	category: "UpdateCheck"
)

/**
 Protocol that defines some methods on reporting the progress of the update checking process.
 */
@MainActor
protocol UpdateCheckProgressReporting : AnyObject {

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
class UpdateCheckCoordinator: @unchecked Sendable {

    typealias UpdateCheckerCallback = (_ app: App.Bundle) -> Void

	/// The object holding the apps found by the checker.
	var appProvider: AppProviding {
		return self.dataStore
	}


	// MARK: - Initialization

	/// The shared instance of the update checker.
	static let shared = UpdateCheckCoordinator()

	private var updateCompletionObserver: NSObjectProtocol?

	init() {
		self.updateCompletionObserver = NotificationCenter.default.addObserver(
			forName: .latestUpdateOperationDidFinish,
			object: nil,
			queue: nil
		) { [weak self] notification in
			self?.refreshUpdatedApp(from: notification)
		}
	}

	deinit {
		if let updateCompletionObserver {
			NotificationCenter.default.removeObserver(updateCompletionObserver)
		}
	}


	// MARK: - Update Checking

	/// Whether the checker is currently waiting for the initial update check.
	private var waitForInitialCheck = true

	/// The delegate for the progress of the entire update checking progress
    weak var progressDelegate : UpdateCheckProgressReporting?

	/// The library containing all bundles loaded from disk.
	private lazy var library: AppLibrary = {
		return AppLibrary { bundles in
			// Set new bundles and check for updates
			let newApps = self.dataStore.set(appBundles: Set(bundles))
			self.runUpdateCheck(on: newApps.map({ $0.bundle }))
		}
	}()

	/// The data store updated apps should be passed to
	private let dataStore = AppDataStore()

	private struct CheckerDefinition: Sendable {
		let source: App.Source
		let canPerform: @Sendable (URL) -> Bool
		let check: @Sendable (App.Bundle, UpdateRepository?) async throws -> App.Update
	}

	private static let availableCheckers: [CheckerDefinition] = [
		CheckerDefinition(
			source: .appStore,
			canPerform: AppStoreUpdateCheckerOperation.canPerformUpdateCheck,
			check: { bundle, _ in try await AppStoreUpdateCheckerOperation(with: bundle).check() }
		),
		CheckerDefinition(
			source: .sparkle,
			canPerform: SparkleUpdateCheckerOperation.canPerformUpdateCheck,
			check: { bundle, _ in try await SparkleUpdateCheckerOperation(with: bundle).check() }
		),
		CheckerDefinition(
			source: .none,
			canPerform: HomebrewCheckerOperation.canPerformUpdateCheck,
			check: { bundle, repository in try await HomebrewCheckerOperation(with: bundle, repository: repository).check() }
		)
	]

	private let updateCheckExecutor = BoundedUpdateCheckExecutor(maximumConcurrentTasks: 6)

	private let updateCheckSchedulingLock = NSLock()
	private var activeUpdateCheckTasks = [UUID: Task<Void, Never>]()

	private let updateCheckGeneration = UpdateCheckGenerationTracker()

	/// Initiate the update check, if not already running.
	@MainActor
	func run(hardRefresh: Bool = false) {
		self.progressDelegate?.updateCheckerDidStartScanningForApps(self)

		if self.waitForInitialCheck {
			self.waitForInitialCheck = false
			self.library.startQuery()
			return
		}

		invalidateActiveUpdateCheck()
		Task { [weak self] in
			if hardRefresh {
				await AppStoreUpdateCheckerOperation.invalidateLookupCache()
			}
			guard let self else { return }

			self.library.reload { [weak self] bundles in
				guard let self else { return }
				let bundles = Array(Set(bundles))
				_ = self.dataStore.set(appBundles: Set(bundles))
				self.runUpdateCheck(on: bundles)
			}
		}
	}

	/// Prevents results from the previous generation from being published while a manual rescan is collecting bundles.
	private func invalidateActiveUpdateCheck() {
		updateCheckSchedulingLock.withCriticalScope {
			_ = updateCheckGeneration.begin()
			activeUpdateCheckTasks.values.forEach { $0.cancel() }
			activeUpdateCheckTasks.removeAll(keepingCapacity: true)
		}
	}

	/// Performs the update check on the given bundles.
	private func runUpdateCheck(on bundles: [App.Bundle], cancelsExistingChecks: Bool = true) {
		updateCheckSchedulingLock.lock()

		let generation: Int
		if cancelsExistingChecks {
			generation = updateCheckGeneration.begin()
			activeUpdateCheckTasks.values.forEach { $0.cancel() }
			activeUpdateCheckTasks.removeAll(keepingCapacity: true)
		} else {
			generation = updateCheckGeneration.currentOrBegin()
		}

		let repository = UpdateRepository.newRepository()
		let prioritizedBundles = Self.prioritizedBundlesForUpdateCheck(bundles)
		let checkableBundles = prioritizedBundles.filter { bundle in
			Self.checker(for: bundle.source) != nil
		}
		updateCheckLogger.info(
			"Scheduled update check generation \(generation, privacy: .public) for \(bundles.count, privacy: .public) bundles and \(checkableBundles.count, privacy: .public) child tasks"
		)

		let taskID = UUID()
		let task = Task(priority: .userInitiated) { [weak self] in
			guard let self else { return }
			defer { self.removeActiveTask(taskID) }
			await self.performUpdateCheck(
				on: checkableBundles,
				repository: repository,
				generation: generation
			)
		}
		activeUpdateCheckTasks[taskID] = task
		updateCheckSchedulingLock.unlock()
	}

	private func performUpdateCheck(
		on bundles: [App.Bundle],
		repository: UpdateRepository?,
		generation: Int
	) async {
		await MainActor.run {
			guard self.updateCheckGeneration.isCurrent(generation), !Task.isCancelled else { return }
			self.progressDelegate?.updateChecker(self, didStartCheckingApps: bundles.count)
		}

		let execution = await updateCheckExecutor.run(bundles, onCompletion: { [weak self] (indexedResult: IndexedUpdateCheckResult<App.Update>) in
			guard let self, bundles.indices.contains(indexedResult.index) else { return }
			self.didCheck(bundles[indexedResult.index], indexedResult.result, generation: generation)
		}) { bundle in
			try Task.checkCancellation()
			guard let result = await Self.check(bundle, repository: repository) else {
				throw LatestError.updateInfoUnavailable
			}
			return try result.get()
		}

		guard updateCheckGeneration.isCurrent(generation), !Task.isCancelled else { return }
		let durationComponents = execution.metrics.duration.components
		let durationMilliseconds = Int64(durationComponents.seconds * 1_000) +
			Int64(durationComponents.attoseconds / 1_000_000_000_000_000)
		updateCheckLogger.info(
			"Finished update check generation \(generation, privacy: .public), completed \(execution.metrics.completedCount, privacy: .public) of \(execution.metrics.scheduledCount, privacy: .public) tasks in \(durationMilliseconds, privacy: .public) ms"
		)
		await MainActor.run {
			guard self.updateCheckGeneration.isCurrent(generation), !Task.isCancelled else { return }
			self.progressDelegate?.updateCheckerDidFinishCheckingForUpdates(self)
		}
	}

	/// Callback to notify that an app has been updated.
	private func didCheck(_ bundle: App.Bundle, _ update: Result<App.Update, Error>, generation: Int) {
		guard updateCheckGeneration.isCurrent(generation) else {
			return
		}

		let app = self.dataStore.set(update, for: bundle)

		Task { @MainActor in
			guard self.updateCheckGeneration.isCurrent(generation) else { return }
			self.progressDelegate?.updateChecker(self, didCheckApp: app)
		}
	}

	private func removeActiveTask(_ taskID: UUID) {
		updateCheckSchedulingLock.withCriticalScope {
			activeUpdateCheckTasks[taskID] = nil
		}
	}

	private func refreshUpdatedApp(from notification: Notification) {
		guard let appIdentifier = notification.userInfo?[UpdateOperation.appIdentifierUserInfoKey] as? App.Bundle.Identifier else {
			return
		}

		Task.detached(priority: .utility) { [weak self] in
			try? await Task.sleep(for: .milliseconds(300))
			guard !Task.isCancelled else { return }

			guard let self, let bundle = BundleCollector.collectBundle(at: appIdentifier) else {
				return
			}

			_ = self.dataStore.set(appBundle: bundle)
			self.runUpdateCheck(on: [bundle], cancelsExistingChecks: false)
		}
	}

}

final class UpdateCheckGenerationTracker: Sendable {

	private let currentGeneration = Mutex(0)

	func begin() -> Int {
		currentGeneration.withLock { currentGeneration in
			currentGeneration += 1
			return currentGeneration
		}
	}

	func currentOrBegin() -> Int {
		currentGeneration.withLock { currentGeneration in
			if currentGeneration == 0 {
				currentGeneration = 1
			}

			return currentGeneration
		}
	}

	func isCurrent(_ generation: Int) -> Bool {
		currentGeneration.withLock { currentGeneration in
			generation == currentGeneration
		}
	}

}

// MARK: - Update Checking Operations

extension UpdateCheckCoordinator {

	/// Returns the update source for the app at the given url.
	static func source(forAppAt url: URL) -> App.Source? {
		availableCheckers.first { $0.canPerform(url) }?.source
	}

	static func check(_ bundle: App.Bundle, repository: UpdateRepository?) async -> Result<App.Update, Error>? {
		guard let checker = checker(for: bundle.source) else { return nil }
		do {
			return .success(try await checker.check(bundle, repository))
		} catch {
			return .failure(error)
		}
	}

	private static func checker(for source: App.Source) -> CheckerDefinition? {
		availableCheckers.first { $0.source == source }
	}

	private static func prioritizedBundlesForUpdateCheck(_ bundles: [App.Bundle]) -> [App.Bundle] {
		bundles.enumerated()
			.sorted { left, right in
				let leftPriority = updateCheckPriority(for: left.element.source)
				let rightPriority = updateCheckPriority(for: right.element.source)
				if leftPriority == rightPriority {
					return left.offset < right.offset
				}
				return leftPriority < rightPriority
			}
			.map(\.element)
	}

	private static func updateCheckPriority(for source: App.Source) -> Int {
		switch source {
		case .sparkle, .appStore:
			return 0
		case .homebrew, .none:
			return 1
		}
	}

}
