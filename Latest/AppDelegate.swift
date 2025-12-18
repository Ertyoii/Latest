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
    func applicationDidFinishLaunching(_: Notification) {}

    func applicationWillTerminate(_: Notification) {
        // Insert code here to tear down your application
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        // Always terminate the app if the main window is closed
        true
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    func applicationShouldSaveApplicationState(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_: NSApplication) -> Bool {
        false
    }
}
