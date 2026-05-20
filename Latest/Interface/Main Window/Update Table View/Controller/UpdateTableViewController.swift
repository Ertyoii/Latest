//
//  ViewController.swift
//  Latest
//
//  Created by Max Langer on 15.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

private extension NSUserInterfaceItemIdentifier {
	static let updateCell = NSUserInterfaceItemIdentifier("MLMUpdateCellIdentifier")
	static let updateSectionCell = NSUserInterfaceItemIdentifier("MLMUpdateCellSectionIdentifier")
}

/**
 This is the class handling the update process and displaying its results
 */
class UpdateTableViewController: NSViewController, NSMenuItemValidation, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, Observer {
	
	private static let badgeNumberFormatter = NumberFormatter()

	nonisolated let id = UUID()
	
    /// The array holding the apps that have an update available.
	var snapshot: AppListSnapshot = AppListSnapshot(withApps: [], filterQuery: nil) {
		didSet {
			self.updatePlaceholderVisibility()
		}
	}
	
	/// Convenience for accessing apps that should be displayed in the table.
	var apps: [AppListSnapshot.Entry] {
		return self.snapshot.entries
	}
	        
    /// The detail view controller that shows the release notes
    weak var releaseNotesViewController : ReleaseNotesViewController?
    
    /// The empty state label centered in the list view indicating that no updates are available
    @IBOutlet weak var placeholderLabel: NSTextField!
	
	/// The label indicating how many updates are available
    @IBOutlet weak var updatesLabel: NSTextField!
        
    /// The menu displayed on secondary clicks on cells in the list
    @IBOutlet weak var tableViewMenu: NSMenu!
    
	/// Constraint controlling the top constraint of the table view.
	@IBOutlet weak var topTableConstraint: NSLayoutConstraint!
	
	/// The currently selected app within the UI.
	var selectedApp: App?

	/// The index of the currently selected app within the UI.
	var selectedAppIndex: Int? {
		if let app = self.selectedApp {
			return self.snapshot.firstIndex(of: app)
		}
		
		return nil
	}
	
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let cell = tableView.makeView(withIdentifier: .updateCell, owner: self) {
            self.tableView.rowHeight = cell.frame.height
        }
                        
        self.tableViewMenu.delegate = self
        self.tableView.menu = self.tableViewMenu
		
		AppListSettings.shared.add(self, handler: self.updateSnapshot)
        
		UpdateCheckCoordinator.shared.appProvider.addObserver(self) { newValue in
			self.scheduleTableViewUpdate(with: AppListSnapshot(withApps: newValue, filterQuery: self.snapshot.filterQuery), animated: true)
			self.updateTitleAndBatch()
		}
		
		self.updatesLabel.isHidden = true
		
		self.topTableConstraint.constant = 0
		self.tableView.enclosingScrollView?.contentInsets = .init(top: 78, left: 0, bottom: 0, right: 0)
		self.tableView.enclosingScrollView?.scrollerInsets = .init(top: 0, left: 0, bottom: 10, right: 0)
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
		
		// Setup title
		self.updateTitleAndBatch()
		
