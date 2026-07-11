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
final class UpdatesListViewModel: NSObject, ObservableObject, Observer {
	private static let badgeNumberFormatter = NumberFormatter()

	nonisolated let id = UUID()

	@Published private(set) var snapshot: AppListSnapshot
	private(set) var snapshotRevision = 0
	@Published var selectedApp: App?
	@Published var searchQuery = ""
	@Published private(set) var statusText = ""

	private var isObserving = false

	override init() {
		self.snapshot = AppListSnapshot(withApps: [], filterQuery: nil)
		super.init()
		updateTitleAndBadge()
	}

	func startObserving() {
		guard !isObserving else { return }
		isObserving = true

		AppListSettings.shared.add(self) { [weak self] in
			self?.refreshSnapshot()
		}

		UpdateCheckCoordinator.shared.appProvider.addObserver(self) { [weak self] apps in
			guard let self else { return }
			self.replaceSnapshot(with: AppListSnapshot(withApps: apps, filterQuery: self.normalizedSearchQuery))
			self.maintainSelectionAfterSnapshotChange()
			self.updateTitleAndBadge()
		}
	}

	func stopObserving() {
		guard isObserving else { return }
		isObserving = false
		AppListSettings.shared.removeObserver(withID: id)
		UpdateCheckCoordinator.shared.appProvider.removeObserver(self)
	}

	func setSearchQuery(_ query: String) {
		guard query != searchQuery else { return }
		searchQuery = query
		replaceSnapshot(with: snapshot.refiltered(with: normalizedSearchQuery))
		maintainSelectionAfterSnapshotChange()
	}

	func select(_ app: App?) {
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
		guard let selectedApp else { return }
		if snapshot.firstIndex(of: selectedApp) == nil {
			self.selectedApp = nil
		}
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
