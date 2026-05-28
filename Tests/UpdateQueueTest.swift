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

}
