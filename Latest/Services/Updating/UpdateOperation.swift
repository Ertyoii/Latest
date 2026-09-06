//
//  UpdateOperation.swift
//  Latest
//
//  Created by Max Langer on 01.07.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import Foundation
import Synchronization

extension Notification.Name {
  static let latestUpdateOperationDidFinish = Notification.Name("LatestUpdateOperationDidFinish")
}

/// The abstract update operation used for updating apps.
class UpdateOperation: StatefulOperation, @unchecked Sendable {

  typealias ProgressState = UpdateProgressState

  /// The app that is updated by this operation.
  let bundleIdentifier: String

  /// The identifier of the updated app.
  let appIdentifier: App.Bundle.Identifier

  private let completionNotificationLock = NSLock()

  private var didPostCompletionNotification = false

  private struct Progress: Sendable {
    var state: ProgressState = .pending
    var handler: (@Sendable (App.Bundle.Identifier) -> Void)?
  }
  private let progress = Mutex(Progress())

  /// OperationQueue requires unchecked inheritance. The mutable progress and
  /// handler are protected together; notifications always run outside the lock.
  var progressHandler: (@Sendable (App.Bundle.Identifier) -> Void)? {
    get { progress.withLock { $0.handler } }
    set {
      progress.withLock { $0.handler = newValue }
      newValue?(appIdentifier)
    }
  }

  var progressState: ProgressState {
    get { progress.withLock { $0.state } }
    set {
      let handler = progress.withLock { progress in
        progress.state = newValue
        return progress.handler
      }
      handler?(appIdentifier)
    }
  }

  /// Initializes the operation with the given app and progress handler.
  init(bundleIdentifier: String, appIdentifier: App.Bundle.Identifier) {
    self.bundleIdentifier = bundleIdentifier
    self.appIdentifier = appIdentifier
  }

  // MARK: - Operation sub-classing

  override func execute() {
    self.progressState = .initializing
  }

  override func cancel() {
    super.cancel()
    self.progressState = .cancelling
  }

  override func finish() {
    let didCompleteSuccessfully =
      self.error == nil && !self.isCancelled && self.markCompletionNotificationPending()

    if let error = self.error {
      self.progressState = .error(error)
    } else {
      self.progressState = .none
    }

    super.finish()

    if didCompleteSuccessfully {
      NotificationCenter.default.post(
        name: .latestUpdateOperationDidFinish, object: self,
        userInfo: [
          Self.appIdentifierUserInfoKey: self.appIdentifier
        ])
    }
  }

  private func markCompletionNotificationPending() -> Bool {
    completionNotificationLock.withCriticalScope {
      guard !didPostCompletionNotification else {
        return false
      }

      didPostCompletionNotification = true
      return true
    }
  }

}

extension UpdateOperation {
  static let appIdentifierUserInfoKey = "appIdentifier"
}
