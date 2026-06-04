//
//  SettingsWindowController.swift
//  Latest
//
//  Created by Codex on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
	private static let toolbarIdentifier = NSToolbar.Identifier("latest.settings.toolbar")

	private let viewModel: SettingsViewModel
	private let hostingController: NSHostingController<SettingsRootView>

	static func makeController() -> SettingsWindowController {
		SettingsWindowController(viewModel: SettingsViewModel())
	}

	private init(viewModel: SettingsViewModel) {
		self.viewModel = viewModel

		let hostingController = NSHostingController(rootView: SettingsRootView(viewModel: viewModel))
		self.hostingController = hostingController
		let window = NSWindow(
			contentRect: NSRect(origin: .zero, size: viewModel.selectedTab.contentSize),
			styleMask: [.titled, .closable, .miniaturizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = hostingController
		window.title = viewModel.selectedTab.title
		window.isReleasedWhenClosed = false
		window.isRestorable = false
		window.setFrameAutosaveName("SettingsWindow")
		window.center()

		super.init(window: window)
		configureToolbar()
		resizeWindow(to: viewModel.selectedTab.windowFrameSize, animated: false)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func select(_ tab: SettingsViewModel.Tab) {
		viewModel.selectedTab = tab
		hostingController.rootView = SettingsRootView(viewModel: viewModel)
		window?.title = tab.title
		window?.toolbar?.selectedItemIdentifier = tab.toolbarItemIdentifier
		resizeWindow(to: tab.windowFrameSize, animated: false)
		DispatchQueue.main.async { [weak self] in
			self?.resizeWindow(to: tab.windowFrameSize, animated: false)
		}
	}

	private func configureToolbar() {
		let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
		toolbar.displayMode = .iconAndLabel
		toolbar.sizeMode = .regular
		toolbar.allowsUserCustomization = false
		toolbar.autosavesConfiguration = false
		toolbar.delegate = self
		window?.toolbar = toolbar
		window?.toolbarStyle = .preference
		window?.toolbar?.selectedItemIdentifier = viewModel.selectedTab.toolbarItemIdentifier
	}

	private func resizeWindow(to frameSize: NSSize, animated: Bool) {
		guard let window else { return }

		let frame = NSRect(
			origin: NSPoint(
				x: window.frame.origin.x,
				y: window.frame.origin.y + window.frame.height - frameSize.height
			),
			size: frameSize
		)
		window.setFrame(frame, display: true, animate: animated)
	}

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		SettingsViewModel.Tab.allCases.map(\.toolbarItemIdentifier)
	}

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarAllowedItemIdentifiers(toolbar)
	}

	func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarAllowedItemIdentifiers(toolbar)
	}

	func toolbar(
		_ toolbar: NSToolbar,
		itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
		willBeInsertedIntoToolbar flag: Bool
	) -> NSToolbarItem? {
		guard let tab = SettingsViewModel.Tab(itemIdentifier: itemIdentifier) else { return nil }
		let item = NSToolbarItem(itemIdentifier: itemIdentifier)
		item.label = tab.title
		item.paletteLabel = tab.title
		item.image = NSImage(systemSymbolName: tab.systemImageName, accessibilityDescription: tab.title)
		item.target = self
		item.action = #selector(selectToolbarTab(_:))
		return item
	}

	@objc private func selectToolbarTab(_ sender: NSToolbarItem) {
		guard let tab = SettingsViewModel.Tab(itemIdentifier: sender.itemIdentifier) else { return }
		select(tab)
	}
}

private extension SettingsViewModel.Tab {
	var toolbarItemIdentifier: NSToolbarItem.Identifier {
		NSToolbarItem.Identifier("latest.settings.\(title.lowercased())")
	}

	init?(itemIdentifier: NSToolbarItem.Identifier) {
		switch itemIdentifier.rawValue {
		case Self.general.toolbarItemIdentifier.rawValue:
			self = .general
		case Self.locations.toolbarItemIdentifier.rawValue:
			self = .locations
		default:
			return nil
		}
	}
}
