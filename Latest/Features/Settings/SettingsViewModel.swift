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
	typealias DirectoryStoreFactory = (@escaping AppDirectoryUpdateHandler) -> any AppDirectoryStoring

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

		var contentSize: CGSize {
			switch self {
			case .general:
				// SwiftUI's native preferences toolbar is six points shorter than the
				// former NSToolbar host. Keep that six-point allowance while making
				// room for the native appearance selector.
				CGSize(width: 440, height: 255)
			case .locations:
				CGSize(width: 440, height: 296)
			}
		}

	}

	@Published var selectedTab: Tab = .general
	@Published private(set) var directoryURLs: [URL] = []
	@Published var selectedDirectory: URL?
	@Published private(set) var showsInstallHelperBanner = false

	private let settings: any AppListSettingsProviding
	private let installHelperService: any InstallHelperServicing
	private let directoryStoreFactory: DirectoryStoreFactory
	private lazy var directoryStore = directoryStoreFactory { [weak self] in
		self?.reloadDirectories()
	}

	init(
		settings: any AppListSettingsProviding = AppListSettings.shared,
		installHelperService: any InstallHelperServicing = LiveInstallHelperService.shared,
		directoryStoreFactory: @escaping DirectoryStoreFactory = { AppDirectoryStore(updateHandler: $0) }
	) {
		self.settings = settings
		self.installHelperService = installHelperService
		self.directoryStoreFactory = directoryStoreFactory
		reloadDirectories()
		refreshInstallHelperAvailability()
	}

	var includeAppsWithLimitedSupport: Bool {
		get {
			settings.includeAppsWithLimitedSupport
		}
		set {
			settings.includeAppsWithLimitedSupport = newValue
			objectWillChange.send()
		}

	}

	var includeUnsupportedApps: Bool {
		get {
			settings.includeUnsupportedApps
		}
		set {
			settings.includeUnsupportedApps = newValue
			objectWillChange.send()
		}
	}

	func refreshInstallHelperAvailability() {
		do {
			try installHelperService.verifyAvailability()
			showsInstallHelperBanner = false
		} catch {
			showsInstallHelperBanner = true
		}
	}

	func registerInstallHelper() {
		try? installHelperService.register()
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

	/// Refreshes the locations snapshot. Kept internal so the migration
	/// performance harness measures the same path used after add/remove events.
	func refreshDirectories() {
		reloadDirectories()
	}

	private func reloadDirectories() {
		MigrationTelemetry.shared.measureSettingsRefresh {
			directoryURLs = directoryStore.URLs
			if let selectedDirectory, !directoryURLs.contains(selectedDirectory) {
				self.selectedDirectory = nil
			}
		}
	}
}
