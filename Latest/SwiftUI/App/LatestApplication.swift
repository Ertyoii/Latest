//
//  LatestApplication.swift
//  Latest
//
//  Created by Codex on 11.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class ApplicationLifecycleDelegate: NSObject, NSApplicationDelegate {
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		true
	}
}

@MainActor
final class AppUpdateController: ObservableObject {
	private let updaterController = SPUStandardUpdaterController(
		startingUpdater: true,
		updaterDelegate: nil,
		userDriverDelegate: nil
	)

	func checkForAppUpdates() {
		updaterController.checkForUpdates(nil)
	}
}

struct LatestApplication: SwiftUI.App {
	@NSApplicationDelegateAdaptor(ApplicationLifecycleDelegate.self)
	private var lifecycleDelegate

	@StateObject private var environment = AppEnvironment.live()
	@StateObject private var appUpdateController = AppUpdateController()

	var body: some Scene {
		Window("Latest", id: "main") {
			LatestRootView(environment: environment)
				.frame(
					minWidth: VisualMetrics.mainWindowMinWidth,
					minHeight: VisualMetrics.mainWindowMinHeight
				)
				.onAppear {
					environment.start()
				}
				.onDisappear {
					environment.stop()
				}
		}
		.defaultSize(
			width: VisualMetrics.mainWindowDefaultWidth,
			height: VisualMetrics.mainWindowDefaultHeight
		)
		.windowResizability(.contentMinSize)
		.windowToolbarStyle(.unified)
		.commands {
			LatestCommands(
				appCommands: environment.commands,
				updatesViewModel: environment.updatesListViewModel,
				updateCheckingService: environment.updateCheckingService,
				appUpdateController: appUpdateController
			)
		}

		Settings {
			SettingsRootView()
		}
	}
}

private struct LatestRootView: View {
	let environment: AppEnvironment

	@ObservedObject private var updatesViewModel: UpdatesListViewModel
	@ObservedObject private var updateCheckingService: UpdateCheckingService

	init(environment: AppEnvironment) {
		self.environment = environment
		_updatesViewModel = ObservedObject(wrappedValue: environment.updatesListViewModel)
		_updateCheckingService = ObservedObject(wrappedValue: environment.updateCheckingService)
	}

	var body: some View {
		NavigationSplitView {
			UpdatesSidebarView(
				viewModel: updatesViewModel,
				searchFocusController: environment.searchFocusController
			)
		} detail: {
			ReleaseNotesDetailView(updatesViewModel: updatesViewModel)
				.frame(minWidth: VisualMetrics.detailMinWidth)
		}
		.navigationSplitViewStyle(.balanced)
		.navigationTitle("Latest")
		.navigationSubtitle(updatesViewModel.statusText)
		.toolbar {
			ToolbarItemGroup(placement: .primaryAction) {
				updateProgress

				Button {
					environment.commands.updateAll()
				} label: {
					Label("Update All", systemImage: "square.and.arrow.down.on.square")
				}
				.disabled(!updatesViewModel.hasUpdatesAvailable)

				Button {
					environment.commands.reload()
				} label: {
					Label("Check for Updates", systemImage: "arrow.clockwise")
				}
				.disabled(updateCheckingService.isRunning)
			}
		}
	}

	@ViewBuilder
	private var updateProgress: some View {
		if updateCheckingService.isRunning {
			if let progress = updateCheckingService.progressFraction {
				ProgressView(value: progress)
					.frame(width: 64)
					.accessibilityLabel("Checking for updates")
			} else {
				ProgressView()
					.controlSize(.small)
					.accessibilityLabel("Scanning applications")
			}
		}
	}
}
