//
//  AppDelegate.swift
//  Latest
//
//  Created by Max Langer on 15.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa
import Sparkle

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
		NSApp.setActivationPolicy(.regular)
		installMainMenu()
		showMainWindowIfNeeded()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
	
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		// Always terminate the app if the main window is closed
		return true
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		showMainWindowIfNeeded()
		return true
	}

	private var mainWindowController: NSWindowController?
	private var settingsWindowController: NSWindowController?
	private lazy var sparkleUpdaterController = SPUStandardUpdaterController(
		startingUpdater: true,
		updaterDelegate: nil,
		userDriverDelegate: nil
	)

	@IBAction func showSettings(_ sender: Any?) {
		if settingsWindowController == nil {
			settingsWindowController = SettingsWindowController.makeController()
		}

		if let settingsWindowController {
			presentWindow(settingsWindowController, sender: sender)
		}
	}

	private func showMainWindowIfNeeded() {
		if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "MainWindow" }) {
			presentWindow(window, sender: self)
			return
		}

		let windowController = MainWindowController.makeProgrammaticSwiftUIMainWindowController()
		mainWindowController = windowController
		presentWindow(windowController, sender: self)
	}

	private func presentWindow(_ windowController: NSWindowController, sender: Any?) {
		windowController.showWindow(sender)
		if let window = windowController.window {
			presentWindow(window, sender: sender)
		} else {
			NSApp.activate(ignoringOtherApps: true)
		}
	}

	private func presentWindow(_ window: NSWindow, sender: Any?) {
		window.makeKeyAndOrderFront(sender)
		window.orderFrontRegardless()
		NSApp.activate(ignoringOtherApps: true)
	}

	private func installMainMenu() {
		let mainMenu = NSMenu(title: "Main Menu")
		mainMenu.addItem(appMenuItem())
		mainMenu.addItem(fileMenuItem())
		mainMenu.addItem(editMenuItem())
		mainMenu.addItem(viewMenuItem())
		mainMenu.addItem(windowMenuItem())
		mainMenu.addItem(helpMenuItem())
		NSApp.mainMenu = mainMenu
	}

	private func appMenuItem() -> NSMenuItem {
		let appName = Bundle.main.localizedInfoDictionary?[kCFBundleNameKey as String] as? String
			?? Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String
			?? ProcessInfo.processInfo.processName
		let menu = NSMenu(title: appName)
		menu.addItem(menuItem(
			title: String(format: NSLocalizedString("About %@", comment: "About application menu item title"), appName),
			action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
			target: NSApp
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("Check for Updates…", comment: "Sparkle application update menu item title"),
			action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
			target: sparkleUpdaterController,
			image: NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90", accessibilityDescription: nil)
		))
		menu.addItem(.separator())
		menu.addItem(menuItem(
			title: NSLocalizedString("Preferences…", comment: "Preferences menu item title"),
			action: #selector(showSettings(_:)),
			target: self,
			keyEquivalent: ",",
			image: NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
		))
		menu.addItem(.separator())

		let servicesMenu = NSMenu(title: NSLocalizedString("Services", comment: "Services menu title"))
		let servicesItem = NSMenuItem(title: NSLocalizedString("Services", comment: "Services menu title"), action: nil, keyEquivalent: "")
		servicesItem.submenu = servicesMenu
		menu.addItem(servicesItem)
		NSApp.servicesMenu = servicesMenu

		menu.addItem(.separator())
		menu.addItem(menuItem(
			title: String(format: NSLocalizedString("Hide %@", comment: "Hide application menu item title"), appName),
			action: #selector(NSApplication.hide(_:)),
			target: NSApp,
			keyEquivalent: "h"
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("Hide Others", comment: "Hide other applications menu item title"),
			action: #selector(NSApplication.hideOtherApplications(_:)),
			target: NSApp,
			keyEquivalent: "h",
			modifierMask: [.command, .option]
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("Show All", comment: "Show all applications menu item title"),
			action: #selector(NSApplication.unhideAllApplications(_:)),
			target: NSApp
		))
		menu.addItem(.separator())
		menu.addItem(menuItem(
			title: String(format: NSLocalizedString("Quit %@", comment: "Quit application menu item title"), appName),
			action: #selector(NSApplication.terminate(_:)),
			target: NSApp,
			keyEquivalent: "q"
		))

		let item = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
		item.submenu = menu
		return item
	}

	private func fileMenuItem() -> NSMenuItem {
		let menu = NSMenu(title: NSLocalizedString("File", comment: "File menu title"))
		menu.addItem(menuItem(
			title: NSLocalizedString("Update", comment: "Update selected app menu item title"),
			action: #selector(MainWindowController.updateApp(_:)),
			keyEquivalent: "u",
			image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("Update All", comment: "Update all apps menu item title"),
			action: #selector(MainWindowController.updateAll(_:)),
			keyEquivalent: "U",
			image: NSImage(named: "custom.arrow.down.square.stack")
		))
		menu.addItem(.separator())
		menu.addItem(menuItem(
			title: NSLocalizedString("Open", comment: "Open selected app menu item title"),
			action: #selector(MainWindowController.openApp(_:)),
			keyEquivalent: "O",
			image: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("Show in Finder", comment: "Show selected app in Finder menu item title"),
			action: #selector(MainWindowController.showAppInFinder(_:)),
			keyEquivalent: "R",
			image: NSImage(systemSymbolName: "finder", accessibilityDescription: nil)
		))
		menu.addItem(.separator())
		menu.addItem(menuItem(title: NSLocalizedString("Close", comment: "Close menu item title"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
		return parentMenuItem(title: NSLocalizedString("File", comment: "File menu title"), submenu: menu)
	}

	private func editMenuItem() -> NSMenuItem {
		let menu = NSMenu(title: NSLocalizedString("Edit", comment: "Edit menu title"))
		menu.addItem(menuItem(title: NSLocalizedString("Undo", comment: "Undo menu item title"), action: Selector(("undo:")), keyEquivalent: "z"))
		menu.addItem(menuItem(title: NSLocalizedString("Redo", comment: "Redo menu item title"), action: Selector(("redo:")), keyEquivalent: "Z"))
		menu.addItem(.separator())
		menu.addItem(menuItem(title: NSLocalizedString("Cut", comment: "Cut menu item title"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
		menu.addItem(menuItem(title: NSLocalizedString("Copy", comment: "Copy menu item title"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
		menu.addItem(menuItem(title: NSLocalizedString("Paste", comment: "Paste menu item title"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
		menu.addItem(menuItem(title: NSLocalizedString("Paste and Match Style", comment: "Paste and match style menu item title"), action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "V"))
		menu.addItem(menuItem(title: NSLocalizedString("Delete", comment: "Delete menu item title"), action: #selector(NSText.delete(_:))))
		menu.addItem(menuItem(title: NSLocalizedString("Select All", comment: "Select all menu item title"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
		menu.addItem(.separator())
		menu.addItem(findMenuItem())
		return parentMenuItem(title: NSLocalizedString("Edit", comment: "Edit menu title"), submenu: menu)
	}

	private func findMenuItem() -> NSMenuItem {
		let menu = NSMenu(title: NSLocalizedString("Find", comment: "Find menu title"))
		let findItem = menuItem(
			title: NSLocalizedString("Find…", comment: "Find menu item title"),
			action: #selector(MainWindowController.performFindPanelAction(_:)),
			keyEquivalent: "f"
		)
		findItem.tag = 1
		menu.addItem(findItem)
		menu.addItem(menuItem(
			title: NSLocalizedString("Find Next", comment: "Find next menu item title"),
			action: #selector(MainWindowController.performFindPanelAction(_:)),
			keyEquivalent: "g"
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("Find Previous", comment: "Find previous menu item title"),
			action: #selector(MainWindowController.performFindPanelAction(_:)),
			keyEquivalent: "G"
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("Use Selection for Find", comment: "Use selection for find menu item title"),
			action: #selector(MainWindowController.performFindPanelAction(_:)),
			keyEquivalent: "e"
		))
		return parentMenuItem(title: NSLocalizedString("Find", comment: "Find menu title"), submenu: menu)
	}

	private func viewMenuItem() -> NSMenuItem {
		let menu = NSMenu(title: NSLocalizedString("View", comment: "View menu title"))
		let sortItem = parentMenuItem(title: NSLocalizedString("Sort By", comment: "Sort by menu title"), submenu: NSMenu(title: NSLocalizedString("Sort By", comment: "Sort by menu title")))
		sortItem.identifier = NSUserInterfaceItemIdentifier("sortByMenu")
		sortItem.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)
		menu.addItem(sortItem)
		menu.addItem(.separator())
		menu.addItem(menuItem(
			title: NSLocalizedString("Show Installed Apps", comment: "Show installed apps menu item title"),
			action: #selector(MainWindowController.toggleShowInstalledUpdates(_:)),
			keyEquivalent: "i",
			image: NSImage(systemSymbolName: "checkmark.app", accessibilityDescription: nil)
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("Show Ignored Apps", comment: "Show ignored apps menu item title"),
			action: #selector(MainWindowController.toggleShowIgnoredUpdates(_:)),
			keyEquivalent: "I",
			image: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
		))
		menu.addItem(.separator())
		menu.addItem(menuItem(
			title: NSLocalizedString("Check for Updates…", comment: "Check app update availability menu item title"),
			action: #selector(MainWindowController.reload(_:)),
			keyEquivalent: "r",
			image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
		))
		menu.addItem(.separator())
		menu.addItem(menuItem(
			title: NSLocalizedString("Enter Full Screen", comment: "Enter full screen menu item title"),
			action: #selector(NSWindow.toggleFullScreen(_:)),
			keyEquivalent: "f",
			modifierMask: [.command, .control]
		))
		return parentMenuItem(title: NSLocalizedString("View", comment: "View menu title"), submenu: menu)
	}

	private func windowMenuItem() -> NSMenuItem {
		let menu = NSMenu(title: NSLocalizedString("Window", comment: "Window menu title"))
		menu.addItem(menuItem(title: NSLocalizedString("Minimize", comment: "Minimize menu item title"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
		menu.addItem(menuItem(title: NSLocalizedString("Zoom", comment: "Zoom menu item title"), action: #selector(NSWindow.performZoom(_:))))
		menu.addItem(.separator())
		menu.addItem(menuItem(title: NSLocalizedString("Bring All to Front", comment: "Bring all to front menu item title"), action: #selector(NSApplication.arrangeInFront(_:)), target: NSApp))
		NSApp.windowsMenu = menu
		return parentMenuItem(title: NSLocalizedString("Window", comment: "Window menu title"), submenu: menu)
	}

	private func helpMenuItem() -> NSMenuItem {
		let menu = NSMenu(title: NSLocalizedString("Help", comment: "Help menu title"))
		menu.addItem(menuItem(title: NSLocalizedString("Latest Help", comment: "Latest help menu item title"), action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?"))
		menu.addItem(.separator())
		menu.addItem(menuItem(
			title: NSLocalizedString("Visit Latest-Website", comment: "Visit website menu item title"),
			action: #selector(MainWindowController.visitWebsite(_:)),
			image: NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("Donate", comment: "Donate menu item title"),
			action: #selector(MainWindowController.donate(_:)),
			image: NSImage(systemSymbolName: "hands.clap", accessibilityDescription: nil)
		))
		NSApp.helpMenu = menu
		return parentMenuItem(title: NSLocalizedString("Help", comment: "Help menu title"), submenu: menu)
	}

	private func parentMenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
		item.submenu = submenu
		return item
	}

	private func menuItem(
		title: String,
		action: Selector?,
		target: AnyObject? = nil,
		keyEquivalent: String = "",
		modifierMask: NSEvent.ModifierFlags = .command,
		image: NSImage? = nil
	) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
		item.target = target
		item.keyEquivalentModifierMask = modifierMask
		item.image = image
		return item
	}
    
}
