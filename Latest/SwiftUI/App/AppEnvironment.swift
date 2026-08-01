//
//  AppEnvironment.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
	let searchFocusController: SearchFocusController
	let updateCheckingService: UpdateCheckingService
	let updatesListViewModel: UpdatesListViewModel
	let commands: AppCommands

	init(
		searchFocusController: SearchFocusController = SearchFocusController(),
		updateCheckingService: UpdateCheckingService = UpdateCheckingService(),
		updatesListViewModel: UpdatesListViewModel = UpdatesListViewModel()
	) {
		self.searchFocusController = searchFocusController
		self.updateCheckingService = updateCheckingService
		self.updatesListViewModel = updatesListViewModel
		self.commands = AppCommands(
			updateCheckingService: updateCheckingService,
			updatesListViewModel: updatesListViewModel,
			searchFocusController: searchFocusController
		)
	}

	static func live() -> AppEnvironment {
		AppEnvironment()
	}

	func start() {
		MigrationTelemetry.shared.applicationStarted()
		updateCheckingService.startReportingProgress()
		updatesListViewModel.startObserving()
		Task {
			await ReleaseNotesSourceCatalog.refresh()
		}
		updateCheckingService.checkForUpdates(hardRefresh: false)
	}

	func stop() {
		updatesListViewModel.stopObserving()
		updateCheckingService.stopReportingProgress()
	}
}
