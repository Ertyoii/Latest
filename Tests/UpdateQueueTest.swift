//
//  UpdateQueueTest.swift
//  Latest Tests
//
//  Created by Codex on 28.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

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