		// Setup search field
        NSLayoutConstraint(item: self.searchField!, attribute: .top, relatedBy: .equal, toItem: self.view.window?.contentLayoutGuide, attribute: .top, multiplier: 1.0, constant: 1).isActive = true
		self.view.window?.makeFirstResponder(nil)
	}
	
	deinit {
		let observerID = self.id
		Task { @MainActor in
			AppListSettings.shared.removeObserver(withID: observerID)
		}
	}
    
    
    // MARK: - TableView Stuff
    
    /// The table view displaying the list
    @IBOutlet weak var tableView: NSTableView!
    
	func updateSnapshot() {
		self.scheduleTableViewUpdate(with: self.snapshot.updated(), animated: true)
		self.updateTitleAndBatch()
	}
	
	
    // MARK: Table View Delegate
	
	private func contentCell(for app: App) -> NSView? {
        guard let cell = tableView.makeView(withIdentifier: .updateCell, owner: self) as? UpdateCell else {
            return nil
        }
		
		// Only update image if needed, as this might result in flicker
		if cell.app != app {
			IconCache.shared.icon(for: app) { (image) in
				cell.imageView?.image = image
			}
		}

		cell.app = app
		cell.filterQuery = self.snapshot.filterQuery

        return cell
	}
	
	private func headerCell(of section: AppListSnapshot.Section) -> NSView? {
		let view = self.tableView.makeView(withIdentifier: .updateSectionCell, owner: self) as? UpdateGroupCellView
		
		view?.section = section
		
		return view
	}
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		// Ensure the index is valid
		guard row >= 0 && row < self.apps.count else { return nil }
		
		switch self.apps[row] {
		case .app(let app):
			return self.contentCell(for: app)
		case .section(let section):
			return self.headerCell(of: section)
		}
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		// Ensure the index is valid
		guard row >= 0 && row < self.apps.count else { return nil }
		
		if self.snapshot.isSectionHeader(at: row) {
			guard let view = tableView.rowView(atRow: row, makeIfNecessary: false) else {
				return UpdateGroupRowView()
			}
			
			return view
		}
		
		return nil
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		// Ensure the index is valid
		guard row >= 0 && row < self.apps.count else { return -1 }
		return self.snapshot.isSectionHeader(at: row) ? 27 : 65
    }
    
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
		// Ensure the index is valid
		guard row >= 0 && row < self.apps.count else { return false }
        return self.snapshot.isSectionHeader(at: row)
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		// Ensure the index is valid
		guard row >= 0 && row < self.apps.count else { return false }

        return !self.snapshot.isSectionHeader(at: row)
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        self.selectApp(at: self.tableView.selectedRow)
    }
    
    // MARK: Table View Data Source
    
    func numberOfRows(in tableView: NSTableView) -> Int {
		return self.apps.count
    }
	
	
	// MARK: Update Scheduling
	
	/// The next snapshot to be applied to the table view.
	private var pendingSnapshot: AppListSnapshot?
	
	/// Whether an table view update is already scheduled.
	private var isTableViewUpdateScheduled = false
	
	/// Whether a table view update is currently ongoing.
	private var isApplyingTableViewUpdate = false
	
	/// Schedules a table view update with the given snapshot.
	func scheduleTableViewUpdate(with snapshot: AppListSnapshot, animated: Bool) {
		self.pendingSnapshot = snapshot

		if self.isApplyingTableViewUpdate {
			self.isTableViewUpdateScheduled = true
			return
		}
				
		if animated {
			if self.isTableViewUpdateScheduled {
				return
			}

			self.isTableViewUpdateScheduled = true
			self.perform(#selector(applyScheduledTableViewUpdate), with: nil, afterDelay: 0.1)
			return
		}
		
		self.apply(snapshot, animated: false)
	}
	
	@objc private func applyScheduledTableViewUpdate() {
		guard self.isTableViewUpdateScheduled, let snapshot = pendingSnapshot else {
			return
		}
		self.apply(snapshot, animated: true)

		if self.isTableViewUpdateScheduled {
			self.applyScheduledTableViewUpdate()
		}
	}

	private func apply(_ snapshot: AppListSnapshot, animated: Bool) {
		self.isTableViewUpdateScheduled = false
		self.isApplyingTableViewUpdate = true

		let oldSnapshot = self.snapshot
		self.snapshot = snapshot
		self.pendingSnapshot = nil

		if animated {
			self.applyTableViewChanges(from: oldSnapshot, to: snapshot)
		} else {
			self.tableView.reloadData()
		}
		
		self.ensureSelection()
		self.isApplyingTableViewUpdate = false
	}
    
    
    // MARK: - Public Methods
    
    /// Triggers the update checking mechanism
    func checkForUpdates() {
		UpdateCheckCoordinator.shared.run()
		self.view.window?.makeFirstResponder(self)
    }

    /**
    Selects the app at the given index.
     - parameter index: The index of the given app. If nil, the currently selected app is deselected.
     */
    func selectApp(at index: Int?) {
		guard let index = index, index >= 0, let app = self.snapshot.app(at: index) else {
			self.selectedApp = nil
            self.tableView.deselectAll(nil)
			
			// Clear release notes
			if let detailViewController = self.releaseNotesViewController {
				detailViewController.display(releaseNotesFor: nil)
			}
            
            return
        }
        
		if self.selectedApp?.identifier == app.identifier && index == self.tableView.selectedRow {
			return
		}
		
        self.tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        self.tableView.scrollRowToVisible(index)
			
		self.selectedApp = app
		self.releaseNotesViewController?.display(releaseNotesFor: app)
    }
    
    
	/// The search field used for filtering apps
	@IBOutlet weak var searchField: NSSearchField!

	// MARK: - Interface Updating
    
    /// Updates the UI depending on available updates (show empty states or update list)
    private func updatePlaceholderVisibility() {
		// Only show placeholder if there are no apps and also no active search (which might produce an empty list)
		let showPlaceholder = self.apps.isEmpty && self.snapshot.filterQuery == nil
		
        if showPlaceholder && self.placeholderLabel.isHidden {
            self.tableView.isHidden = true
            self.placeholderLabel.isHidden = false
        } else if !showPlaceholder && !self.placeholderLabel.isHidden {
            self.tableView.isHidden = false
            self.placeholderLabel.isHidden = true
        }
    }
    
    /// Updates the title in the toolbar ("No / n updates available") and the badge of the app icon
    private func updateTitleAndBatch() {
		let showExternalUpdates = AppListSettings.shared.includeAppsWithLimitedSupport
		let count = UpdateCheckCoordinator.shared.appProvider.countOfAvailableUpdates(where: { showExternalUpdates || $0.usesBuiltInUpdater })
		let statusText: String
		
		// Update dock badge
		NSApplication.shared.dockTile.badgeLabel = count == 0 ? nil : Self.badgeNumberFormatter.string(from: count as NSNumber)
		
		let format = NSLocalizedString("NumberOfUpdatesAvailable", comment: "number of updates available")
		statusText = String.localizedStringWithFormat(format, count)
        
		self.view.window?.subtitle = statusText
	}
	
	private func ensureSelection() {
		self.selectApp(at: self.selectedAppIndex)
	}
	
	/// Animates changes made to the apps list
	private func applyTableViewChanges(from oldSnapshot: AppListSnapshot, to newSnapshot: AppListSnapshot) {
		guard let change = TableViewSnapshotDiff(from: oldSnapshot.entries, to: newSnapshot.entries).change else { return }

		switch change {
		case .reload(let indexes):
			self.tableView.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet(integer: 0))
		case .append(let indexes):
			self.tableView.insertRows(at: indexes, withAnimation: [.slideDown, .effectFade])
		case .remove(let indexes):
			self.tableView.removeRows(at: indexes, withAnimation: [.slideUp, .effectFade])
		case .reloadAll:
			self.tableView.reloadData()
		}
	}
	
}

