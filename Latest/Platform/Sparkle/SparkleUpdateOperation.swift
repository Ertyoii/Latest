//
//  SparkleUpdateOperation.swift
//  Latest
//
//  Created by Max Langer on 01.07.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import AppKit
import Sparkle

/// The operation updating Sparkle apps.
final class SparkleUpdateOperation: UpdateOperation, @unchecked Sendable {

  // Sparkle's driver callbacks run on the main actor. OperationQueue entry
  // points hop there before touching the updater or its download state.
  @MainActor private var updater: SPUUpdater?
  @MainActor private var cancellationCallback: (() -> Void)?
  @MainActor private var progressTask: Task<Void, Never>?
  @MainActor private var expectedContentLength: UInt64 = 0
  @MainActor private var receivedLength: UInt64 = 0

  // MARK: - Operation Overrides

  override func execute() {
    super.execute()

    // Gather app and app bundle
    guard let bundle = Bundle(path: self.appIdentifier.path) else {
      self.finish(with: LatestError.updateInfoUnavailable)
      return
    }

    Task { @MainActor in
      guard !self.isCancelled, !self.isFinished else { return }
      // Instantiate a new updater that performs the update
      let updater = SPUUpdater(
        hostBundle: bundle, applicationBundle: bundle, userDriver: self, delegate: self)

      do {
        try updater.start()
      } catch let error {
        self.finish(with: error)
        return
      }

      guard !self.isCancelled, !self.isFinished else { return }
      self.updater = updater
      updater.checkForUpdates()
    }
  }

  override func cancel() {
    super.cancel()

    self.finish()
  }

  override func finish() {
    super.finish()
    Task { @MainActor in
      self.cancelProgressNotification()
      let cancellation = self.cancellationCallback
      self.cancellationCallback = nil
      if self.isCancelled { cancellation?() }
      self.updater = nil
    }
  }

}

// MARK: - Driver Implementation
extension SparkleUpdateOperation: SPUUserDriver {

  // MARK: - Preparing Update

  func show(
    _ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void
  ) {
    reply(.init(automaticUpdateChecks: false, sendSystemProfile: false))
  }

  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    guard !isCancelled, !isFinished else {
      cancellation()
      return
    }
    cancellationCallback = cancellation
    self.progressState = .initializing
  }

  func showUpdateFound(
    with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
    reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
    reply(self.isCancelled ? .dismiss : .install)
  }

  func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
    self.finish(with: error)
    acknowledgement()
  }

  func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
    self.finish(with: error)
    acknowledgement()
  }

  func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
    acknowledgement()
    self.finish()
  }

  func showUpdateInFocus() {
    // Noop
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) {
    if self.isCancelled || self.isFinished {
      cancellation()
      return
    }

    self.cancellationCallback = cancellation
  }

  // MARK: - Downloading Update

  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    // A replacement download (for example after a failed delta) resets progress.
    self.expectedContentLength = expectedContentLength
    self.receivedLength = 0

    self.scheduleProgressHandler()
  }

  func showDownloadDidReceiveData(ofLength length: UInt64) {
    self.receivedLength += length

    // Expected content length may be wrong, adjust if needed
    self.expectedContentLength = max(self.expectedContentLength, self.receivedLength)

    self.scheduleProgressHandler()
  }

  @MainActor
  private func scheduleProgressHandler() {
    guard progressTask == nil, !isCancelled, !isFinished else { return }
    progressTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
      guard let self else { return }
      self.progressTask = nil
      guard !self.isCancelled, !self.isFinished else { return }
      self.progressState = .downloading(
        loadedSize: Int64(clamping: self.receivedLength),
        totalSize: Int64(clamping: self.expectedContentLength))
    }
  }

  @MainActor
  private func cancelProgressNotification() {
    progressTask?.cancel()
    progressTask = nil
  }

  // MARK: - Installing Update

  func showDownloadDidStartExtractingUpdate() {
    cancelProgressNotification()
    self.progressState = .extracting(progress: 0)
  }

  func showExtractionReceivedProgress(_ progress: Double) {
    cancelProgressNotification()
    self.progressState = .extracting(progress: progress)
  }

  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    reply(self.isCancelled ? .dismiss : .install)
  }

  func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {
    cancelProgressNotification()
    self.progressState = .installing
  }

  // MARK: - Ignored Methods

  func showCanCheck(forUpdates canCheckForUpdates: Bool) {}
  func dismissUserInitiatedUpdateCheck() {}
  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
  func showSendingTerminationSignal() {}
  func dismissUpdateInstallation() {}

}

extension SparkleUpdateOperation: SPUUpdaterDelegate {

  func feedURLString(for updater: SPUUpdater) -> String? {
    // We can try to supply a valid feed as addition to Sparkle's own methods.
    // For some cases (like DevMate) Sparkle fails to retrieve an appcast by itself.
    return SparkleFeed.feedURL(from: updater.hostBundle)?.absoluteString
  }

}
