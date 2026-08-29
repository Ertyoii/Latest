//
//  UpdateCheckingService.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Combine
import Foundation

@MainActor
final class UpdateCheckingService: NSObject, ObservableObject, UpdateCheckProgressReporting {
	private enum ExternalURL {
		static let updatesPage = URL(string: "macappstore://apps.apple.com/updates")
	}

	@Published private(set) var isRunning = false
	@Published private(set) var isIndeterminate = false
	@Published private(set) var checkedApps = 0
	@Published private(set) var totalApps = 0
	private var currentCheckingGeneration: Int?
	private var activeCheckingBatches = 0
	private let coordinator: any UpdateCheckCoordinating
	private let appStoreUpdateService: any AppStoreUpdateServicing
	private let workspace: any ApplicationWorkspace

	init(
		coordinator: any UpdateCheckCoordinating = UpdateCheckCoordinator.shared,
		appStoreUpdateService: any AppStoreUpdateServicing = LiveAppStoreUpdateService.shared,
		workspace: any ApplicationWorkspace = MacApplicationWorkspace.shared
	) {
		self.coordinator = coordinator
		self.appStoreUpdateService = appStoreUpdateService
		self.workspace = workspace
	}

	var progressFraction: Double? {
		guard !isIndeterminate, totalApps > 0 else { return nil }
		return Double(checkedApps) / Double(max(totalApps, 1))
	}

	var hasUpdatesAvailable: Bool {
		!coordinator.appProvider.updatableApps.isEmpty
	}

	func startReportingProgress() {
		coordinator.progressDelegate = self
	}

	func stopReportingProgress() {
		if coordinator.progressDelegate === self {
			coordinator.progressDelegate = nil
		}
	}

	func checkForUpdates() {
		checkForUpdates(hardRefresh: true)
	}

	/// Startup can reuse short-lived App Store lookups; an explicit user refresh
	/// invalidates them so the command retains its expected force-refresh behavior.
	func checkForUpdates(hardRefresh: Bool) {
		startReportingProgress()
		coordinator.run(hardRefresh: hardRefresh)
	}

	func updateAll() {
		let apps = coordinator.appProvider.updatableApps

		if apps.contains(where: { $0.bundle.source == .appStore }) {
			do {
				try appStoreUpdateService.prepareForUpdates()
			} catch {
				guard let updatesPage = ExternalURL.updatesPage else { return }
				if !appStoreUpdateService.alwaysUsesManualUpdates {
					UpdateInstallHelperAlert.present(with: error, fallbackURL: updatesPage)
				} else {
					workspace.open(updatesPage)
				}
			}
		}

		apps.forEach { app in
			if !app.isUpdating {
				app.performUpdate(isBulkUpdate: true)
			}
		}
	}

	func updateCheckerDidStartScanningForApps(_ updateChecker: UpdateCheckCoordinator) {
		MigrationTelemetry.shared.scanStarted()
		isRunning = true
		isIndeterminate = true
		checkedApps = 0
		totalApps = 0
		currentCheckingGeneration = nil
		activeCheckingBatches = 0
	}

	func updateChecker(
		_ updateChecker: UpdateCheckCoordinator,
		didStartCheckingApps numberOfApps: Int,
		generation: Int
	) {
		if currentCheckingGeneration != generation {
			currentCheckingGeneration = generation
			activeCheckingBatches = 0
			checkedApps = 0
			totalApps = 0
		}

		let isFirstBatch = activeCheckingBatches == 0
		activeCheckingBatches += 1
		isRunning = true
		isIndeterminate = false
		if isFirstBatch {
			checkedApps = 0
			totalApps = numberOfApps
		} else {
			totalApps += numberOfApps
		}
	}

	func updateChecker(_ updateChecker: UpdateCheckCoordinator, didCheckApp: App) {
		checkedApps += 1
	}

	func updateCheckerDidFinishCheckingForUpdates(_ updateChecker: UpdateCheckCoordinator, generation: Int) {
		guard currentCheckingGeneration == generation else { return }
		activeCheckingBatches = max(0, activeCheckingBatches - 1)
		guard activeCheckingBatches == 0 else { return }
		currentCheckingGeneration = nil
		isRunning = false
		isIndeterminate = false
		MigrationTelemetry.shared.scanFinished(appCount: totalApps)
	}
}
