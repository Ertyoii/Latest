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
class SparkleUpdateOperation: UpdateOperation, @unchecked Sendable {
    /// The updater used to update this app.
    private var updater: SPUUpdater?

    // Callback to be called when the operation has been cancelled
    fileprivate var cancellationCallback: (() -> Void)?

    /// Schedules an progress update notification.
    private let progressScheduler: DispatchSourceUserDataAdd

    /// Initializes the operation with the given Sparkle app and handler
    override init(bundleIdentifier: String, appIdentifier: App.Bundle.Identifier) {
        progressScheduler = DispatchSource.makeUserDataAddSource(queue: .global())
        super.init(bundleIdentifier: bundleIdentifier, appIdentifier: appIdentifier)

        // Delay notifying observers to only let that notification occur in a certain interval
        progressScheduler.setEventHandler { [weak self] in
            guard let self else { return }

            // Notify the progress state
            progressState = .downloading(loadedSize: Int64(receivedLength), totalSize: Int64(expectedContentLength))

            // Delay the next call for 1 second
            Thread.sleep(forTimeInterval: 1)
        }

        progressScheduler.activate()
    }

    // MARK: - Operation Overrides

    override func execute() {
        super.execute()

        // Gather app and app bundle
        guard let bundle = Bundle(identifier: bundleIdentifier) else {
            finish(with: LatestError.updateInfoUnavailable)
            return
        }

        DispatchQueue.main.async {
            // Instantiate a new updater that performs the update
            let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: self, delegate: self)

            do {
                try updater.start()
            } catch {
                self.finish(with: error)
            }

            updater.checkForUpdates()

            self.updater = updater
        }
    }

    override func cancel() {
        super.cancel()

        cancellationCallback?()
        finish()
    }

    override func finish() {
        // Cleanup updater
        updater = nil

        super.finish()
    }

    // MARK: - Downloading

    /// The estimated total length of the downloaded app bundle.
    fileprivate var expectedContentLength: UInt64 = 0

    /// The length of already downloaded data.
    fileprivate var receivedLength: UInt64 = 0

    // MARK: - Installation

    /// Whether the app is open.
    fileprivate var isAppOpen = false

    /// One instance of the currently updating application.
    fileprivate var runningApplication: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == self.bundleIdentifier })
    }
}

// MARK: - Driver Implementation

extension SparkleUpdateOperation: SPUUserDriver {
    // MARK: - Preparing Update

    func show(_: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(.init(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation _: @escaping () -> Void) {
        progressState = .initializing
    }

    func showUpdateFound(with _: SUAppcastItem, state _: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(isCancelled ? .dismiss : .install)
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        finish(with: error)
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        finish(with: error)
        acknowledgement()
    }

    func showUpdateInstalledAndRelaunched(_: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        finish()
    }

    func showUpdateInFocus() {
        // Noop
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        if isCancelled {
            cancellation()
            return
        }

        cancellationCallback = cancellation
    }

    // MARK: - Downloading Update

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        // This should be only called once per download. If it Uis called more than once, reset the progress
        self.expectedContentLength = expectedContentLength
        receivedLength = 0

        scheduleProgressHandler()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length

        // Expected content length may be wrong, adjust if needed
        expectedContentLength = max(expectedContentLength, receivedLength)

        scheduleProgressHandler()
    }

    private func scheduleProgressHandler() {
        progressScheduler.add(data: 1)
    }

    // MARK: - Installing Update

    func showDownloadDidStartExtractingUpdate() {
        progressState = .extracting(progress: 0)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        progressState = .extracting(progress: progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Check whether app is open
        isAppOpen = runningApplication != nil

        reply(isCancelled ? .dismiss : .install)
    }

    func showInstallingUpdate(withApplicationTerminated _: Bool, retryTerminatingApplication _: @escaping () -> Void) {
        progressState = .installing
    }

    // MARK: - Ignored Methods

    func showCanCheck(forUpdates _: Bool) {}
    func dismissUserInitiatedUpdateCheck() {}
    func showUpdateReleaseNotes(with _: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_: Error) {}
    func showSendingTerminationSignal() {}
    func dismissUpdateInstallation() {}
}

extension SparkleUpdateOperation: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        // We can try to supply a valid feed as addition to Sparkle's own methods.
        // For some cases (like DevMate) Sparkle fails to retrieve an appcast by itself.
        Sparke.feedURL(from: updater.hostBundle)?.absoluteString
    }
}
