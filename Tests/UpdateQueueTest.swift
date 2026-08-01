//
//  UpdateQueueTest.swift
//  Latest Tests
//
//  Created by Codex on 28.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Synchronization
import XCTest
@testable import Latest

@MainActor
final class UpdateQueueTest: XCTestCase {

	func testDuplicateUpdateOperationIsNotQueued() {
		let identifier = URL(fileURLWithPath: "/Applications/Duplicate-\(UUID().uuidString).app")
		let didStart = expectation(description: "Operation started")
		let didFinish = expectation(description: "Operation finished")
		let firstOperation = TestUpdateOperation(identifier: identifier, didStart: didStart)
		firstOperation.completionBlock = {
			didFinish.fulfill()
		}
		let secondOperation = TestUpdateOperation(identifier: identifier)

		UpdateQueue.shared.addOperation(firstOperation)
		wait(for: [didStart], timeout: 2)

		UpdateQueue.shared.addOperation(secondOperation)

		let matchingOperations = UpdateQueue.shared.operations.compactMap { $0 as? UpdateOperation }.filter {
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
		let identifier = URL(fileURLWithPath: "/Applications/Finished-\(UUID().uuidString).app")
		let didStart = expectation(description: "Operation started")
		let didFinish = expectation(description: "Operation finished")
		let operation = TestUpdateOperation(identifier: identifier, didStart: didStart)
		operation.completionBlock = {
			didFinish.fulfill()
		}

		UpdateQueue.shared.addOperation(operation)
		wait(for: [didStart], timeout: 2)
		operation.complete()
		wait(for: [didFinish], timeout: 2)

		XCTAssertFalse(UpdateQueue.shared.contains(identifier))
	}

	func testReregisteringObserverReceivesCurrentState() {
		let observer = NSObject()
		let identifier = URL(fileURLWithPath: "/Applications/Observer-\(UUID().uuidString).app")
		var receivedStates = [UpdateOperation.ProgressState]()

		UpdateQueue.shared.addObserver(observer, to: identifier) { state in
			receivedStates.append(state)
		}

		UpdateQueue.shared.addObserver(observer, to: identifier) { state in
			receivedStates.append(state)
		}

		XCTAssertEqual(receivedStates.count, 2)
		for state in receivedStates {
			if case .none = state {
				continue
			}
			XCTFail("Expected .none state, got \(state)")
		}
		UpdateQueue.shared.removeObserver(observer, for: identifier)
	}

	func testStateStreamImmediatelyYieldsCurrentState() async {
		let identifier = URL(fileURLWithPath: "/Applications/Stream-\(UUID().uuidString).app")
		var iterator = UpdateQueue.shared.states(for: identifier).makeAsyncIterator()

		guard let state = await iterator.next() else {
			return XCTFail("Expected an initial queue state")
		}
		if case .none = state {
			return
		}
		XCTFail("Expected .none state, got \(state)")
	}

	func testStateChangesReturnsCurrentWithoutRepublishingIt() async {
		let identifier = URL(fileURLWithPath: "/Applications/StateChanges-\(UUID().uuidString).app")
		let feed = UpdateQueue.shared.stateChanges(for: identifier)
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

	func testGlobalStateFeedPublishesIdentifierAndCurrentState() async {
		let identifier = URL(fileURLWithPath: "/Applications/GlobalStream-\(UUID().uuidString).app")
		let operation = TestUpdateOperation(identifier: identifier)
		var iterator = UpdateQueue.shared.stateChanges().makeAsyncIterator()

		UpdateQueue.shared.addOperation(operation)
		guard let change = await iterator.next() else {
			return XCTFail("Expected a global queue state change")
		}

		XCTAssertEqual(change.identifier, identifier)
		if case .pending = change.state {
			// Expected state assigned by UpdateOperation before execution.
		} else if case .initializing = change.state {
			// A fast operation may start before the main actor receives the event.
		} else {
			XCTFail("Expected pending or initializing state, got \(change.state)")
		}
		operation.complete()
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

final class UpdateCheckGenerationTrackerTest: XCTestCase {

	func testStartingNewGenerationInvalidatesOlderWork() {
		let tracker = UpdateCheckGenerationTracker()

		let firstGeneration = tracker.begin()
		XCTAssertTrue(tracker.isCurrent(firstGeneration))

		let secondGeneration = tracker.begin()
		XCTAssertFalse(tracker.isCurrent(firstGeneration))
		XCTAssertTrue(tracker.isCurrent(secondGeneration))
	}

	func testGenerationsIncreaseMonotonically() {
		let tracker = UpdateCheckGenerationTracker()

		XCTAssertEqual(tracker.begin(), 1)
		XCTAssertEqual(tracker.begin(), 2)
		XCTAssertEqual(tracker.begin(), 3)
	}

	func testCurrentOrBeginReusesExistingGeneration() {
		let tracker = UpdateCheckGenerationTracker()

		XCTAssertEqual(tracker.currentOrBegin(), 1)
		XCTAssertEqual(tracker.currentOrBegin(), 1)
		XCTAssertEqual(tracker.begin(), 2)
		XCTAssertEqual(tracker.currentOrBegin(), 2)
	}

}

final class BoundedUpdateCheckExecutorTest: XCTestCase {
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

	func testStaleGenerationCompletionIsNotPublished() async {
		let tracker = UpdateCheckGenerationTracker()
		let published = Mutex([Int]())
		let firstGeneration = tracker.begin()
		let first = Task {
			await BoundedUpdateCheckExecutor(maximumConcurrentTasks: 1).run(
				[1],
				onCompletion: { (result: IndexedUpdateCheckResult<Int>) in
					guard tracker.isCurrent(firstGeneration), case .success(let value) = result.result else { return }
					published.withLock { $0.append(value) }
				}
			) { value in
				try? await Task.sleep(for: .milliseconds(30))
				return value
			}
		}

		try? await Task.sleep(for: .milliseconds(5))
		let secondGeneration = tracker.begin()
		_ = await BoundedUpdateCheckExecutor(maximumConcurrentTasks: 1).run(
			[2],
			onCompletion: { (result: IndexedUpdateCheckResult<Int>) in
				guard tracker.isCurrent(secondGeneration), case .success(let value) = result.result else { return }
				published.withLock { $0.append(value) }
			}
		) { $0 }
		_ = await first.value

		XCTAssertEqual(published.withLock { $0 }, [2])
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
