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
