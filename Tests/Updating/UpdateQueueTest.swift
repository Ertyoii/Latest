//
//  UpdateQueueTest.swift
//  Latest Tests
//
//  Created by ertyoii on 28.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-05-28.
//  Licensed under GPL-3.0; see LICENSE.md.

import Combine
import Synchronization
import XCTest

@testable import Latest

@MainActor
final class UpdateCheckDiscoveryTest: XCTestCase {
  func testScanPublishesSettledRowsAndKeepsPreviousListDuringRefresh() async throws {
    let initialStarted = expectation(description: "Initial checks started")
    initialStarted.expectedFulfillmentCount = 2
    let refreshStarted = expectation(description: "Refresh checks started")
    refreshStarted.expectedFulfillmentCount = 2
    let startedCount = Mutex(0)
    let checks = SuspendedDiscoveryChecks { _ in
      let count = startedCount.withLock {
        $0 += 1
        return $0
      }
      (count <= 2 ? initialStarted : refreshStarted).fulfill()
    }
    let coordinator = UpdateCheckCoordinator(
      check: { bundle, _ in try await checks.check(bundle) }, repositoryProvider: { nil })
    let settings = try isolatedAppListSettings(for: self)
    let model = UpdatesListViewModel(settings: settings, appProvider: coordinator.appProvider)
    var publishedRows = [[String]]()
    var prematureRows = expectation(description: "No provisional rows during startup")
    prematureRows.isInverted = true
    var settledRows = expectation(description: "Settled startup order")
    var isChecking = true
    let observation = model.$snapshot.sink { snapshot in
      let names = snapshot.sections.flatMap(\.apps).map(\.name)
      guard !names.isEmpty else { return }
      publishedRows.append(names)
      if isChecking {
        prematureRows.fulfill()
      } else {
        settledRows.fulfill()
      }
    }
    defer {
      observation.cancel()
      model.stopObserving()
    }
    model.startObserving()
    let bundles = [bundle("A"), bundle("B")]
    coordinator.updateDiscoveredBundles(bundles)
    await fulfillment(of: [initialStarted], timeout: 2)
    await checks.complete("A", remoteVersion: "1", date: Date(timeIntervalSince1970: 10))
    // Give the store's coalesced publication time to expose any provisional rows.
    await fulfillment(of: [prematureRows], timeout: 0.35)
    XCTAssertTrue(model.snapshot.entries.isEmpty)
    XCTAssertNil(model.selectedApp)

    isChecking = false
    await checks.complete("B", remoteVersion: "1", date: Date(timeIntervalSince1970: 20))
    await fulfillment(of: [settledRows], timeout: 2)
    XCTAssertEqual(publishedRows, [["B", "A"]])
    XCTAssertEqual(model.selectedApp?.name, "B")
    let selected = try XCTUnwrap(model.snapshot.apps.first { $0.name == "A" })
    model.select(selected)

    prematureRows = expectation(description: "No partial rows during refresh")
    prematureRows.isInverted = true
    settledRows = expectation(description: "Settled refresh order")
    isChecking = true
    coordinator.updateDiscoveredBundles(bundles, forceRefresh: true)
    await fulfillment(of: [refreshStarted], timeout: 2)
    await checks.complete("A")
    await fulfillment(of: [prematureRows], timeout: 0.35)
    XCTAssertEqual(model.snapshot.sections.flatMap(\.apps).map(\.name), ["B", "A"])
    XCTAssertTrue(model.selectedApp === selected)
    // A view subscribing in the middle of a scan must also see the last settled state.
    var iterator = coordinator.appProvider.updates().makeAsyncIterator()
    let currentApps = await iterator.next()
    let current = try XCTUnwrap(currentApps)
    XCTAssertEqual(current.first { $0.name == "A" }?.remoteVersion?.versionNumber, "1")

    isChecking = false
    await checks.fail("B")
    await fulfillment(of: [settledRows], timeout: 2)
    XCTAssertEqual(publishedRows, [["B", "A"], ["A", "B"]])
    XCTAssertEqual(model.selectedApp?.identifier, selected.identifier)
    XCTAssertEqual(model.selectedApp?.remoteVersion?.versionNumber, "3")
    XCTAssertNotNil(model.snapshot.apps.first { $0.name == "B" }?.error)
  }

