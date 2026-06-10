//
//  AppLibrary.swift
//  Latest
//
//  Created by Max Langer on 08.01.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import Foundation

/// Observes the local collection of apps and notifies its owner of changes.
class AppLibrary: @unchecked Sendable {

	/// The handler to be called when apps change locally.
	typealias UpdateHandler = ([App.Bundle]) -> Void
	let updateHandler: UpdateHandler

	/// The handler to be called when a full reload completed.
	typealias ReloadHandler = @Sendable ([App.Bundle]) -> Void

	/// A list of all application bundles that are available locally.
	var bundles: [App.Bundle] {
		stateQueue.sync {
			currentBundles()
		}
	}

	private var directories = [URL: AppDirectory]()

	/// Initializes the library with the given handler for updates.
	init(handler: @escaping UpdateHandler) {
		self.updateHandler = handler
	}

	private let stateQueue = DispatchQueue(label: "AppLibraryStateQueue")

	private var scheduledUpdateWorkItem: DispatchWorkItem?

	private static let updateCoalescingInterval: TimeInterval = 0.5


	// MARK: - Actions

	/// Starts the update checking process
	func startQuery() {
		stateQueue.async { [weak self] in
			guard let self else { return }
			self.setupDirectoryObservers()
		}
	}

	/// Forces all observed directories to be read from disk again.
	func reload(handler: @escaping ReloadHandler) {
		stateQueue.async { [weak self] in
			guard let self else { return }
			self.setupDirectoryObservers()
			self.refreshDirectories(handler: handler)
		}
	}

	private func setupDirectoryObservers() {
		// Use a dispatch group for the initial setup to get contents for all directories before gathering apps
		let isInitialSetup = self.directories.isEmpty
		let dispatchGroup = isInitialSetup ? DispatchGroup() : nil

		// Setup directories
		let observedDirectories: [(URL, AppDirectory)] = directoryStore.URLs.compactMap { url in
			// Skip unreachable directories
			guard directoryStore.isReachable(url) else { return nil }

			// Reuse existing directory observations if possible
			if let directory = directories[url] {
				return (url, directory)
			}

			let directory: AppDirectory
			let updateHandler: AppDirectory.UpdateHandler = { [weak self] in
				// Schedule update and coalesce bursts of file-system events.
				self?.scheduleUpdate()
			}

			if isInitialSetup {
				dispatchGroup?.enter()
				directory = AppDirectory(
					url: url,
					notifyOnInitialCollection: false,
					initialCollectionCompletion: {
						dispatchGroup?.leave()
					},
					updateHandler: updateHandler
				)
			} else {
				directory = AppDirectory(url: url, updateHandler: updateHandler)
			}

			return (url, directory)
		}
		directories = Dictionary(uniqueKeysWithValues: observedDirectories)

		dispatchGroup?.notify(queue: stateQueue) {
			// Call update immediately. Using the scheduler delays the update.
			self.performUpdate()
		}
	}

	private func performUpdate() {
		updateHandler(currentBundles())
	}

	private func refreshDirectories(handler: @escaping ReloadHandler) {
		let dispatchGroup = DispatchGroup()

		for directory in directories.values {
			dispatchGroup.enter()
			directory.refresh {
				dispatchGroup.leave()
			}
		}

		dispatchGroup.notify(queue: stateQueue) {
			handler(self.currentBundles())
		}
	}

	private func scheduleUpdate() {
		stateQueue.async { [weak self] in
			guard let self else { return }
			self.scheduleUpdateOnStateQueue()
		}
	}

	private func scheduleUpdateOnStateQueue() {
		self.scheduledUpdateWorkItem?.cancel()

		let workItem = DispatchWorkItem { [weak self] in
			self?.performUpdate()
		}
		self.scheduledUpdateWorkItem = workItem

		self.stateQueue.asyncAfter(deadline: .now() + Self.updateCoalescingInterval, execute: workItem)
	}

	private func currentBundles() -> [App.Bundle] {
		directories.flatMap { $0.value.bundles }
	}



	// MARK: - Directory Handling

	/// The store handling application directories.
	private lazy var directoryStore = {
		AppDirectoryStore(updateHandler: self.startQuery)
	}()

}
