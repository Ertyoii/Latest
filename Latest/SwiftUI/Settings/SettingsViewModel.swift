//
//  SettingsViewModel.swift
//  Latest
//
//  Created by Codex on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
	enum Tab: CaseIterable {
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

		var contentSize: NSSize {
			switch self {
			case .general:
				return NSSize(width: 440, height: 219)
			case .locations:
				return NSSize(width: 440, height: 296)
			}
		}

		var windowFrameSize: NSSize {
			switch self {
			case .general:
				return NSSize(width: 440, height: 309)
			case .locations:
				return NSSize(width: 440, height: 384)
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

	func addDirectory(attachedTo window: NSWindow?) {
		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true

		let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
			guard response == .OK, let panel else { return }
			panel.urls.forEach { self?.directoryStore.add($0) }
		}

		if let window {
			panel.beginSheetModal(for: window, completionHandler: completion)
		} else {
			panel.begin(completionHandler: completion)
		}
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
