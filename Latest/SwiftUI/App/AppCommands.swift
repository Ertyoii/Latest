//
//  AppCommands.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit

@MainActor
final class AppCommands {
	private enum ExternalURL {
		static let website = URL(string: "https://max.codes/latest")
		static let donationPage = URL(string: "https://max.codes/latest/donate/")
	}

	private let updateCheckingService: UpdateCheckingService
	private let updatesListViewModel: UpdatesListViewModel
	private let searchFocusController: SearchFocusController

	init(
		updateCheckingService: UpdateCheckingService,
		updatesListViewModel: UpdatesListViewModel,
		searchFocusController: SearchFocusController
	) {
		self.updateCheckingService = updateCheckingService
		self.updatesListViewModel = updatesListViewModel
		self.searchFocusController = searchFocusController
	}

	func reload() {
		updateCheckingService.checkForUpdates()
	}

	func updateAll() {
		updateCheckingService.updateAll()
	}

	var selectedApp: App? {
		updatesListViewModel.selectedApp
	}

	var canUpdateSelectedApp: Bool {
		guard let selectedApp else { return false }
		return selectedApp.updateAvailable && !selectedApp.isUpdating
	}

	var canOpenSelectedApp: Bool {
		selectedApp != nil
	}

	func updateSelectedApp() {
		guard let selectedApp, canUpdateSelectedApp else { return }
		updatesListViewModel.update(selectedApp)
	}

	func openSelectedApp() {
		guard let selectedApp else { return }
		updatesListViewModel.open(selectedApp)
	}

	func revealSelectedAppInFinder() {
		guard let selectedApp else { return }
		updatesListViewModel.revealInFinder(selectedApp)
	}

	func focusSearch() {
		searchFocusController.focus()
	}

	func visitWebsite() {
		guard let url = ExternalURL.website else { return }
		NSWorkspace.shared.open(url)
	}

	func donate() {
		guard let url = ExternalURL.donationPage else { return }
		NSWorkspace.shared.open(url)
	}

	func changeSortOrder(_ order: AppListSettings.SortOptions) {
		AppListSettings.shared.sortOrder = order
	}

	func toggleShowInstalledUpdates() {
		AppListSettings.shared.showInstalledUpdates.toggle()
	}

	func toggleShowIgnoredUpdates() {
		AppListSettings.shared.showIgnoredUpdates.toggle()
	}
}