  func testUnchangedDiscoveryKeepsPendingChecks() async {
    let started = expectation(description: "Both checks started")
    started.expectedFulfillmentCount = 2
    let checks = SuspendedDiscoveryChecks { _ in started.fulfill() }
    let coordinator = UpdateCheckCoordinator(
      check: { bundle, _ in try await checks.check(bundle) },
      repositoryProvider: {
        XCTFail("Sparkle-only scans must not load the Homebrew catalog")
        return nil
      })
    let progress = DiscoveryCheckProgress(finished: expectation(description: "Scan finished"))
    coordinator.progressDelegate = progress
    let bundles = [bundle("A"), bundle("B")]

    coordinator.updateDiscoveredBundles(bundles)
    await fulfillment(of: [started], timeout: 2)
    coordinator.updateDiscoveredBundles([bundle("B"), bundle("A")])
    await checks.completeAll()
    await fulfillment(of: [progress.finished], timeout: 2)

    XCTAssertEqual(
      Set(coordinator.appProvider.updatableApps.map(\.identifier)), Set(bundles.map(\.identifier)))
    XCTAssertEqual(progress.checked.count, 2)
    XCTAssertEqual(progress.batchSizes, [2])
  }

  func testChangedDiscoveryRechecksRetainedAppsAndRejectsRemovedResults() async {
    let initialStarted = expectation(description: "Initial checks started")
    initialStarted.expectedFulfillmentCount = 3
    let replacementStarted = expectation(description: "Changed and retained apps rechecked")
    replacementStarted.expectedFulfillmentCount = 2
    let startedCount = Mutex(0)
    let checks = SuspendedDiscoveryChecks { _ in
      let count = startedCount.withLock {
        $0 += 1
        return $0
      }
      (count <= 3 ? initialStarted : replacementStarted).fulfill()
    }
    let coordinator = UpdateCheckCoordinator(
      check: { bundle, _ in try await checks.check(bundle) }, repositoryProvider: { nil })
    let progress = DiscoveryCheckProgress(
      finished: expectation(description: "Replacement scan finished"))
    coordinator.progressDelegate = progress
    let prematurePublication = expectation(description: "Cancelled scan cannot publish rows")
    prematurePublication.isInverted = true
    let settledPublication = expectation(description: "Replacement rows published")
    let isChecking = Mutex(true)
    var publishedApps = [App]()
    let stream = coordinator.appProvider.updates()
    let observation = Task {
      for await apps in stream {
        guard !apps.isEmpty else { continue }
        publishedApps = apps
        if isChecking.withLock({ $0 }) {
          prematurePublication.fulfill()
        } else {
          settledPublication.fulfill()
        }
      }
    }
    defer { observation.cancel() }

    coordinator.updateDiscoveredBundles([bundle("A"), bundle("B"), bundle("Removed")])
    await fulfillment(of: [initialStarted], timeout: 2)
    let replacement = [bundle("A", version: "2"), bundle("B")]
    coordinator.updateDiscoveredBundles(replacement)
    await fulfillment(of: [replacementStarted], timeout: 2)
    // Finish the cancelled generation while the replacement checks are still pending.
    await checks.complete("A")
    await checks.complete("B")
    await checks.complete("Removed")
    await fulfillment(of: [prematurePublication], timeout: 0.35)
    isChecking.withLock { $0 = false }
    await checks.completeAll()
    await fulfillment(of: [progress.finished, settledPublication], timeout: 2)

    let apps = coordinator.appProvider.updatableApps
    XCTAssertEqual(Set(apps.map(\.identifier)), Set(replacement.map(\.identifier)))
    XCTAssertEqual(apps.first { $0.name == "A" }?.version.versionNumber, "2")
    XCTAssertEqual(progress.batchSizes, [3, 2])
    XCTAssertEqual(progress.checked.count, 2)
    XCTAssertEqual(Set(publishedApps.map(\.identifier)), Set(replacement.map(\.identifier)))
  }

  private func bundle(_ name: String, version: String = "1") -> App.Bundle {
    App.Bundle(
      version: Version(versionNumber: version, buildNumber: nil), name: name,
      bundleIdentifier: "test.discovery.\(name)", fileURL: URL(fileURLWithPath: "/tmp/\(name).app"),
      source: .sparkle, modificationDate: .distantPast)
  }
}

