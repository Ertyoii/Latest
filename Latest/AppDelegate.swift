//
//  AppDelegate.swift
//  Latest
//
//  Created by Max Langer on 15.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa
import Sparkle

@main
class AppDelegate: NSObject, NSApplicationDelegate {
	
	private lazy var sparkleUpdaterController = SPUStandardUpdaterController(
		startingUpdater: true,
		updaterDelegate: nil,
		userDriverDelegate: nil
	)
	
	private lazy var settingsWindowController: NSWindowController? = {
		NSStoryboard(name: "Main", bundle: nil)
			.instantiateController(withIdentifier: "SettingsWindowController") as? NSWindowController
	}()
	
    func applicationDidFinishLaunching(_ aNotification: Notification) {
		// Defer wiring system menu pointers until after AppKit has finished constructing the
		// menu graph on launch (helps avoid spurious menu consistency assertions on macOS 26).
		DispatchQueue.main.async { [weak self] in
			self?.wireSystemMenus()
		}
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
	
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		// Always terminate the app if the main window is closed
		return true
	}
	
	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		true
	}

	func applicationShouldSaveApplicationState(_ sender: NSApplication) -> Bool {
		false
	}

	func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool {
		false
	}
	
	@IBAction func checkForUpdates(_ sender: Any?) {
		sparkleUpdaterController.checkForUpdates(sender)
	}
	
	@IBAction func showPreferences(_ sender: Any?) {
		settingsWindowController?.showWindow(sender)
		settingsWindowController?.window?.makeKeyAndOrderFront(sender)
		NSApp.activate(ignoringOtherApps: true)
	}
	
	private func wireSystemMenus() {
		MainActor.assumeIsolated {
			guard let mainMenu = NSApp.mainMenu else { return }

			if
				let appMenu = mainMenu.items.first?.submenu,
				let servicesMenu = appMenu.item(withTitle: "Services")?.submenu
			{
				NSApp.servicesMenu = servicesMenu
			}

			if let windowMenu = mainMenu.item(withTitle: "Window")?.submenu {
				NSApp.windowsMenu = windowMenu
			}

			if let helpMenu = mainMenu.item(withTitle: "Help")?.submenu {
				NSApp.helpMenu = helpMenu
			}
		}
	}
    
}
