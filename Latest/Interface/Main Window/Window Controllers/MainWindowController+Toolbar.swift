//
//  MainWindowController+Toolbar.swift
//  Latest
//
//  Created by Max Langer on 11.10.25.
//  Copyright © 2025 Max Langer. All rights reserved.
//

import AppKit

extension MainWindowController: NSToolbarDelegate {
	
	// MARK: - Toolbar Delegate
	
	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		var items: [NSToolbarItem.Identifier] = [
			.flexibleSpace,
			.progressIndicatorItem,
			.checkForUpdatesActionItem,
			.updateAllActionItem
		]
		
		// Items sit in sidebar
		items.append(.sidebarTrackingSeparator)
		
		return items
	}
	
	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarDefaultItemIdentifiers(toolbar)
	}
	
	func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
		let item = NSToolbarItem(itemIdentifier: itemIdentifier)
		
		switch itemIdentifier {
		case .progressIndicatorItem:
			item.view = progressIndicator
		case .checkForUpdatesActionItem:
			item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
			item.target = self
			item.toolTip = NSLocalizedString("CheckForUpdatesToolbarItemToolTip", comment: "Tool tip of a toolbar button that checks for updates")
			item.action = #selector(reload(_:))
		case .updateAllActionItem:
			item.image = Self.updateAllToolbarImage()
			item.target = self
			item.toolTip = NSLocalizedString("UpdateAllToolbarItemToolTip", comment: "Tool tip of a toolbar button that performs updates for all apps with update available")
			item.action = #selector(updateAll(_:))
		default:
			return nil
		}
		
		return item
	}
	
}

private extension MainWindowController {
	static func updateAllToolbarImage() -> NSImage? {
		guard let image = NSImage(named: "custom.arrow.down.square.stack") else {
			return nil
		}

		let sizeConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular, scale: .medium)
		let contrastConfiguration = NSImage.SymbolConfiguration(paletteColors: [.labelColor, .labelColor, .labelColor])
		return image.withSymbolConfiguration(sizeConfiguration.applying(contrastConfiguration)) ?? image
	}
}

private extension NSToolbarItem.Identifier {
	/// The item showing the progress indicator.
	static let progressIndicatorItem = NSToolbarItem.Identifier("latest.reloadProgressIndicatorItem")

	/// Action for checking for updates
	static let checkForUpdatesActionItem = NSToolbarItem.Identifier("latest.checkForUpdatesActionItem")
	
	/// Action for updating all apps.
	static let updateAllActionItem = NSToolbarItem.Identifier("latest.updateAllActionItem")
}
