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

/// Protocol that defines some methods on reporting the progress of the update checking process.
@MainActor
protocol UpdateCheckProgressReporting: AnyObject {

  /// Indicates that the scan process has been started.
  func updateCheckerDidStartScanningForApps(_ updateChecker: UpdateCheckCoordinator)

  /**
  The process of checking apps for updates has started
  - parameter numberOfApps: The number of apps that will be checked
  - parameter generation: The check generation that owns this batch
  */
  func updateChecker(
    _ updateChecker: UpdateCheckCoordinator,
    didStartCheckingApps numberOfApps: Int,
    generation: Int
  )

  /// Indicates that a single app has been checked.
  func updateChecker(_ updateChecker: UpdateCheckCoordinator, didCheckApp: App)

  /// Called after the update checker finished checking for updates.
  func updateCheckerDidFinishCheckingForUpdates(
    _ updateChecker: UpdateCheckCoordinator, generation: Int)

}

/// Composition boundary used by UI-facing update services. The concrete
/// coordinator remains responsible for discovery and scheduling internals.
protocol UpdateCheckCoordinating: AnyObject {
  var appProvider: any AppProviding { get }
  @MainActor
  var progressDelegate: (any UpdateCheckProgressReporting)? { get set }
  @MainActor
  func run(hardRefresh: Bool)
}

/// UpdateCheckCoordinator handles the logic for checking for updates.
/// Update sources are registered in `availableCheckers`.
class UpdateCheckCoordinator: UpdateCheckCoordinating, @unchecked Sendable {
  typealias Check = @Sendable (App.Bundle, UpdateRepository?) async throws -> App.Update

  /// The object holding the apps found by the checker.
  var appProvider: AppProviding {
    return self.dataStore
  }

  // MARK: - Initialization

  /// The shared instance of the update checker.
  static let shared = UpdateCheckCoordinator()

  private var updateCompletionObserver: NSObjectProtocol?
  private let check: Check
  private let repositoryProvider: @Sendable () -> UpdateRepository?

