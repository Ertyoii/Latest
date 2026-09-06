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

@MainActor
final class AppUpdatingBoundaryTest: XCTestCase {
    func testIsolatedServiceRoutesActionsAndHonorsBulkAndQueuedGuards() {
        let calls = Mutex(0)
        let queue = UpdateQueue()
        queue.isSuspended = true
        defer { queue.cancelAllOperations(); queue.isSuspended = false }
        let service = AppUpdateService(queue: queue)
        let app = makeApp(action: .builtIn { _ in calls.withLock { $0 += 1 } })
        service.update(app)
        XCTAssertEqual(calls.withLock { $0 }, 1)

        let operation = UpdateOperation(bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
        queue.addOperation(operation)
        XCTAssertTrue(service.isUpdating(app))
        service.update(app)
        XCTAssertEqual(calls.withLock { $0 }, 1, "An active operation must suppress duplicate actions")
        service.cancel(app)
        XCTAssertTrue(operation.isCancelled)
        XCTAssertFalse(UpdateQueue.shared.contains(app.identifier), "Injected queue must not touch the live queue")

        let external = makeApp(action: .external(label: "Vendor", block: { _ in calls.withLock { $0 += 1 } }))
        service.update(external, isBulkUpdate: true)
        XCTAssertEqual(calls.withLock { $0 }, 1)
        service.update(external)
        XCTAssertEqual(calls.withLock { $0 }, 2)
    }

    func testActionModelObservesInjectedQueueAndReleasesWhileStreamIsOpen() async {
        let queue = UpdateQueue()
        queue.isSuspended = true
        defer { queue.cancelAllOperations(); queue.isSuspended = false }
        let service = AppUpdateService(queue: queue)
        let app = makeApp(action: .builtIn { _ in })
        let operation = UpdateOperation(bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
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
        XCTAssertTrue(operation.isCancelled, "Progress control must cancel the injected queue's operation")
        weak var weakModel = model
        model = nil
        XCTAssertNil(weakModel, "The observation task must not retain its owner across stream suspension")
    }

    func testProgressCanBeReadAndUpdatedConcurrentlyAndCallbackCanReenter() {
        let app = makeApp(action: .builtIn { _ in })
        let operation = UpdateOperation(bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
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
        let bundle = App.Bundle(version: Version(versionNumber: "1.0", buildNumber: nil),
                                name: "Isolated", bundleIdentifier: "test.isolated",
                                fileURL: URL(fileURLWithPath: "/tmp/Isolated-\(UUID().uuidString).app"),
                                source: .sparkle, modificationDate: .distantPast)
        let update = App.Update(app: bundle, remoteVersion: Version(versionNumber: "2.0", buildNumber: nil),
                                minimumOSVersion: nil, source: .sparkle, date: nil,
                                releaseNotes: nil, updateAction: action)
        return App(bundle: bundle, update: .success(update), isIgnored: false)
    }
}

@MainActor
final class DisplayLinkTest: XCTestCase {
	func testFiniteAnimationStopsAfterReachingItsDuration() async {
		let finished = expectation(description: "Animation completes")
		let link = DisplayLink(duration: 0.03) { progress in
			if progress >= 1 { finished.fulfill() }
		}
		defer { link.invalidate() }
		link.start()
		await fulfillment(of: [finished], timeout: 2)
		XCTAssertFalse(link.isRunning)
		XCTAssertGreaterThanOrEqual(link.progress, 1)
	}

	func testIndefiniteAnimationContinuesUntilInvalidated() async {
		let advanced = expectation(description: "Spinner advances")
		var received = false
		let link = DisplayLink(duration: nil) { progress in
			if progress >= 2, !received {
				received = true
				advanced.fulfill()
			}
		}
		defer { link.invalidate() }
		link.start()
		await fulfillment(of: [advanced], timeout: 2)
		XCTAssertTrue(link.isRunning)
		link.invalidate()
		XCTAssertFalse(link.isRunning)
	}
}
