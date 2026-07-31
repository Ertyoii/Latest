//
//  UpdateCheckingService.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Combine

@MainActor
final class UpdateCheckingService: NSObject, ObservableObject, UpdateCheckProgressReporting {
	private enum ExternalURL {
		static let updatesPage = URL(string: "macappstore://apps.apple.com/updates")
	}

	@Published private(set) var isRunning = false
	@Published private(set) var isIndeterminate = false
	@Published private(set) var checkedApps = 0
	@Published private(set) var totalApps = 0

	var progressFraction: Double? {
		guard !isIndeterminate, totalApps > 0 else { return nil }
		return Double(checkedApps) / Double(max(totalApps, 1))
	}

	var hasUpdatesAvailable: Bool {
		!UpdateCheckCoordinator.shared.appProvider.updatableApps.isEmpty
	}

	func startReportingProgress() {
		UpdateCheckCoordinator.shared.progressDelegate = self
	}

	func stopReportingProgress() {
		if UpdateCheckCoordinator.shared.progressDelegate === self {
			UpdateCheckCoordinator.shared.progressDelegate = nil
		}
	}

	func checkForUpdates() {
		startReportingProgress()
		UpdateCheckCoordinator.shared.run()
	}

	func updateAll() {
		let apps = UpdateCheckCoordinator.shared.appProvider.updatableApps

		if apps.contains(where: { $0.bundle.source == .appStore }) {
			do {
				try AppStoreUpdater.prepareForUpdates()
			} catch {
				guard let updatesPage = ExternalURL.updatesPage else { return }
				if !AppStoreUpdateSettings.alwaysPerformManualUpdates.active {
					UpdateInstallHelperAlert.present(with: error, fallbackURL: updatesPage)
				} else {
					NSWorkspace.shared.open(updatesPage)
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
	}

	func updateChecker(_ updateChecker: UpdateCheckCoordinator, didStartCheckingApps numberOfApps: Int) {
		isRunning = true
		isIndeterminate = false
		checkedApps = 0
		totalApps = numberOfApps
	}

	func updateChecker(_ updateChecker: UpdateCheckCoordinator, didCheckApp: App) {
		checkedApps += 1
	}

	func updateCheckerDidFinishCheckingForUpdates(_ updateChecker: UpdateCheckCoordinator) {
		isRunning = false
		isIndeterminate = false
		MigrationTelemetry.shared.scanFinished(appCount: totalApps)
	}
}
