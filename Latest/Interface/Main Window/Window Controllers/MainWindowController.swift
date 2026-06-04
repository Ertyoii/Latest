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

/**
 This class controls the main window of the app. It includes the list of apps that have an update available as well as the release notes for the specific update.
 */
class MainWindowController: NSWindowController, NSMenuItemValidation, NSMenuDelegate, UpdateCheckProgressReporting {

	private static var activeMainWindowController: MainWindowController?
	private static let mainWindowAutosaveName = "MainWindowSize"
	private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("MainWindow")
	private static let toolbarIdentifier = NSToolbar.Identifier("latest.mainWindowToolbar")
    
	/// Encapsulates the main window items with their according tag identifiers
	private enum MainMenuItem: Int {
		case latest = 0, file, edit, view, window, help
	}

	private enum ExternalURL {
		static let updatesPage = URL(string: "macappstore://apps.apple.com/updates")
		static let website = URL(string: "https://max.codes/latest")
		static let donationPage = URL(string: "https://max.codes/latest/donate/")
	}

	private var swiftUIEnvironment: AppEnvironment?
	private var swiftUICancellables = Set<AnyCancellable>()
	private var didConfigureSwiftUIMainWindow = false

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
		controller.configureProgrammaticSwiftUIMainWindow()
		return controller
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
		Self.activeMainWindowController = self

		if LaunchMode.useSwiftUIMainWindow {
			configureSwiftUIMainWindow()
			return
		}
    
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

		self.window?.makeKeyAndOrderFront(self)
    }

	override func showWindow(_ sender: Any?) {
		super.showWindow(sender)
	}

	private func configureProgrammaticSwiftUIMainWindow() {
		Self.activeMainWindowController = self
		configureSwiftUIMainWindow()
	}

	private func configureSwiftUIMainWindow() {
		guard !didConfigureSwiftUIMainWindow else { return }
		didConfigureSwiftUIMainWindow = true

		let environment = AppEnvironment.live()
		let storyboardFrame = self.window.map { Self.normalizedSwiftUIMainWindowFrame($0.frame) }
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
		if let storyboardFrame {
			self.window?.setFrame(storyboardFrame, display: false)
		}
		bindSwiftUIEnvironment(environment)
		environment.start()

		DispatchQueue.main.async { [weak self, weak splitViewController] in
			if let storyboardFrame {
				self?.window?.setFrame(storyboardFrame, display: true)
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
		toolbar.showsBaselineSeparator = false
		toolbar.displayMode = .iconOnly
		toolbar.sizeMode = .regular
		toolbar.delegate = self
		window?.toolbar = toolbar
	}

	private static func normalizedSwiftUIMainWindowFrame(_ frame: NSRect) -> NSRect {
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
					self?.syncSwiftUIProgressIndicator()
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

	private func syncSwiftUIProgressIndicator() {
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
    
    /// Reloads the list / checks for updates
    @IBAction func reload(_ sender: Any?) {
		if let swiftUIEnvironment {
			swiftUIEnvironment.commands.reload()
			return
		}

        self.listViewController.checkForUpdates()
    }
    
    /// Open all apps that have an update available. If apps from the Mac App Store are there as well, open the Mac App Store
	@IBAction func updateAll(_ sender: Any?) {
		if let swiftUIEnvironment {
			swiftUIEnvironment.commands.updateAll()
			return
		}

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

	@IBAction func updateApp(_ sender: NSMenuItem?) {
		if let swiftUIEnvironment {
			swiftUIEnvironment.commands.updateSelectedApp()
			return
		}

		guard let selectedApp = listViewController.selectedApp else { return }
		selectedApp.performUpdate()
	}

	@IBAction func openApp(_ sender: NSMenuItem?) {
		if let swiftUIEnvironment {
			swiftUIEnvironment.commands.openSelectedApp()
			return
		}

		listViewController.selectedApp?.open()
	}

	@IBAction func showAppInFinder(_ sender: NSMenuItem?) {
		if let swiftUIEnvironment {
			swiftUIEnvironment.commands.revealSelectedAppInFinder()
			return
		}

		listViewController.selectedApp?.showInFinder()
	}
    	
	@IBAction func performFindPanelAction(_ sender: Any?) {
		if let swiftUIEnvironment {
			swiftUIEnvironment.commands.focusSearch()
			return
		}

		self.window?.makeFirstResponder(self.listViewController.searchField)
	}
    
	@IBAction func visitWebsite(_ sender: NSMenuItem?) {
		if let swiftUIEnvironment {
			swiftUIEnvironment.commands.visitWebsite()
			return
		}

		guard let url = ExternalURL.website else { return }
		NSWorkspace.shared.open(url)
    }
	
	@IBAction func donate(_ sender: NSMenuItem?) {
		if let swiftUIEnvironment {
			swiftUIEnvironment.commands.donate()
			return
		}

		guard let url = ExternalURL.donationPage else { return }
		NSWorkspace.shared.open(url)
	}
    
	fileprivate func validate(_ selector: Selector) -> Bool {
		if let swiftUIEnvironment {
			switch selector {
			case #selector(updateApp(_:)):
				return swiftUIEnvironment.commands.canUpdateSelectedApp
			case #selector(openApp(_:)), #selector(showAppInFinder(_:)):
				return swiftUIEnvironment.commands.canOpenSelectedApp
			case #selector(updateAll(_:)):
				return swiftUIEnvironment.updatesListViewModel.hasUpdatesAvailable
			case #selector(reload(_:)):
				return !swiftUIEnvironment.updateCheckingService.isRunning
			default:
				return true
			}
		}

		switch selector {
		case #selector(updateApp(_:)):
			guard let selectedApp = listViewController.selectedApp else { return false }
			return selectedApp.updateAvailable && !selectedApp.isUpdating
		case #selector(openApp(_:)), #selector(showAppInFinder(_:)):
			return listViewController.selectedApp != nil
		case #selector(updateAll(_:)):
			return hasUpdatesAvailable
		case #selector(reload(_:)):
			return !isRunningUpdateCheck
		default:
			return true
		}
	}
	
    
    // MARK: Menu Item

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else {
            return true
        }

		if action == #selector(updateApp(_:)), let app = selectedMenuApp {
			menuItem.title = updateTitle(for: app)
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
			case #selector(updateApp(_:)):
				if let app = selectedMenuApp {
					menuItem.title = updateTitle(for: app)
				}
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
			item.target = self
			item.representedObject = order
			item.state = AppListSettings.shared.sortOrder == order ? .on : .off
			
			return item
		}
	}

	private var selectedMenuApp: App? {
		if let swiftUIEnvironment {
			return swiftUIEnvironment.commands.selectedApp
		}

		return listViewController.selectedApp
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
		if let swiftUIEnvironment {
			swiftUIEnvironment.commands.changeSortOrder(sortOrder)
			return
		}

		AppListSettings.shared.sortOrder = sortOrder
	}

	@IBAction func toggleShowInstalledUpdates(_ sender: NSMenuItem?) {
		if let swiftUIEnvironment {
			swiftUIEnvironment.commands.toggleShowInstalledUpdates()
			return
		}

		AppListSettings.shared.showInstalledUpdates.toggle()
	}
	
	@IBAction func toggleShowIgnoredUpdates(_ sender: NSMenuItem?) {
		if let swiftUIEnvironment {
			swiftUIEnvironment.commands.toggleShowIgnoredUpdates()
			return
		}

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
	
	func windowWillClose(_ notification: Notification) {
		if Self.activeMainWindowController === self {
			Self.activeMainWindowController = nil
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
