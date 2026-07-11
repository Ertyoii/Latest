//
//  SettingsViewModel.swift
//  Latest
//
//  Created by Codex on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
	enum Tab: CaseIterable, Hashable {
		case general
		case locations

		var title: String {
			switch self {
			case .general:
				return "General"
			case .locations:
				return "Locations"
			}
		}

		var systemImageName: String {
			switch self {
			case .general:
				return "gearshape"
			case .locations:
				return "externaldrive"
			}
		}

	}

	@Published var selectedTab: Tab = .general
	@Published private(set) var directoryURLs: [URL] = []
	@Published var selectedDirectory: URL?
	@Published private(set) var showsInstallHelperBanner = false

	private lazy var directoryStore = AppDirectoryStore(updateHandler: { [weak self] in
		self?.reloadDirectories()
	})

	init() {
		reloadDirectories()
		refreshInstallHelperAvailability()
	}

	var includeAppsWithLimitedSupport: Bool {
		get {
			AppListSettings.shared.includeAppsWithLimitedSupport
		}
		set {
			AppListSettings.shared.includeAppsWithLimitedSupport = newValue
			objectWillChange.send()
		}

	}

	var includeUnsupportedApps: Bool {
		get {
			AppListSettings.shared.includeUnsupportedApps
		}
		set {
			AppListSettings.shared.includeUnsupportedApps = newValue
			objectWillChange.send()
		}
	}

	func refreshInstallHelperAvailability() {
		do {
			try InstallHelper.verifyAvailability()
			showsInstallHelperBanner = false
		} catch {
			showsInstallHelperBanner = true
		}
	}

	func registerInstallHelper() {
		AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
		try? InstallHelper.installHelper()
		refreshInstallHelperAvailability()
	}

	func canRemove(_ url: URL?) -> Bool {
		guard let url else { return false }
		return directoryStore.canRemove(url)
	}

	func addDirectories(_ urls: [URL]) {
		urls.forEach(directoryStore.add)
		reloadDirectories()
	}

	func removeSelectedDirectory() {
		guard let selectedDirectory, directoryStore.canRemove(selectedDirectory) else { return }
		directoryStore.remove(selectedDirectory)
		self.selectedDirectory = nil
		reloadDirectories()
	}

	func isReachable(_ url: URL) -> Bool {
		directoryStore.isReachable(url)
	}

	private func reloadDirectories() {
		directoryURLs = directoryStore.URLs
		if let selectedDirectory, !directoryURLs.contains(selectedDirectory) {
			self.selectedDirectory = nil
		}
	}
}
