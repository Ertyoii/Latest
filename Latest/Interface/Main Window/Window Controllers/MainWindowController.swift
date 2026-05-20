//
//  MainWindowController.swift
//  Latest
//
//  Created by Max Langer on 27.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

private extension NSUserInterfaceItemIdentifier {
	static let sortByMenu = NSUserInterfaceItemIdentifier("sortByMenu")
}

/**
 This class controls the main window of the app. It includes the list of apps that have an update available as well as the release notes for the specific update.
 */
class MainWindowController: NSWindowController, NSMenuItemValidation, NSMenuDelegate, UpdateCheckProgressReporting {
    
	/// Encapsulates the main window items with their according tag identifiers
	private enum MainMenuItem: Int {
		case latest = 0, file, edit, view, window, help
	}

	private enum ExternalURL {
		static let updatesPage = URL(string: "macappstore://apps.apple.com/updates")
		static let website = URL(string: "https://max.codes/latest")
		static let donationPage = URL(string: "https://max.codes/latest/donate/")
	}
    
    /// The list view holding the apps
    lazy var listViewController : UpdateTableViewController = {
		let splitViewController = self.contentViewController as? NSSplitViewController
        guard let firstItem = splitViewController?.splitViewItems[0], let controller = firstItem.viewController as? UpdateTableViewController else {
                return UpdateTableViewController()
        }
		
		// Override sidebar collapsing behavior
		firstItem.canCollapse = false
        
        return controller
    }()
    
    /// The detail view controller holding the release notes
    lazy var releaseNotesViewController : ReleaseNotesViewController = {
        guard let splitViewController = self.contentViewController as? NSSplitViewController,
            let secondItem = splitViewController.splitViewItems[1].viewController as? ReleaseNotesViewController else {
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
    
    override func windowDidLoad() {
        super.windowDidLoad()
    
		self.window?.titlebarAppearsTransparent = true
		self.window?.title = Bundle.main.localizedInfoDictionary?[kCFBundleNameKey as String] as? String ?? "Latest"
		self.window?.toolbarStyle = .unified
		
		// Set ourselves as the view menu delegate
		NSApplication.shared.mainMenu?.item(at: MainMenuItem.view.rawValue)?.submenu?.delegate = self
		
		UpdateCheckCoordinator.shared.progressDelegate = self
        
        self.window?.makeFirstResponder(self.listViewController)
        self.window?.delegate = self
        
        self.listViewController.checkForUpdates()
        self.listViewController.releaseNotesViewController = self.releaseNotesViewController

        if let splitViewController = self.contentViewController as? NSSplitViewController {
			splitViewController.splitView.autosaveName = "MainSplitView"
			
            let detailItem = splitViewController.splitViewItems[1]
            detailItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        }
    }

    
    // MARK: - Action Methods
    
    /// Reloads the list / checks for updates
    @IBAction func reload(_ sender: Any?) {
        self.listViewController.checkForUpdates()
    }
    
    /// Open all apps that have an update available. If apps from the Mac App Store are there as well, open the Mac App Store
    @IBAction func updateAll(_ sender: Any?) {
		let apps = UpdateCheckCoordinator.shared.appProvider.updatableApps
		
		// Check if there are app store updates
		if apps.contains(where: { $0.bundle.source == .appStore }) {
			do {
				try AppStoreUpdater.prepareForUpdates()
			} catch {
				guard let updatesPage = ExternalURL.updatesPage else { return }
				if !AppStoreUpdateSettings.alwaysPerformManualUpdates.active {
					UpdateInstallHelperAlert.present(with: error, fallbackURL: updatesPage)
				} else {
					NSWorkspace.shared.open(updatesPage)
				}
			}
		}
		
		// Iterate all updatable apps and perform update
		apps.forEach({ app in
			if !app.isUpdating {
				app.performUpdate(isBulkUpdate: true)
			}
		})
    }
    	
	@IBAction func performFindPanelAction(_ sender: Any?) {
		self.window?.makeFirstResponder(self.listViewController.searchField)
	}
    
	@IBAction func visitWebsite(_ sender: NSMenuItem?) {
		guard let url = ExternalURL.website else { return }
		NSWorkspace.shared.open(url)
    }
	
	@IBAction func donate(_ sender: NSMenuItem?) {
		guard let url = ExternalURL.donationPage else { return }
		NSWorkspace.shared.open(url)
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
		menu.items.forEach { (menuItem) in
			// Sort By menu constructed dynamically
			if menuItem.identifier == .sortByMenu {
				menuItem.submenu?.items = sortByMenuItems
			}

            guard let action = menuItem.action else { return }
            
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
		self.isRunningUpdateCheck = true
		
		// Setup indeterminate progress indicator
		self.progressIndicator.isIndeterminate = true
		self.progressIndicator.startAnimation(updateChecker)

		self.window?.toolbar?.validateVisibleItems()
	}
    
    /// This implementation activates the progress indicator, sets its max value and disables the reload button
	func updateChecker(_ updateChecker: UpdateCheckCoordinator, didStartCheckingApps numberOfApps: Int) {
		// Setup progress indicator
		self.progressIndicator.isIndeterminate = false
        self.progressIndicator.doubleValue = 0
        self.progressIndicator.maxValue = Double(numberOfApps - 1)
	}
    
    /// Update the progress indicator
	func updateChecker(_ updateChecker: UpdateCheckCoordinator, didCheckApp: App) {
		self.progressIndicator.increment(by: 1)
    }
	
	func updateCheckerDidFinishCheckingForUpdates(_ updateChecker: UpdateCheckCoordinator) {
		self.isRunningUpdateCheck = false
		self.window?.toolbar?.validateVisibleItems()
	}
    
	
	// MARK: - Actions
	
	@IBAction func changeSortOrder(_ sender: NSMenuItem?) {
		guard let sortOrder = sender?.representedObject as? AppListSettings.SortOptions else { return }
		AppListSettings.shared.sortOrder = sortOrder
	}

	@IBAction func toggleShowInstalledUpdates(_ sender: NSMenuItem?) {
		AppListSettings.shared.showInstalledUpdates.toggle()
	}
	
	@IBAction func toggleShowIgnoredUpdates(_ sender: NSMenuItem?) {
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
			self.progressIndicator.isHidden = !isRunningUpdateCheck
		}
	}

    
    // MARK: - Private Methods
    	
    private func showReleaseNotes(_ show: Bool, animated: Bool) {
        guard let splitViewController = self.contentViewController as? NSSplitViewController else {
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
            self.listViewController.selectApp(at: nil)
        }
    }
	
}

extension MainWindowController: NSWindowDelegate {}

extension MainWindowController: NSToolbarItemValidation {
	func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
		guard let action = item.action else { return true }
		return validate(action)
	}
}