private actor SuspendedDiscoveryChecks {
  private let started: @Sendable (App.Bundle) -> Void
  private var pending = [(App.Bundle, CheckedContinuation<App.Update, Error>)]()

  init(started: @escaping @Sendable (App.Bundle) -> Void) {
    self.started = started
  }

  func check(_ bundle: App.Bundle) async throws -> App.Update {
    try await withCheckedThrowingContinuation { continuation in
      pending.append((bundle, continuation))
      started(bundle)
    }
  }

  func completeAll() {
    while let (bundle, _) = pending.first {
      complete(bundle.name)
    }
  }

  func complete(_ name: String, remoteVersion: String = "3", date: Date? = nil) {
    guard let index = pending.firstIndex(where: { $0.0.name == name }) else { return }
    let (bundle, continuation) = pending.remove(at: index)
    continuation.resume(
      returning: App.Update(
        app: bundle, remoteVersion: Version(versionNumber: remoteVersion, buildNumber: nil),
        minimumOSVersion: nil, source: .sparkle, date: date, releaseNotes: nil,
        updateAction: .builtIn { _ in }))
  }

  func fail(_ name: String) {
    guard let index = pending.firstIndex(where: { $0.0.name == name }) else { return }
    let (_, continuation) = pending.remove(at: index)
    continuation.resume(throwing: LatestError.updateInfoUnavailable)
  }
}

@MainActor
private final class DiscoveryCheckProgress: UpdateCheckProgressReporting {
  let finished: XCTestExpectation
  var checked = [App]()
  var batchSizes = [Int]()

  init(finished: XCTestExpectation) { self.finished = finished }
  func updateCheckerDidStartScanningForApps(_ updateChecker: UpdateCheckCoordinator) {}
  func updateChecker(
    _ updateChecker: UpdateCheckCoordinator, didStartCheckingApps count: Int, generation: Int
  ) {
    batchSizes.append(count)
  }
  func updateChecker(_ updateChecker: UpdateCheckCoordinator, didCheckApp app: App) {
    checked.append(app)
  }
  func updateCheckerDidFinishCheckingForUpdates(
    _ updateChecker: UpdateCheckCoordinator, generation: Int
  ) {
    finished.fulfill()
  }
}

@MainActor
final class UpdateQueueTest: XCTestCase {

  func testDuplicateUpdateOperationIsNotQueued() {
    let queue = UpdateQueue()
    let identifier = URL(fileURLWithPath: "/Applications/Duplicate-\(UUID().uuidString).app")
    let didStart = expectation(description: "Operation started")
    let didFinish = expectation(description: "Operation finished")
    let firstOperation = TestUpdateOperation(identifier: identifier, didStart: didStart)
    firstOperation.completionBlock = {
      didFinish.fulfill()
    }
    let secondOperation = TestUpdateOperation(identifier: identifier)

    queue.addOperation(firstOperation)
    wait(for: [didStart], timeout: 2)

    queue.addOperation(secondOperation)

    let matchingOperations = queue.operations.compactMap { $0 as? UpdateOperation }
      .filter {
        $0.appIdentifier == identifier
      }
    XCTAssertEqual(matchingOperations.count, 1)
    XCTAssertTrue(matchingOperations.first === firstOperation)
    XCTAssertFalse(secondOperation.isExecuting)
    XCTAssertFalse(secondOperation.isFinished)

    firstOperation.complete()
    wait(for: [didFinish], timeout: 2)
  }

  func testFinishedUpdateOperationIsRemovedFromLookupIndex() {
    let queue = UpdateQueue()
    let identifier = URL(fileURLWithPath: "/Applications/Finished-\(UUID().uuidString).app")
    let didStart = expectation(description: "Operation started")
    let didFinish = expectation(description: "Operation finished")
    let operation = TestUpdateOperation(identifier: identifier, didStart: didStart)
    operation.completionBlock = {
      didFinish.fulfill()
    }

    queue.addOperation(operation)
    wait(for: [didStart], timeout: 2)
    operation.complete()
    wait(for: [didFinish], timeout: 2)

    XCTAssertFalse(queue.contains(identifier))
  }

