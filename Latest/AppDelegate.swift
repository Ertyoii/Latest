//
//  AppDelegate.swift
//  Latest
//
//  Created by Max Langer on 15.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa


@main
class AppDelegate: NSObject, NSApplicationDelegate {
	
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
    
}
