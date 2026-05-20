//
//  UpdateTableViewController+Actions.swift
//  Latest
//
//  Created by Codex on 19.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit

extension UpdateTableViewController {

	// MARK: - Row Actions

	func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
		guard row >= 0 && row < self.apps.count else { return [] }
		guard !self.snapshot.isSectionHeader(at: row) else { return [] }

		if edge == .trailing {
			guard let app = self.snapshot.app(at: row), app.updateAvailable, !app.isUpdating else {
				return []
			}

			let action = NSTableViewRowAction(style: .regular, title: updateTitle(for: app), handler: { _, row in
				self.updateApp(atIndex: row)
				tableView.rowActionsVisible = false
			})
			action.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
			action.backgroundColor = .systemCyan

			return [action]
		}

		if edge == .leading {
			let open = NSTableViewRowAction(style: .regular, title: NSLocalizedString("OpenAction", comment: "Action to open a given app.")) { _, row in
				self.openApp(at: row)
				tableView.rowActionsVisible = false
			}
			open.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)

			let reveal = NSTableViewRowAction(style: .regular, title: NSLocalizedString("RevealAction", comment: "Revea in Finder Row action"), handler: { _, row in
				self.showAppInFinder(at: row)
				tableView.rowActionsVisible = false
			})
			reveal.backgroundColor = .systemGray
			reveal.image = NSImage(systemSymbolName: "finder", accessibilityDescription: nil)

			return [open, reveal]
		}

		return []
	}

	// MARK: - Menu Item Validation

	private func rowIndex(forMenuItem menuItem: NSMenuItem?) -> Int {
		guard let app = menuItem?.representedObject as? App, let index = self.snapshot.firstIndex(of: app) else { return self.tableView.selectedRow }
		return index
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else {
			return true
		}

		let index = self.rowIndex(forMenuItem: menuItem)
		guard index >= 0, let app = self.snapshot.app(at: index) else {
			return false
		}

		switch action {
		case #selector(updateApp(_:)):
			menuItem.title = updateTitle(for: app)
			return app.updateAvailable && !app.isUpdating
		case #selector(openApp(_:)), #selector(showAppInFinder(_:)):
			return true
		case #selector(ignoreApp(_:)):
			menuItem.isHidden = app.isIgnored
			return true
		case #selector(unignoreApp(_:)):
			menuItem.isHidden = !app.isIgnored
			return true
		default:
			return false
		}
	}

	func menuNeedsUpdate(_ menu: NSMenu) {
		let row = self.tableView.clickedRow

		guard row != -1, !self.snapshot.isSectionHeader(at: row) else { return }
		let app = self.snapshot.app(at: row)
		menu.items.forEach { $0.representedObject = app }
	}

	// MARK: - Menu Actions

	@IBAction func updateApp(_ sender: NSMenuItem?) {
		self.updateApp(atIndex: self.rowIndex(forMenuItem: sender))
	}

	@IBAction func ignoreApp(_ sender: NSMenuItem?) {
		self.setIgnored(true, forAppAt: self.rowIndex(forMenuItem: sender))
	}

	@IBAction func unignoreApp(_ sender: NSMenuItem?) {
		self.setIgnored(false, forAppAt: self.rowIndex(forMenuItem: sender))
	}

	@IBAction func openApp(_ sender: NSMenuItem?) {
		self.openApp(at: self.rowIndex(forMenuItem: sender))
	}

	@IBAction func showAppInFinder(_ sender: NSMenuItem?) {
		self.showAppInFinder(at: self.rowIndex(forMenuItem: sender))
	}

	// MARK: - Row Actions

	private func updateTitle(for app: App) -> String {
		if let externalUpdater = app.externalUpdaterName {
			String(format: NSLocalizedString("ExternalUpdateAction", comment: "Action to update a given app outside of Latest. The placeholder is filled with the name of the external updater. (App Store, App Name)"), externalUpdater)
		} else {
			NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
		}
	}

	private func updateApp(atIndex index: Int) {
		guard let app = self.app(at: index) else { return }

		Task { @MainActor in
			app.performUpdate()
		}
	}

	private func setIgnored(_ ignored: Bool, forAppAt index: Int) {
		guard let app = self.app(at: index) else { return }
		UpdateCheckCoordinator.shared.appProvider.setIgnoredState(ignored, for: app)
	}

	private func openApp(at index: Int) {
		self.app(at: index)?.open()
	}

	private func showAppInFinder(at index: Int) {
		self.app(at: index)?.showInFinder()
	}

	private func app(at index: Int) -> App? {
		guard index >= 0 && index < self.apps.count else {
			return nil
		}

		return self.snapshot.app(at: index)
	}

}