  func testStateStreamImmediatelyYieldsCurrentState() async {
    let queue = UpdateQueue()
    let identifier = URL(fileURLWithPath: "/Applications/Stream-\(UUID().uuidString).app")
    var iterator = queue.states(for: identifier).makeAsyncIterator()

    guard let state = await iterator.next() else {
      return XCTFail("Expected an initial queue state")
    }
    if case .none = state {
      return
    }
    XCTFail("Expected .none state, got \(state)")
  }

  func testStateChangesReturnsCurrentWithoutRepublishingIt() async {
    let queue = UpdateQueue()
    let identifier = URL(fileURLWithPath: "/Applications/StateChanges-\(UUID().uuidString).app")
    let feed = queue.stateChanges(for: identifier)
    if case .none = feed.current {
      // Expected current value.
    } else {
      XCTFail("Expected .none current state, got \(feed.current)")
    }

    let didReceiveDuplicate = expectation(description: "No duplicate initial state")
    didReceiveDuplicate.isInverted = true
    let observation = Task {
      for await _ in feed.changes {
        didReceiveDuplicate.fulfill()
        break
      }
    }
    await fulfillment(of: [didReceiveDuplicate], timeout: 0.05)
    observation.cancel()
  }

  func testBothPerAppFeedsReceiveSubsequentUpdates() async {
    let queue = UpdateQueue()
    let identifier = URL(fileURLWithPath: "/Applications/Feeds-\(UUID().uuidString).app")
    let operation = TestUpdateOperation(identifier: identifier)
    defer { operation.complete() }
    let states = queue.states(for: identifier)
    let changes = queue.stateChanges(for: identifier).changes
    let received = expectation(description: "Both feeds receive an update")
    received.expectedFulfillmentCount = 2
    let tasks = [states, changes].map { stream in
      Task {
        for await state in stream {
          if case .none = state { continue }
          received.fulfill()
          break
        }
      }
    }
    defer { tasks.forEach { $0.cancel() } }
    queue.addOperation(operation)
    await fulfillment(of: [received], timeout: 2)
  }

}

private final class TestUpdateOperation: UpdateOperation, @unchecked Sendable {
  private let didStart: XCTestExpectation?

  init(identifier: App.Bundle.Identifier, didStart: XCTestExpectation? = nil) {
    self.didStart = didStart
    super.init(bundleIdentifier: "com.example.test", appIdentifier: identifier)
  }

  override func execute() {
    super.execute()
    didStart?.fulfill()
  }

  func complete() {
    finish()
  }
}

final class UpdateCheckSchedulingTest: XCTestCase {
  func testPriorityGroupingPreservesOrderAndDuplicates() {
    let sources: [App.Source] = [.none, .sparkle, .homebrew, .appStore, .none, .sparkle]
    let bundles = sources.enumerated().map { index, source in
      App.Bundle(
        version: Version(versionNumber: "1", buildNumber: nil),
        name: "App \(index)",
        bundleIdentifier: "test.\(index)",
        fileURL: URL(fileURLWithPath: "/Applications/Test-\(index).app"),
        source: source,
        modificationDate: .distantPast
      )
    }
    let input = bundles + [bundles[1]]
    XCTAssertEqual(
      UpdateCheckCoordinator.prioritizedBundlesForUpdateCheck(input).map(\.identifier),
      [1, 3, 5, 1, 0, 2, 4].map { bundles[$0].identifier }
    )
    XCTAssertTrue(UpdateCheckCoordinator.prioritizedBundlesForUpdateCheck([]).isEmpty)
  }
}

