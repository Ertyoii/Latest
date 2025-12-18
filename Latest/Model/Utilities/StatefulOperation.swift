//
//  StatefulOperation.swift
//  Latest
//
//  Created by Max Langer on 01.07.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import Foundation

/// An convenience operation adding state to Operations.
class StatefulOperation: Operation, @unchecked Sendable {
    // MARK: State Management

    override class func keyPathsForValuesAffectingValue(forKey key: String) -> Set<String> {
        switch key {
        case "isFinished", "isExecuting", "isReady":
            ["state"]

        default:
            []
        }
    }

    /// The states this `Operation` can be in.
    private enum State: Int {
        /// The initial state of an `Operation`.
        case ready

        /// The `Operation` is executing.
        case executing

        /// The `Operation` has finished executing.
        case finished
    }

    /// Private storage for the `state` property.
    private var _state = State.ready

    /// A lock to guard reads and writes to the `_state` property
    private let stateLock = NSLock()

    /// The actual state of the operation
    private var state: State {
        get {
            stateLock.withCriticalScope(block: {
                self._state
            })
        }

        set(newState) {
            willChangeValue(forKey: "state")

            stateLock.withCriticalScope {
                guard _state != .finished else {
                    return
                }

                _state = newState
            }

            didChangeValue(forKey: "state")
        }
    }

    /// Whether the operation is currently executing
    override final var isExecuting: Bool {
        state == .executing
    }

    /// Whether the operation is finished
    override final var isFinished: Bool {
        state == .finished
    }

    // MARK: - Execution

    override final func start() {
        // NSOperation.start() contains important logic that shouldn't be bypassed.
        super.start()

        // If the operation has been cancelled, we still need to enter the "Finished" state.
        if !isCancelled {
            state = .executing

            execute()
        } else {
            finish()
        }
    }

    /**
     `execute()` is the entry point of execution for all `StatefulOperation` subclasses.
     If you subclass `StatefulOperation` and wish to customize its execution, you would
     do so by overriding the `execute()` method.

     At some point, your `StatefulOperation` subclass must call one of the "finish"
     methods defined below; this is how you indicate that your operation has
     finished its execution.
     */
    func execute() {
        fatalError("\(type(of: self)) must override `execute()`.")
    }

    func finish() {
        state = .finished
    }

    /// The error raised during execution
    private(set) var error: Error?

    func finish(with error: Error) {
        self.error = error
        finish()
    }
}

extension NSLock {
    func withCriticalScope<T>(block: () -> T) -> T {
        lock()
        let value = block()
        unlock()
        return value
    }

    func withCriticalScope(block: () -> Void) {
        lock()
        block()
        unlock()
    }
}
