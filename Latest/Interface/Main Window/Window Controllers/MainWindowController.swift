//
//  MainWindowController.swift
//  Latest
//
//  Created by Max Langer on 27.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa
import Combine

private extension NSUserInterfaceItemIdentifier {
	static let sortByMenu = NSUserInterfaceItemIdentifier("sortByMenu")
}

/// Controls the SwiftUI-hosted main window and bridges AppKit menus/toolbars into app commands.
class MainWindowController: NSWindowController, NSMenuItemValidation, NSMenuDelegate {

	private static let mainWindowAutosaveName = "MainWindowSize"
	private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("MainWindow")
	private static let toolbarIdentifier = NSToolbar.Identifier("latest.mainWindowToolbar")

	private enum MainMenuItem: Int {
		case latest = 0, file, edit, view, window, help
	}

	private var swiftUIEnvironment: AppEnvironment?
	private var swiftUICancellables = Set<AnyCancellable>()
	private var didConfigureMainWindow = false

	lazy var progressIndicator: NSProgressIndicator = {
		let progressIndicator = NSProgressIndicator()
		progressIndicator.controlSize = .small
		progressIndicator.style = .spinning
		return progressIndicator
	}()

	static func makeProgrammaticSwiftUIMainWindowController() -> MainWindowController {
		let contentRect = NSRect(
			x: 0,
			y: 0,
			width: VisualMetrics.mainWindowDefaultWidth,
			height: VisualMetrics.mainWindowDefaultHeight
		)
		let window = NSWindow(
			contentRect: contentRect,
			styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		window.identifier = mainWindowIdentifier
		window.allowsToolTipsWhenApplicationIsInactive = false
		window.isReleasedWhenClosed = false
		window.animationBehavior = .default
		window.minSize = NSSize(width: VisualMetrics.mainWindowMinWidth, height: VisualMetrics.mainWindowMinHeight)
		let restoredSavedFrame = window.setFrameAutosaveName(mainWindowAutosaveName)
		if !restoredSavedFrame {
			window.center()
		}

		let controller = MainWindowController(window: window)
		controller.configureSwiftUIMainWindow()
		return controller
	}

	override func windowDidLoad() {
		super.windowDidLoad()
		configureSwiftUIMainWindow()
	}

	private func configureSwiftUIMainWindow() {
		guard !didConfigureMainWindow else { return }
		didConfigureMainWindow = true

		let environment = AppEnvironment.live()
		let normalizedFrame = self.window.map { Self.normalizedMainWindowFrame($0.frame) }
		swiftUIEnvironment = environment

		self.window?.titlebarAppearsTransparent = true
		self.window?.title = Bundle.main.localizedInfoDictionary?[kCFBundleNameKey as String] as? String ?? "Latest"
		self.window?.toolbarStyle = .unified
		self.window?.minSize = NSSize(width: VisualMetrics.mainWindowMinWidth, height: VisualMetrics.mainWindowMinHeight)
		self.window?.delegate = self
		configureToolbarIfNeeded()

		NSApplication.shared.mainMenu?.item(at: MainMenuItem.view.rawValue)?.submenu?.delegate = self

		let splitViewController = SwiftUIMainWindowController.makeSplitViewController(environment: environment)
		self.contentViewController = splitViewController
		if let normalizedFrame {
			self.window?.setFrame(normalizedFrame, display: false)
		}
		bindSwiftUIEnvironment(environment)
		environment.start()

		DispatchQueue.main.async { [weak self, weak splitViewController] in
			if let normalizedFrame {
				self?.window?.setFrame(normalizedFrame, display: true)
			}
			splitViewController?.splitView.setPosition(VisualMetrics.sidebarIdealWidth, ofDividerAt: 0)
			self?.window?.makeFirstResponder(nil)
			self?.window?.makeKeyAndOrderFront(self)
			self?.window?.orderFrontRegardless()
			NSApp.activate(ignoringOtherApps: true)
		}
	}

	private func configureToolbarIfNeeded() {
		guard window?.toolbar == nil else { return }

		let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
		toolbar.autosavesConfiguration = false
		toolbar.allowsUserCustomization = false
		toolbar.displayMode = .iconOnly
		toolbar.sizeMode = .regular
		toolbar.delegate = self
		window?.toolbar = toolbar
	}

	private static func normalizedMainWindowFrame(_ frame: NSRect) -> NSRect {
		let defaultSize = NSSize(
			width: VisualMetrics.mainWindowDefaultWidth,
			height: VisualMetrics.mainWindowDefaultHeight
		)

		let isShortMainWindowFrame = frame.height <= VisualMetrics.mainWindowMinHeight + 1
		guard isShortMainWindowFrame else {
			return frame.integral
		}

		var normalizedFrame = frame
		normalizedFrame.origin.y += frame.height - defaultSize.height
		normalizedFrame.size = defaultSize
		return normalizedFrame.integral
	}

	private func bindSwiftUIEnvironment(_ environment: AppEnvironment) {
		environment.updateCheckingService.objectWillChange
			.sink { [weak self] _ in
				DispatchQueue.main.async {
					self?.syncProgressIndicator()
				}
			}
			.store(in: &swiftUICancellables)

		environment.updatesListViewModel.$statusText
			.sink { [weak self] statusText in
				self?.window?.subtitle = statusText
				self?.window?.toolbar?.validateVisibleItems()
			}
			.store(in: &swiftUICancellables)

		environment.updatesListViewModel.$snapshot
			.sink { [weak self] _ in
				self?.window?.toolbar?.validateVisibleItems()
			}
			.store(in: &swiftUICancellables)
	}

	private func syncProgressIndicator() {
		guard let service = swiftUIEnvironment?.updateCheckingService else { return }

		if service.isRunning {
			progressIndicator.isHidden = false
			progressIndicator.isIndeterminate = service.isIndeterminate

			if service.isIndeterminate {
				progressIndicator.startAnimation(self)
			} else {
				progressIndicator.maxValue = Double(max(service.totalApps - 1, 0))
				progressIndicator.doubleValue = Double(service.checkedApps)
				progressIndicator.startAnimation(self)
			}
		} else {
			progressIndicator.stopAnimation(self)
			progressIndicator.isHidden = true
		}

		window?.toolbar?.validateVisibleItems()
	}

	// MARK: - Action Methods

	@IBAction func reload(_ sender: Any?) {
		swiftUIEnvironment?.commands.reload()
	}

	@IBAction func updateAll(_ sender: Any?) {
		swiftUIEnvironment?.commands.updateAll()
	}

	@IBAction func updateApp(_ sender: NSMenuItem?) {
		swiftUIEnvironment?.commands.updateSelectedApp()
	}

	@IBAction func openApp(_ sender: NSMenuItem?) {
		swiftUIEnvironment?.commands.openSelectedApp()
	}

	@IBAction func showAppInFinder(_ sender: NSMenuItem?) {
		swiftUIEnvironment?.commands.revealSelectedAppInFinder()
	}

	@IBAction func performFindPanelAction(_ sender: Any?) {
		swiftUIEnvironment?.commands.focusSearch()
	}

	@IBAction func visitWebsite(_ sender: NSMenuItem?) {
		swiftUIEnvironment?.commands.visitWebsite()
	}

	@IBAction func donate(_ sender: NSMenuItem?) {
		swiftUIEnvironment?.commands.donate()
	}

	@IBAction func changeSortOrder(_ sender: NSMenuItem?) {
		guard let sortOrder = sender?.representedObject as? AppListSettings.SortOptions else { return }
		swiftUIEnvironment?.commands.changeSortOrder(sortOrder)
	}

	@IBAction func toggleShowInstalledUpdates(_ sender: NSMenuItem?) {
		swiftUIEnvironment?.commands.toggleShowInstalledUpdates()
	}

	@IBAction func toggleShowIgnoredUpdates(_ sender: NSMenuItem?) {
		swiftUIEnvironment?.commands.toggleShowIgnoredUpdates()
	}

	// MARK: - Menu Item

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else {
			return true
		}

		if action == #selector(updateApp(_:)), let app = selectedMenuApp {
			menuItem.title = updateTitle(for: app)
		}

