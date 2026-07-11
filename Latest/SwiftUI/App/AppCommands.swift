//
//  AppCommands.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

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

struct LatestCommands: Commands {
	let appCommands: AppCommands
	@ObservedObject var updatesViewModel: UpdatesListViewModel
	@ObservedObject var updateCheckingService: UpdateCheckingService
	@ObservedObject var appUpdateController: AppUpdateController

	var body: some Commands {
		CommandMenu("Updates") {
			Button("Check for App Updates…") {
				appUpdateController.checkForAppUpdates()
			}

			Divider()

			Button("Check Installed Apps") {
				appCommands.reload()
			}
			.keyboardShortcut("r")
			.disabled(updateCheckingService.isRunning)

			Button("Update All") {
				appCommands.updateAll()
			}
			.keyboardShortcut("u", modifiers: [.command, .shift])
			.disabled(!updatesViewModel.hasUpdatesAvailable)

			Button(updateSelectedTitle) {
				appCommands.updateSelectedApp()
			}
			.keyboardShortcut("u")
			.disabled(!appCommands.canUpdateSelectedApp)

			Divider()

			Button("Open") {
				appCommands.openSelectedApp()
			}
			.keyboardShortcut("o", modifiers: [.command, .shift])
			.disabled(!appCommands.canOpenSelectedApp)

			Button("Show in Finder") {
				appCommands.revealSelectedAppInFinder()
			}
			.keyboardShortcut("r", modifiers: [.command, .shift])
			.disabled(!appCommands.canOpenSelectedApp)
		}

		CommandGroup(after: .textEditing) {
			Button("Find…") {
				appCommands.focusSearch()
			}
			.keyboardShortcut("f")
		}

		CommandMenu("View Options") {
			Menu("Sort By") {
				ForEach(AppListSettings.SortOptions.allCases, id: \.rawValue) { order in
					Button {
						appCommands.changeSortOrder(order)
					} label: {
						if AppListSettings.shared.sortOrder == order {
							Label(order.displayName, systemImage: "checkmark")
						} else {
							Text(order.displayName)
						}
					}
				}
			}

			Toggle("Show Installed Apps", isOn: showInstalledApps)
				.keyboardShortcut("i")
			Toggle("Show Ignored Apps", isOn: showIgnoredApps)
				.keyboardShortcut("i", modifiers: [.command, .shift])
		}

		CommandGroup(after: .help) {
			Button("Visit Latest Website") {
				appCommands.visitWebsite()
			}
			Button("Donate") {
				appCommands.donate()
			}
		}
	}

	private var updateSelectedTitle: String {
		guard let app = appCommands.selectedApp else {
			return NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
		}
		if let externalUpdater = app.externalUpdaterName {
			return String(
				format: NSLocalizedString(
					"ExternalUpdateAction",
					comment: "Action to update a given app outside of Latest."
				),
				externalUpdater
			)
		}
		return NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
	}

	private var showInstalledApps: Binding<Bool> {
		Binding(
			get: { AppListSettings.shared.showInstalledUpdates },
			set: { AppListSettings.shared.showInstalledUpdates = $0 }
		)
	}

	private var showIgnoredApps: Binding<Bool> {
		Binding(
			get: { AppListSettings.shared.showIgnoredUpdates },
			set: { AppListSettings.shared.showIgnoredUpdates = $0 }
		)
	}
}
