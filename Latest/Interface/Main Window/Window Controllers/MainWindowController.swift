//
//  MainWindowController.swift
//  Latest
//
//  Created by Max Langer on 27.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

/**
 This class controls the main window of the app. It includes the list of apps that have an update available as well as the release notes for the specific update.
 */
class MainWindowController: NSWindowController, NSMenuItemValidation, NSMenuDelegate, UpdateCheckProgressReporting {
    /// Encapsulates the main window items with their according tag identifiers
    private enum MainMenuItem: Int {
        case latest = 0, file, edit, view, window, help
    }

    /// The list view holding the apps
    lazy var listViewController: UpdateTableViewController = {
        let splitViewController = self.contentViewController as? NSSplitViewController
        guard let firstItem = splitViewController?.splitViewItems[0], let controller = firstItem.viewController as? UpdateTableViewController else {
            return UpdateTableViewController()
        }

        // Override sidebar collapsing behavior
        firstItem.canCollapse = false

        return controller
    }()

    /// The detail view controller holding the release notes
    lazy var releaseNotesViewController: ReleaseNotesViewController = {
        guard let splitViewController = self.contentViewController as? NSSplitViewController,
              let secondItem = splitViewController.splitViewItems[1].viewController as? ReleaseNotesViewController
        else {
            return ReleaseNotesViewController()
        }

        return secondItem
    }()

    /// The progress indicator showing how many apps have been checked for updates
    lazy var progressIndicator: NSProgressIndicator = {
        let progressIndicator = NSProgressIndicator()
        progressIndicator.controlSize = .small
        progressIndicator.style = .spinning

        return progressIndicator
    }()

    /// The button that triggers an reload/recheck for updates
    @IBOutlet var reloadTouchBarButton: NSButton!

    override func windowDidLoad() {
        super.windowDidLoad()

        window?.titlebarAppearsTransparent = true
        window?.title = Bundle.main.localizedInfoDictionary?[kCFBundleNameKey as String] as! String
        if #available(macOS 11.0, *) {
            window?.toolbarStyle = .unified
        } else {
            window?.titleVisibility = .hidden
        }