		switch action {
		case #selector(performFindPanelAction(_:)):
			return menuItem.tag == 1 && validate(action)
		default:
			return validate(action)
		}
	}

	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.items.forEach { menuItem in
			if menuItem.identifier == .sortByMenu {
				menuItem.submenu?.items = sortByMenuItems
			}

			guard let action = menuItem.action else { return }

			switch action {
			case #selector(updateApp(_:)):
				if let app = selectedMenuApp {
					menuItem.title = updateTitle(for: app)
				}
			case #selector(toggleShowInstalledUpdates(_:)):
				menuItem.state = AppListSettings.shared.showInstalledUpdates ? .on : .off
			case #selector(toggleShowIgnoredUpdates(_:)):
				menuItem.state = AppListSettings.shared.showIgnoredUpdates ? .on : .off
			default:
				break
			}
		}
	}

	private func validate(_ selector: Selector) -> Bool {
		guard let environment = swiftUIEnvironment else { return false }

		switch selector {
		case #selector(updateApp(_:)):
			return environment.commands.canUpdateSelectedApp
		case #selector(openApp(_:)), #selector(showAppInFinder(_:)):
			return environment.commands.canOpenSelectedApp
		case #selector(updateAll(_:)):
			return environment.updatesListViewModel.hasUpdatesAvailable
		case #selector(reload(_:)):
			return !environment.updateCheckingService.isRunning
		default:
			return true
		}
	}

	private var sortByMenuItems: [NSMenuItem] {
		AppListSettings.SortOptions.allCases.map { order in
			let item = NSMenuItem(title: order.displayName, action: #selector(changeSortOrder), keyEquivalent: "")
			item.target = self
			item.representedObject = order
			item.state = AppListSettings.shared.sortOrder == order ? .on : .off
			return item
		}
	}

	private var selectedMenuApp: App? {
		swiftUIEnvironment?.commands.selectedApp
	}

	private func updateTitle(for app: App) -> String {
		if let externalUpdater = app.externalUpdaterName {
			return String(
				format: NSLocalizedString(
					"ExternalUpdateAction",
					comment: "Action to update a given app outside of Latest. The placeholder is filled with the name of the external updater. (App Store, App Name)"
				),
				externalUpdater
			)
		}

		return NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
	}
}

extension MainWindowController: NSWindowDelegate {
	func windowWillClose(_ notification: Notification) {
		swiftUIEnvironment?.stop()
		swiftUICancellables.removeAll()
	}
}

extension MainWindowController: NSToolbarItemValidation {
	func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
		guard let action = item.action else { return true }
		return validate(action)
	}
}
