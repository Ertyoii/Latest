//
//  UpdateQueue.swift
//  Latest
//
//  Created by Max Langer on 01.07.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import Foundation

/// The queue where update operations are scheduled on.
class UpdateQueue: OperationQueue, @unchecked Sendable {

  // MARK: - Initialization
  override init() {
    super.init()

    self.maxConcurrentOperationCount = 3
  }

  /// The shared instance of the queue.
  static let shared = UpdateQueue()

  private let operationIndexLock = NSLock()

  private var operationsByIdentifier = [App.Bundle.Identifier: UpdateOperation]()

  // MARK: - Public Methods

  /// Cancels the update operation for the given app.
  func cancelUpdate(for identifier: App.Bundle.Identifier) {
    guard let operation = self.operation(for: identifier) else { return }
    operation.cancel()
  }

  /// Whether the queue contains an update operation for the given app.
  func contains(_ identifier: App.Bundle.Identifier) -> Bool {
    return self.operation(for: identifier) != nil
  }

  /// Returns the state for a given app.
  func state(for identifier: App.Bundle.Identifier) -> UpdateOperation.ProgressState {
    return self.operation(for: identifier)?.progressState ?? .none
  }

  override func addOperation(_ op: Operation) {
    // Abort if the operation is of an unknown type
    guard let operation = op as? UpdateOperation else {
      assertionFailure("Added unknown operation \(op.self) to update queue.")
      return
    }

    // Abort if the app is already in the queue
    guard index(operation) else {
      return
    }

    let previousCompletionBlock = operation.completionBlock
    operation.completionBlock = { [weak self, weak operation] in
      previousCompletionBlock?()

      guard let operation else { return }
      self?.removeIndexedOperation(operation)
    }

    operation.progressHandler = { [weak self] identifier in
      self?.publishState(for: identifier)
    }

    super.addOperation(op)
  }

  // MARK: - State Feeds

  /// Bounded structured-concurrency feeds used by SwiftUI rows.
  @MainActor private var stateContinuations = [
    App.Bundle.Identifier: [UUID: AsyncStream<UpdateOperation.ProgressState>.Continuation]
  ]()

  @MainActor
  func states(for identifier: App.Bundle.Identifier) -> AsyncStream<UpdateOperation.ProgressState> {
    makeStateFeed(for: identifier, includesCurrentState: true).changes
  }

  /// Atomically captures the current state and registers a stream containing
  /// only subsequent changes. SwiftUI state owners use this to avoid publishing
  /// the same initial value while their view is being constructed.
  @MainActor
  func stateChanges(
    for identifier: App.Bundle.Identifier
  ) -> UpdateStateFeed {
    makeStateFeed(for: identifier, includesCurrentState: false)
  }

  @MainActor
  private func makeStateFeed(for identifier: App.Bundle.Identifier, includesCurrentState: Bool)
    -> UpdateStateFeed
  {
    let streamIdentifier = UUID()
    let currentState = state(for: identifier)
    let (stream, continuation) = AsyncStream.makeStream(
      of: UpdateOperation.ProgressState.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    stateContinuations[identifier, default: [:]][streamIdentifier] = continuation
    if includesCurrentState {
      continuation.yield(currentState)
    }
    continuation.onTermination = { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.removeStateContinuation(streamIdentifier, for: identifier)
      }
    }
    return (currentState, stream)
  }

  /// Delivers progress to the app's bounded state feeds.
  private func publishState(for identifier: App.Bundle.Identifier) {
    let state = self.state(for: identifier)

    Task { @MainActor in
      if let continuations = self.stateContinuations[identifier] {
        for continuation in continuations.values {
          continuation.yield(state)
        }
      }
    }
  }

  @MainActor
  private func removeStateContinuation(
    _ streamIdentifier: UUID, for identifier: App.Bundle.Identifier
  ) {
    stateContinuations[identifier]?.removeValue(forKey: streamIdentifier)
    if stateContinuations[identifier]?.isEmpty == true {
      stateContinuations.removeValue(forKey: identifier)
    }
  }

  // MARK: - Helper

  /// Returns the operation for the given app.
  private func operation(for identifier: App.Bundle.Identifier) -> UpdateOperation? {
    operationIndexLock.withLock {
      guard let operation = operationsByIdentifier[identifier] else {
        return nil
      }

      if operation.isFinished {
        operationsByIdentifier[identifier] = nil
        return nil
      }

      return operation
    }
  }

  private func index(_ operation: UpdateOperation) -> Bool {
    operationIndexLock.withLock {
      if let existingOperation = operationsByIdentifier[operation.appIdentifier],
        !existingOperation.isFinished
      {
        return false
      }

      operationsByIdentifier[operation.appIdentifier] = operation
      return true
    }
  }

  private func removeIndexedOperation(_ operation: UpdateOperation) {
    operationIndexLock.withLock {
      guard operationsByIdentifier[operation.appIdentifier] === operation else {
        return
      }

      operationsByIdentifier[operation.appIdentifier] = nil
    }
  }

}