final class UpdateCheckGenerationTrackerTest: XCTestCase {
  func testGenerationCannotAdvanceDuringResultAcceptance() {
    let tracker = UpdateCheckGenerationTracker()
    let generation = tracker.begin()
    let accepting = DispatchSemaphore(value: 0)
    let releaseAcceptance = DispatchSemaphore(value: 0)
    let advanceAttempted = DispatchSemaphore(value: 0)
    let advanced = DispatchSemaphore(value: 0)
    let events = Mutex([String]())
    let finished = expectation(description: "Both operations finish")
    finished.expectedFulfillmentCount = 2
    DispatchQueue.global().async {
      _ = tracker.withCurrent(generation) {
        accepting.signal()
        releaseAcceptance.wait()
        events.withLock { $0.append("accepted") }
      }
      finished.fulfill()
    }
    XCTAssertEqual(accepting.wait(timeout: .now() + 2), .success)
    DispatchQueue.global().async {
      advanceAttempted.signal()
      _ = tracker.begin()
      events.withLock { $0.append("advanced") }
      advanced.signal()
      finished.fulfill()
    }
    XCTAssertEqual(advanceAttempted.wait(timeout: .now() + 2), .success)
    XCTAssertEqual(advanced.wait(timeout: .now() + 0.05), .timedOut)
    releaseAcceptance.signal()
    wait(for: [finished], timeout: 2)
    XCTAssertEqual(events.withLock { $0 }, ["accepted", "advanced"])
    let stale = tracker.withCurrent(generation) {
      XCTFail("Stale write ran")
      return 1
    }
    XCTAssertNil(stale)
  }

  func testStartingNewGenerationInvalidatesOlderWork() {
    let tracker = UpdateCheckGenerationTracker()

    let firstGeneration = tracker.begin()
    XCTAssertTrue(tracker.isCurrent(firstGeneration))

    let secondGeneration = tracker.begin()
    XCTAssertFalse(tracker.isCurrent(firstGeneration))
    XCTAssertTrue(tracker.isCurrent(secondGeneration))
  }

  func testCurrentOrBeginReusesExistingGeneration() {
    let tracker = UpdateCheckGenerationTracker()

    XCTAssertEqual(tracker.currentOrBegin(), 1)
    XCTAssertEqual(tracker.currentOrBegin(), 1)
    XCTAssertEqual(tracker.begin(), 2)
    XCTAssertEqual(tracker.currentOrBegin(), 2)
    XCTAssertEqual(tracker.begin(), 3)
    XCTAssertEqual(tracker.currentOrBegin(), 3)
  }

}

final class BoundedUpdateCheckExecutorTest: XCTestCase {
  func testStreamingModeDoesNotRetainCompletedResults() async {
    let completedValues = Mutex([Int]())
    let execution = await BoundedUpdateCheckExecutor(maximumConcurrentTasks: 3).run(
      Array(0..<12),
      collectResults: false,
      onCompletion: { result in
        guard case .success(let value) = result.result else { return }
        completedValues.withLock { $0.append(value) }
      }
    ) { $0 }

    XCTAssertTrue(execution.results.isEmpty)
    XCTAssertEqual(execution.metrics.scheduledCount, 12)
    XCTAssertEqual(execution.metrics.completedCount, 12)
    XCTAssertEqual(Set(completedValues.withLock { $0 }), Set(0..<12))
  }

  func testBoundsParallelismAndReportsProgressForEveryCompletedCheck() async {
    let activity = UpdateCheckActivityTracker()
    let progressCount = Mutex(0)
    let execution = await BoundedUpdateCheckExecutor(maximumConcurrentTasks: 4).run(
      Array(0..<24),
      onCompletion: { _ in progressCount.withLock { $0 += 1 } }
    ) { value in
      await activity.started()
      try await Task.sleep(for: .milliseconds(3))
      await activity.finished()
      return value
    }

    let maximumConcurrentCount = await activity.maximumConcurrentCount()
    XCTAssertEqual(maximumConcurrentCount, 4)
    XCTAssertEqual(execution.results.count, 24)
    XCTAssertEqual(execution.metrics.scheduledCount, 24)
    XCTAssertEqual(execution.metrics.completedCount, 24)
    XCTAssertEqual(progressCount.withLock { $0 }, 24)
    XCTAssertFalse(execution.metrics.wasCancelled)
  }

  func testCancellationStopsAdmittingNewChecks() async {
    let task = Task {
      await BoundedUpdateCheckExecutor(maximumConcurrentTasks: 4).run(Array(0..<100)) { value in
        try await Task.sleep(for: .milliseconds(100))
        return value
      }
    }
    try? await Task.sleep(for: .milliseconds(10))
    task.cancel()
    let execution = await task.value

    XCTAssertTrue(execution.metrics.wasCancelled)
    XCTAssertLessThan(execution.metrics.scheduledCount, 100)
    XCTAssertLessThanOrEqual(execution.metrics.completedCount, execution.metrics.scheduledCount)
    XCTAssertLessThan(execution.results.count, 100)
  }

}

