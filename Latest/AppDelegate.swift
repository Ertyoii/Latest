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
	

    
}
