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