private struct TableViewSnapshotDiff {

	enum Change {
		case reload(IndexSet)
		case append(IndexSet)
		case remove(IndexSet)
		case reloadAll
	}

	let change: Change?

	init(from oldEntries: [AppListSnapshot.Entry], to newEntries: [AppListSnapshot.Entry]) {
		if oldEntries.count == newEntries.count, oldEntries.identityMatches(newEntries) {
			self.change = oldEntries.isEmpty ? nil : .reload(IndexSet(oldEntries.indices))
			return
		}

		if oldEntries.exactlyMatchesPrefix(of: newEntries) {
			self.change = .append(IndexSet(oldEntries.count..<newEntries.count))
			return
		}

		if newEntries.exactlyMatchesPrefix(of: oldEntries) {
			self.change = .remove(IndexSet(newEntries.count..<oldEntries.count))
			return
		}

		self.change = .reloadAll
	}

}

private extension Array where Element == AppListSnapshot.Entry {

	func identityMatches(_ other: [Element]) -> Bool {
		guard count == other.count else { return false }
		return zip(self, other).allSatisfy { $0.isSimilar(to: $1) }
	}

	func exactlyMatchesPrefix(of other: [Element]) -> Bool {
		guard count <= other.count else { return false }
		return zip(self, other).allSatisfy(==)
	}

}
