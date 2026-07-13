//
//  UpdatesListViewModel.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Combine

@MainActor
final class UpdatesListViewModel: ObservableObject {
	private static let badgeNumberFormatter = NumberFormatter()

	@Published private(set) var snapshot: AppListSnapshot
	private(set) var snapshotRevision = 0
	@Published var selectedApp: App?
	@Published var searchQuery = ""
	@Published private(set) var statusText = ""

	private var observationTasks = [Task<Void, Never>]()
	private var selectionWasUserInitiated = false

	init() {
		self.snapshot = AppListSnapshot(withApps: [], filterQuery: nil)
		updateTitleAndBadge()
	}

	func startObserving() {
		guard observationTasks.isEmpty else { return }

		observationTasks = [
			Task { [weak self] in
				for await _ in AppListSettings.shared.updates() {
					guard !Task.isCancelled, let self else { break }
					self.refreshSnapshot()
				}
			},
			Task { [weak self] in
				for await apps in UpdateCheckCoordinator.shared.appProvider.updates() {
					guard !Task.isCancelled, let self else { break }
					self.replaceSnapshot(with: AppListSnapshot(withApps: apps, filterQuery: self.normalizedSearchQuery))
					self.maintainSelectionAfterSnapshotChange()
					self.updateTitleAndBadge()
				}
			}
		]
	}

	func stopObserving() {
		observationTasks.forEach { $0.cancel() }
		observationTasks.removeAll()
	}

	func setSearchQuery(_ query: String) {
		guard query != searchQuery else { return }
		searchQuery = query
		replaceSnapshot(with: snapshot.refiltered(with: normalizedSearchQuery))
		maintainSelectionAfterSnapshotChange()
	}

	func select(_ app: App?) {
		selectionWasUserInitiated = true
		selectedApp = app
	}

	func update(_ app: App) {
		app.performUpdate()
	}

	func open(_ app: App) {
		app.open()
	}

	func revealInFinder(_ app: App) {
		app.showInFinder()
	}

	func setIgnored(_ ignored: Bool, for app: App) {
		UpdateCheckCoordinator.shared.appProvider.setIgnoredState(ignored, for: app)
	}

	var hasUpdatesAvailable: Bool {
		!UpdateCheckCoordinator.shared.appProvider.updatableApps.isEmpty
	}

	private var normalizedSearchQuery: String? {
		searchQuery.isEmpty ? nil : searchQuery
	}

	private func refreshSnapshot() {
		replaceSnapshot(with: snapshot.updated(with: normalizedSearchQuery))
		maintainSelectionAfterSnapshotChange()
		updateTitleAndBadge()
	}

	private func replaceSnapshot(with snapshot: AppListSnapshot) {
		snapshotRevision &+= 1
		self.snapshot = snapshot
	}

	private func maintainSelectionAfterSnapshotChange() {
		if selectionWasUserInitiated,
		   let selectedApp,
		   snapshot.firstIndex(of: selectedApp) != nil {
			return
		}

		if selectionWasUserInitiated {
			selectionWasUserInitiated = false
		}
		selectedApp = snapshot.sections.first?.apps.first
	}

	private func updateTitleAndBadge() {
		let showExternalUpdates = AppListSettings.shared.includeAppsWithLimitedSupport
		let count = UpdateCheckCoordinator.shared.appProvider.countOfAvailableUpdates { app in
			showExternalUpdates || app.usesBuiltInUpdater
		}

		NSApplication.shared.dockTile.badgeLabel = count == 0
			? nil
			: Self.badgeNumberFormatter.string(from: count as NSNumber)

		let format = NSLocalizedString("NumberOfUpdatesAvailable", comment: "number of updates available")
		statusText = String.localizedStringWithFormat(format, count)
	}
}