private actor UpdateCheckActivityTracker {
  private var activeCount = 0
  private var maximumCount = 0

  func started() {
    activeCount += 1
    maximumCount = max(maximumCount, activeCount)
  }

  func finished() {
    activeCount -= 1
  }

  func maximumConcurrentCount() -> Int {
    maximumCount
  }
}

@MainActor
final class AppUpdatingBoundaryTest: XCTestCase {
  func testIsolatedServiceRoutesActionsAndHonorsBulkAndQueuedGuards() {
    let calls = Mutex(0)
    let queue = UpdateQueue()
    queue.isSuspended = true
    defer {
      queue.cancelAllOperations()
      queue.isSuspended = false
    }
    let service = AppUpdateService(queue: queue)
    let app = makeApp(action: .builtIn { _ in calls.withLock { $0 += 1 } })
    service.update(app)
    XCTAssertEqual(calls.withLock { $0 }, 1)

    let operation = UpdateOperation(
      bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
    queue.addOperation(operation)
    XCTAssertTrue(service.isUpdating(app))
    service.update(app)
    XCTAssertEqual(calls.withLock { $0 }, 1, "An active operation must suppress duplicate actions")
    service.cancel(app)
    XCTAssertTrue(operation.isCancelled)
    XCTAssertFalse(
      UpdateQueue.shared.contains(app.identifier), "Injected queue must not touch the live queue")

    let external = makeApp(
      action: .external(label: "Vendor", block: { _ in calls.withLock { $0 += 1 } }))
    service.update(external, isBulkUpdate: true)
    XCTAssertEqual(calls.withLock { $0 }, 1)
    service.update(external)
    XCTAssertEqual(calls.withLock { $0 }, 2)
  }

  func testActionModelObservesInjectedQueueAndReleasesWhileStreamIsOpen() async {
    let queue = UpdateQueue()
    queue.isSuspended = true
    defer {
      queue.cancelAllOperations()
      queue.isSuspended = false
    }
    let service = AppUpdateService(queue: queue)
    let app = makeApp(action: .builtIn { _ in })
    let operation = UpdateOperation(
      bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
    queue.addOperation(operation)
    var model: UpdateActionViewModel? = UpdateActionViewModel(app: app, updating: service)
    XCTAssertEqual(model?.presentation, .make(for: app, progressState: .pending))
    operation.progressState = .downloading(loadedSize: 50, totalSize: 100)
    for _ in 0..<100 {
      if model?.presentation == .make(for: app, progressState: operation.progressState) { break }
      await Task.yield()
    }
    XCTAssertEqual(model?.presentation, .make(for: app, progressState: operation.progressState))
    model?.performAction()
    XCTAssertTrue(
      operation.isCancelled, "Progress control must cancel the injected queue's operation")
    weak let weakModel = model
    model = nil
    XCTAssertNil(
      weakModel, "The observation task must not retain its owner across stream suspension")
  }

  func testProgressCanBeReadAndUpdatedConcurrentlyAndCallbackCanReenter() {
    let app = makeApp(action: .builtIn { _ in })
    let operation = UpdateOperation(
      bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
    let notifications = Mutex(0)
    operation.progressHandler = { [weak operation] _ in
      _ = operation?.progressState
      notifications.withLock { $0 += 1 }
    }
    DispatchQueue.concurrentPerform(iterations: 500) { index in
      operation.progressState = .downloading(loadedSize: Int64(index), totalSize: 500)
      _ = operation.progressState
    }
    XCTAssertEqual(notifications.withLock { $0 }, 501)
  }

  private func makeApp(action: App.Update.Action) -> App {
    let bundle = App.Bundle(
      version: Version(versionNumber: "1.0", buildNumber: nil),
      name: "Isolated", bundleIdentifier: "test.isolated",
      fileURL: URL(fileURLWithPath: "/tmp/Isolated-\(UUID().uuidString).app"),
      source: .sparkle, modificationDate: .distantPast)
    let update = App.Update(
      app: bundle, remoteVersion: Version(versionNumber: "2.0", buildNumber: nil),
      minimumOSVersion: nil, source: .sparkle, date: nil,
      releaseNotes: nil, updateAction: action)
    return App(bundle: bundle, update: .success(update), isIgnored: false)
  }
}