        // Set ourselves as the view menu delegate. Deferring this avoids touching/modifying the
        // main menu while AppKit is still wiring the menu graph during launch on macOS 26.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApplication.shared.mainMenu?.item(at: MainMenuItem.view.rawValue)?.submenu?.delegate = self
        }

        UpdateCheckCoordinator.shared.progressDelegate = self

        window?.makeFirstResponder(listViewController)
        window?.delegate = self

        listViewController.checkForUpdates()
        listViewController.releaseNotesViewController = releaseNotesViewController

        if let splitViewController = contentViewController as? NSSplitViewController {
            splitViewController.splitView.autosaveName = "MainSplitView"

            let detailItem = splitViewController.splitViewItems[1]
            detailItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        }
    }

    // MARK: - Action Methods

    /// Reloads the list / checks for updates
    @IBAction func reload(_: Any?) {
        listViewController.checkForUpdates()
    }

    /// Open all apps that have an update available. If apps from the Mac App Store are there as well, open the Mac App Store
    @IBAction func updateAll(_: Any?) {
        // Iterate all updatable apps and perform update
        for app in UpdateCheckCoordinator.shared.appProvider.updatableApps {
            if !app.isUpdating {
                app.performUpdate()
            }
        }
    }

    @IBAction func performFindPanelAction(_: Any?) {
        window?.makeFirstResponder(listViewController.searchField)
    }

    @IBAction func visitWebsite(_: NSMenuItem?) {
        NSWorkspace.shared.open(URL(string: "https://max.codes/latest")!)
    }

    @IBAction func donate(_: NSMenuItem?) {
        NSWorkspace.shared.open(URL(string: "https://max.codes/latest/donate/")!)
    }

    fileprivate func validate(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(updateAll(_:)):
            hasUpdatesAvailable
        case #selector(reload(_:)):
            !isRunningUpdateCheck
        default:
            true
        }
    }

    // MARK: Menu Item

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else {
            return true
        }

        switch action {
        // Only allow the find item
        case #selector(performFindPanelAction(_:)):
            return menuItem.tag == 1
        default:
            return validate(action)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for menuItem in menu.items {
            // Sort By menu constructed dynamically
            if menuItem.identifier == NSUserInterfaceItemIdentifier(rawValue: "sortByMenu") {
                if let sortByMenu = menuItem.submenu {
                    // Avoid assigning to `items` directly; rebuilding the submenu is less likely to
                    // confuse AppKit's menu graph bookkeeping on macOS 26.
                    sortByMenu.removeAllItems()
                    sortByMenuItems.forEach { sortByMenu.addItem($0) }
                }
            }

            guard let action = menuItem.action else { continue }

            switch action {
            case #selector(toggleShowInstalledUpdates(_:)):
                menuItem.state = AppListSettings.shared.showInstalledUpdates ? .on : .off
            case #selector(toggleShowIgnoredUpdates(_:)):
                menuItem.state = AppListSettings.shared.showIgnoredUpdates ? .on : .off
            default:
                ()
            }
        }
    }

    private var sortByMenuItems: [NSMenuItem] {
        AppListSettings.SortOptions.allCases.map { order in
            let item = NSMenuItem(title: order.displayName, action: #selector(changeSortOrder), keyEquivalent: "")
            item.representedObject = order
            item.state = AppListSettings.shared.sortOrder == order ? .on : .off

            return item
        }
    }

    // MARK: - Update Checker Progress Delegate

    func updateCheckerDidStartScanningForApps(_ updateChecker: UpdateCheckCoordinator) {
        isRunningUpdateCheck = true

        // Setup indeterminate progress indicator
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(updateChecker)

        window?.toolbar?.validateVisibleItems()
    }

    /// This implementation activates the progress indicator, sets its max value and disables the reload button
    func updateChecker(_: UpdateCheckCoordinator, didStartCheckingApps numberOfApps: Int) {
        // Setup progress indicator
        progressIndicator.isIndeterminate = false
        progressIndicator.doubleValue = 0
        progressIndicator.maxValue = Double(numberOfApps - 1)
    }

    /// Update the progress indicator
    func updateChecker(_: UpdateCheckCoordinator, didCheckApp _: App) {
        progressIndicator.increment(by: 1)
    }

    func updateCheckerDidFinishCheckingForUpdates(_: UpdateCheckCoordinator) {
        isRunningUpdateCheck = false
        window?.toolbar?.validateVisibleItems()
    }

    // MARK: - Actions

    @IBAction func changeSortOrder(_ sender: NSMenuItem?) {
        AppListSettings.shared.sortOrder = sender?.representedObject as! AppListSettings.SortOptions
    }

    @IBAction func toggleShowInstalledUpdates(_: NSMenuItem?) {
        AppListSettings.shared.showInstalledUpdates.toggle()
    }

    @IBAction func toggleShowIgnoredUpdates(_: NSMenuItem?) {
        AppListSettings.shared.showIgnoredUpdates.toggle()
    }

    // MARK: - Accessors

    /// Whether there are any updatable apps.
    private var hasUpdatesAvailable: Bool {
        !UpdateCheckCoordinator.shared.appProvider.updatableApps.isEmpty
    }

    /// Whether an update check is currently running
    private var isRunningUpdateCheck: Bool = false {
        didSet {
            reloadTouchBarButton.isEnabled = !isRunningUpdateCheck
            progressIndicator.isHidden = !isRunningUpdateCheck
        }
    }

    // MARK: - Private Methods

    private func showReleaseNotes(_ show: Bool, animated: Bool) {
        guard let splitViewController = contentViewController as? NSSplitViewController else {
            return
        }

        let detailItem = splitViewController.splitViewItems[1]

        if animated {
            detailItem.animator().isCollapsed = !show
        } else {
            detailItem.isCollapsed = !show
        }

        if !show {
            // Deselect current app
            listViewController.selectApp(at: nil)
        }
    }
}

extension MainWindowController: NSWindowDelegate {
    @available(macOS, deprecated: 11.0)
    func window(_ window: NSWindow, willPositionSheet _: NSWindow, using rect: NSRect) -> NSRect {
        // Always position sheets at the top of the window, ignoring toolbar insets
        NSRect(x: rect.minX, y: window.frame.height, width: rect.width, height: rect.height)
    }
}

extension MainWindowController: NSToolbarItemValidation {
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard let action = item.action else { return true }
        return validate(action)
    }
}