  init(
    check: @escaping Check = UpdateCheckCoordinator.check,
    repositoryProvider: @escaping @Sendable () -> UpdateRepository? = UpdateRepository.newRepository
  ) {
    self.check = check
    self.repositoryProvider = repositoryProvider
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
  weak var progressDelegate: UpdateCheckProgressReporting?

  /// The library containing all bundles loaded from disk.
  private lazy var library: AppLibrary = {
    AppLibrary(
      cache: .live, previewHandler: { [weak self] in self?.showDiscoveredPreview($0) },
      handler: { [weak self] in self?.updateDiscoveredBundles($0) })
  }()

  /// Previews may include cached or partial inventory. Only a complete live
  /// collection starts checks and supplies bundles to the installers.
  func showDiscoveredPreview(_ bundles: [App.Bundle]) {
    updateCheckSchedulingLock.withLock {
      guard !hasDiscoveredApps else { return }
      dataStore.beginUpdateCheck(generation: updateCheckGeneration.currentOrBegin())
      dataStore.set(appBundles: Set(bundles))
    }
  }

  /// Reconciles a complete discovery snapshot and schedules its update checks.
  func updateDiscoveredBundles(_ bundles: [App.Bundle], forceRefresh: Bool = false) {
    updateCheckSchedulingLock.withLock {
      let bundles = Set(bundles)
      guard forceRefresh || !hasDiscoveredApps || !dataStore.containsSameBundles(as: bundles) else {
        return
      }
      hasDiscoveredApps = true
      // Invalidate before replacing the store so late results cannot restore removed apps.
      let generation = beginUpdateCheckGeneration()
      dataStore.set(appBundles: bundles)
      scheduleUpdateCheck(on: Array(bundles), generation: generation, isFullScan: true)
    }
  }

  /// The data store updated apps should be passed to
  private let dataStore = AppDataStore()

  func app(at identifier: App.Bundle.Identifier) -> App? { dataStore.app(at: identifier) }

  private struct CheckerDefinition: Sendable {
    let source: App.Source
    let check: @Sendable (App.Bundle, UpdateRepository?) async throws -> App.Update
  }

  private static let availableCheckers: [CheckerDefinition] = [
    CheckerDefinition(
      source: .appStore,
      check: { bundle, _ in try await AppStoreUpdateCheckerOperation(with: bundle).check() }
    ),
    CheckerDefinition(
      source: .sparkle,
      check: { bundle, _ in try await SparkleUpdateCheckerOperation(with: bundle).check() }
    ),
    CheckerDefinition(
      source: .none,
      check: { bundle, repository in
        try await HomebrewCheckerOperation(with: bundle, repository: repository).check()
      }
    ),
  ]

  private let updateCheckSchedulingLock = NSLock()
  private var activeUpdateCheckTasks = [UUID: Task<Void, Never>]()
  private var hasDiscoveredApps = false

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
        self?.updateDiscoveredBundles(bundles, forceRefresh: true)
      }
    }
  }

  /// Prevents results from the previous generation from being published while a manual rescan is collecting bundles.
  private func invalidateActiveUpdateCheck() {
    updateCheckSchedulingLock.withLock {
      _ = beginUpdateCheckGeneration()
    }
  }

  /// Called while holding the scheduling lock.
  private func beginUpdateCheckGeneration() -> Int {
    let generation = updateCheckGeneration.begin()
    dataStore.beginUpdateCheck(generation: generation)
    activeUpdateCheckTasks.values.forEach { $0.cancel() }
    activeUpdateCheckTasks.removeAll(keepingCapacity: true)
    return generation
  }

  /// Called while holding the scheduling lock so registration and cancellation are atomic.
  private func scheduleUpdateCheck(
    on bundles: [App.Bundle], generation: Int, isFullScan: Bool = false
  ) {
    let checkableBundles = bundles.filter { Self.checker(for: $0.source) != nil }
      .sorted { $0.fileURL.path < $1.fileURL.path }
    updateCheckLogger.info(
      "Scheduled update check generation \(generation, privacy: .public) for \(bundles.count, privacy: .public) bundles and \(checkableBundles.count, privacy: .public) child tasks"
    )

    let taskID = UUID()
    let task = Task(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      defer { self.removeActiveTask(taskID) }
      await self.performUpdateCheck(
        on: checkableBundles,
        generation: generation,
        isFullScan: isFullScan
      )
    }
    activeUpdateCheckTasks[taskID] = task
  }

  private func performUpdateCheck(
    on bundles: [App.Bundle],
    generation: Int,
    isFullScan: Bool
  ) async {
    await MainActor.run {
      guard isFullScan, self.updateCheckGeneration.isCurrent(generation), !Task.isCancelled else {
        return
      }
      self.progressDelegate?.updateChecker(
        self,
        didStartCheckingApps: bundles.count,
        generation: generation
      )
    }

    let clock = ContinuousClock()
    let start = clock.now
    let catalog = bundles.filter(HomebrewCheckerOperation.usesCatalog)
    let network = bundles.filter { !HomebrewCheckerOperation.usesCatalog(for: $0) }
    // Indexed catalog matches share one fetch and need no network slots.
    async let networkCount = checkBatch(
      network, limit: 6, repository: nil, generation: generation, isFullScan: isFullScan)
    async let catalogCount = checkCatalogBatch(
      catalog, generation: generation, isFullScan: isFullScan)
    let completed = await networkCount + catalogCount
    guard updateCheckGeneration.isCurrent(generation), !Task.isCancelled else { return }
    let elapsed = start.duration(to: clock.now)
    updateCheckLogger.info(
      "Finished update check generation \(generation, privacy: .public), completed \(completed, privacy: .public) of \(bundles.count, privacy: .public) in \(String(describing: elapsed), privacy: .public)"
    )
    await MainActor.run {
      guard isFullScan, self.updateCheckGeneration.isCurrent(generation), !Task.isCancelled else {
        return
      }
      _ = self.updateCheckGeneration.withCurrent(generation) {
        self.dataStore.finishUpdateCheck(generation: generation)
      }
      self.progressDelegate?.updateCheckerDidFinishCheckingForUpdates(self, generation: generation)
    }
  }

  private func checkCatalogBatch(_ bundles: [App.Bundle], generation: Int, isFullScan: Bool) async
    -> Int
  {
    guard !bundles.isEmpty, !Task.isCancelled else { return 0 }
    return await checkBatch(
      bundles, limit: 1, repository: repositoryProvider(), generation: generation,
      isFullScan: isFullScan)
  }

  private func checkBatch(
    _ bundles: [App.Bundle], limit: Int, repository: UpdateRepository?, generation: Int,
    isFullScan: Bool
  ) async -> Int {
    let execution = await BoundedUpdateCheckExecutor(maximumConcurrentTasks: limit).run(
      bundles, collectResults: false,
      onCompletion: { [weak self] (result: IndexedUpdateCheckResult<App.Update>) in
        self?.didCheck(
          bundles[result.index], result.result, generation: generation, isFullScan: isFullScan)
      }
    ) { [check] bundle in
      try await check(bundle, repository)
    }
    return execution.metrics.completedCount
  }

  /// Callback to notify that an app has been updated.
  private func didCheck(
    _ bundle: App.Bundle, _ update: Result<App.Update, Error>, generation: Int, isFullScan: Bool
  ) {
    guard
      let accepted = updateCheckGeneration.withCurrent(
        generation,
        perform: {
          self.dataStore.accept(update, for: bundle, afterInstall: !isFullScan)
        }),
      let app = accepted, isFullScan
    else { return }

    Task { @MainActor in
      guard self.updateCheckGeneration.isCurrent(generation) else { return }
      self.progressDelegate?.updateChecker(self, didCheckApp: app)
    }
  }

  private func removeActiveTask(_ taskID: UUID) {
    updateCheckSchedulingLock.withLock {
      activeUpdateCheckTasks[taskID] = nil
    }
  }

  @MainActor
  func whileReplacingStoreApp(_ bundle: App.Bundle, install: () async throws -> URL) async throws {
    library.beginReplacing(bundle)
    let result: Result<URL, Error>
    do {
      result = .success(try await install())
    } catch {
      result = .failure(error)
    }
    let installed = await Task.detached(priority: .userInitiated) {
      BundleCollector.collectBundle(at: bundle.fileURL)
    }.value
    // Rebase the existing Store notes and action onto the installed version
    // before the operation releases its progress control.
    let registeredURL = try? result.get()
    let sameCopy =
      registeredURL.map { url in
        if url.standardizedFileURL.path == bundle.fileURL.standardizedFileURL.path { return true }
        // PackageKit can return different capitalization or a symlink to the selected bundle.
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard
          let selected = try? bundle.fileURL.resolvingSymlinksInPath().resourceValues(forKeys: keys)
            .fileResourceIdentifier,
          let registered = try? url.resolvingSymlinksInPath().resourceValues(forKeys: keys)
            .fileResourceIdentifier
        else { return false }
        return selected.isEqual(registered)
      } ?? false
    library.finishReplacing(at: bundle.identifier, with: installed, registeredURL: registeredURL) {
      installed in
      guard sameCopy, installed.source == .appStore,
        installed.bundleIdentifier == bundle.bundleIdentifier
      else { return }
      self.recheckInstalledBundle(installed)
    }
    dataStore.publishCurrentApps()
    let updatedURL = try result.get()
    guard sameCopy else {
      throw LatestError.custom(
        title: String(localized: "The App Store updated a different copy of this app."),
        description: String(
          localized: "Updated \(updatedURL.path) instead of \(bundle.fileURL.path)."))
    }
    guard installed?.source == .appStore, installed?.bundleIdentifier == bundle.bundleIdentifier
    else {
      throw LatestError.custom(
        title: String(localized: "The installed App Store copy could not be verified."),
        description: bundle.fileURL.path)
    }
  }

  private func recheckInstalledBundle(_ bundle: App.Bundle) {
    updateCheckSchedulingLock.withLock {
      guard dataStore.app(at: bundle.identifier) != nil else { return }
      _ = dataStore.set(appBundle: bundle)
      scheduleUpdateCheck(on: [bundle], generation: updateCheckGeneration.currentOrBegin())
    }
  }

  private func refreshUpdatedApp(from notification: Notification) {
    // The manual installer already verified and reconciled its registered path.
    if let store = notification.object as? AppStoreUpdateOperation, store.isCommitting { return }
    guard
      let appIdentifier = notification.userInfo?[UpdateOperation.appIdentifierUserInfoKey]
        as? App.Bundle.Identifier
    else {
      return
    }

    Task.detached(priority: .utility) { [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }

      guard let self, let bundle = BundleCollector.collectBundle(at: appIdentifier) else {
        return
      }

      self.recheckInstalledBundle(bundle)
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

  /// Serialize result acceptance with generation changes. The operation must not
  /// reenter this tracker or invoke observers; AppDataStore publishes asynchronously.
  func withCurrent<Value>(_ generation: Int, perform operation: () -> Value) -> Value? {
    currentGeneration.withLock { current in
      guard generation == current else { return nil }
      return operation()
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

  static func check(_ bundle: App.Bundle, repository: UpdateRepository?) async throws -> App.Update
  {
    guard let checker = checker(for: bundle.source) else {
      throw LatestError.updateInfoUnavailable
    }
    return try await checker.check(bundle, repository)
  }

  private static func checker(for source: App.Source) -> CheckerDefinition? {
    availableCheckers.first { $0.source == source }
  }

}
