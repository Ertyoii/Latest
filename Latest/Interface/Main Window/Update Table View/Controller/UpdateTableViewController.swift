//
//  UpdateTableViewController.swift
//  Latest
//
//  Created by Max Langer on 15.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

/**
 This is the class handling the update process and displaying its results
 */
class UpdateTableViewController: NSViewController, NSMenuItemValidation, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, Observer {
    nonisolated let id = UUID()

    /// The array holding the apps that have an update available.
    var snapshot: AppListSnapshot = .init(withApps: [], filterQuery: nil) {
        didSet {
            updatePlaceholderVisibility()
        }
    }

    /// Convenience for accessing apps that should be displayed in the table.
    var apps: [AppListSnapshot.Entry] {
        snapshot.entries
    }

    /// The detail view controller that shows the release notes
    weak var releaseNotesViewController: ReleaseNotesViewController?

    /// The empty state label centered in the list view indicating that no updates are available
    @IBOutlet var placeholderLabel: NSTextField!

    /// The label indicating how many updates are available
    @IBOutlet var updatesLabel: NSTextField!

    /// The menu displayed on secondary clicks on cells in the list
    @IBOutlet var tableViewMenu: NSMenu!

    /// Constraint controlling the top constraint of the table view.
    @IBOutlet var topTableConstraint: NSLayoutConstraint!

    /// The currently selected app within the UI.
    var selectedApp: App? {
        willSet {
            if let app = newValue, !self.snapshot.contains(app) {
                fatalError("Attempted to select app that is not available.")
            }
        }
    }

    /// The index of the currently selected app within the UI.
    var selectedAppIndex: Int? {
        if let app = selectedApp {
            return snapshot.index(of: app)
        }

        return nil
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MLMUpdateCellIdentifier"), owner: self) {
            tableView.rowHeight = cell.frame.height
        }

        tableViewMenu.delegate = self
        tableView.menu = tableViewMenu

        // In newer macOS versions, scroll views can apply automatic content insets which can
        // create a large blank area above the first row in the sidebar list.
        if let scrollView = tableView.enclosingScrollView {
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }

        AppListSettings.shared.add(self, handler: updateSnapshot)

        UpdateCheckCoordinator.shared.appProvider.addObserver(self) { newValue in
            self.scheduleTableViewUpdate(with: AppListSnapshot(withApps: newValue, filterQuery: self.snapshot.filterQuery), animated: true)
            self.updateTitleAndBatch()
        }

        if #available(macOS 11, *) {
            updatesLabel.isHidden = true
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        // Setup title
        updateTitleAndBatch()

        // Setup search field
        NSLayoutConstraint(item: searchField!, attribute: .top, relatedBy: .equal, toItem: view.window?.contentLayoutGuide, attribute: .top, multiplier: 1.0, constant: 1).isActive = true
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        AppListSettings.shared.remove(self)
        UpdateCheckCoordinator.shared.appProvider.removeObserver(self)
    }

    // MARK: - TableView Stuff

    /// The table view displaying the list
    @IBOutlet var tableView: NSTableView!

    func updateSnapshot() {
        scheduleTableViewUpdate(with: snapshot.updated(), animated: true)
        updateTitleAndBatch()
    }

    // MARK: Table View Delegate

    private func contentCell(for app: App) -> NSView? {
        guard let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MLMUpdateCellIdentifier"), owner: self) as? UpdateCell else {
            return nil
        }

        // Only update image if needed, as this might result in flicker
        if cell.app != app {
            IconCache.shared.icon(for: app) { image in
                cell.imageView?.image = image
            }
        }

        cell.app = app
        cell.filterQuery = snapshot.filterQuery

        return cell
    }

    private func headerCell(of section: AppListSnapshot.Section) -> NSView? {
        let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MLMUpdateCellSectionIdentifier"), owner: self) as? UpdateGroupCellView

        view?.section = section

        return view
    }

    func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        // Ensure the index is valid
        guard row >= 0, row < apps.count else { return nil }

        switch apps[row] {
        case let .app(app):
            return contentCell(for: app)
        case let .section(section):
            return headerCell(of: section)
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        // Ensure the index is valid
        guard row >= 0, row < apps.count else { return nil }

        if snapshot.isSectionHeader(at: row) {
            guard let view = tableView.rowView(atRow: row, makeIfNecessary: false) else {
                return UpdateGroupRowView()
            }

            return view
        }

        return nil
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        // Ensure the index is valid
        guard row >= 0, row < apps.count else { return -1 }
        return snapshot.isSectionHeader(at: row) ? 27 : 65
    }

    func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
        // Ensure the index is valid
        guard row >= 0, row < apps.count else { return false }
        return false
    }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        // Ensure the index is valid
        guard row >= 0, row < apps.count else { return [] }

        // Prevent section headers from displaying row actions
        if snapshot.isSectionHeader(at: row) { return [] }

        if edge == .trailing {
            guard let app = snapshot.app(at: row) else { return [] }

            // Don't provide an update action if the app has no update available
            if !app.updateAvailable || app.isUpdating {
                return []
            }

            let action = NSTableViewRowAction(style: .regular, title: updateTitle(for: app), handler: { _, row in
                self.updateApp(atIndex: row)
                tableView.rowActionsVisible = false
            })

            if #available(macOS 11.0, *) {
                action.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
            }

            action.backgroundColor = .systemCyan

            return [action]
        } else if edge == .leading {
            let open = NSTableViewRowAction(style: .regular, title: NSLocalizedString("OpenAction", comment: "Action to open a given app.")) { _, row in
                self.openApp(at: row)
                tableView.rowActionsVisible = false
            }

            let reveal = NSTableViewRowAction(style: .regular, title: NSLocalizedString("RevealAction", comment: "Revea in Finder Row action"), handler: { _, row in
                self.showAppInFinder(at: row)
                tableView.rowActionsVisible = false
            })
            reveal.backgroundColor = .systemGray

            if #available(macOS 11.0, *) {
                open.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
                reveal.image = NSImage(systemSymbolName: "finder", accessibilityDescription: nil)
            }

            return [open, reveal]
        }

        return []
    }

    func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
        // Ensure the index is valid
        guard row >= 0, row < apps.count else { return false }

        return !snapshot.isSectionHeader(at: row)
    }

    func tableViewSelectionDidChange(_: Notification) {
        selectApp(at: tableView.selectedRow)
    }

    // MARK: Table View Data Source

    func numberOfRows(in _: NSTableView) -> Int {
        apps.count
    }

    // MARK: Update Scheduling

    /// The next snapshot to be applied to the table view.
    private var newSnapshot: AppListSnapshot?

    /// Whether an table view update is already scheduled.
    private var tableViewUpdateScheduled = false

    /// Whether a table view update is currently ongoing.
    private var tableViewUpdateInProgress = false

    /// Schedules a table view update with the given snapshot.
    func scheduleTableViewUpdate(with snapshot: AppListSnapshot, animated: Bool) {
        newSnapshot = snapshot

        if tableViewUpdateInProgress {
            tableViewUpdateScheduled = true
            return
        }

        if animated {
            if tableViewUpdateScheduled {
                return
            }

            tableViewUpdateScheduled = true
            perform(#selector(updateTableViewAnimated), with: nil, afterDelay: 0.1)
            return
        }

        tableViewUpdateScheduled = false
        newSnapshot = nil
        self.snapshot = snapshot
        tableView.reloadData()

        // Update selected app
        ensureSelection()
    }

    @objc func updateTableViewAnimated() {
        guard tableViewUpdateScheduled, let snapshot = newSnapshot else {
            return
        }
        tableViewUpdateScheduled = false
        tableViewUpdateInProgress = true

        let oldSnapshot = self.snapshot
        self.snapshot = snapshot
        newSnapshot = nil
        updateTableView(with: oldSnapshot, with: self.snapshot)

        // Update selected app
        ensureSelection()

        tableViewUpdateInProgress = false
        updateTableViewAnimated()
    }

    // MARK: - Public Methods

    /// Triggers the update checking mechanism
    func checkForUpdates() {
        UpdateCheckCoordinator.shared.run()
        view.window?.makeFirstResponder(self)
    }

    /**
     Selects the app at the given index.
      - parameter index: The index of the given app. If nil, the currently selected app is deselected.
      */
    func selectApp(at index: Int?) {
        guard let index, index >= 0, let app = snapshot.app(at: index) else {
            selectedApp = nil
            tableView.deselectAll(nil)
            scrubber?.animator().selectedIndex = -1

            // Clear release notes
            if let detailViewController = releaseNotesViewController {
                detailViewController.display(releaseNotesFor: nil)
            }

            return
        }

        if selectedApp?.identifier == app.identifier, index == tableView.selectedRow {
            return
        }

        scrubber?.animator().scrollItem(at: index, to: .center)
        scrubber?.animator().selectedIndex = index

        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)

        selectedApp = app
        releaseNotesViewController?.display(releaseNotesFor: app)
    }

    // MARK: - Menu Item Stuff

    private func rowIndex(forMenuItem menuItem: NSMenuItem?) -> Int {
        guard let app = menuItem?.representedObject as? App, let index = snapshot.index(of: app) else { return tableView.selectedRow }
        return index
    }

    /// Open a single app
    @IBAction func updateApp(_ sender: NSMenuItem?) {
        updateApp(atIndex: rowIndex(forMenuItem: sender))
    }

    @IBAction func ignoreApp(_ sender: NSMenuItem?) {
        setIgnored(true, forAppAt: rowIndex(forMenuItem: sender))
    }

    @IBAction func unignoreApp(_ sender: NSMenuItem?) {
        setIgnored(false, forAppAt: rowIndex(forMenuItem: sender))
    }

    /// Opens the selected app
    @IBAction func openApp(_ sender: NSMenuItem?) {
        openApp(at: rowIndex(forMenuItem: sender))
    }

    /// Show the bundle of an app in Finder
    @IBAction func showAppInFinder(_ sender: NSMenuItem?) {
        showAppInFinder(at: rowIndex(forMenuItem: sender))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else {
            return true
        }

        let index = rowIndex(forMenuItem: menuItem)
        guard index >= 0, let app = snapshot.app(at: index) else {
            return false
        }

        switch action {
        case #selector(updateApp(_:)):
            menuItem.title = updateTitle(for: app)
            return app.updateAvailable && !app.isUpdating
        case #selector(openApp(_:)), #selector(showAppInFinder(_:)):
            return true
        case #selector(ignoreApp(_:)):
            menuItem.isHidden = app.isIgnored
            return true
        case #selector(unignoreApp(_:)):
            menuItem.isHidden = !app.isIgnored
            return true
        default:
            ()
        }

        return false
    }

    // MARK: Delegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        let row = tableView.clickedRow

        guard row != -1, !snapshot.isSectionHeader(at: row) else { return }
        menu.items.forEach { $0.representedObject = self.snapshot.app(at: row) }
    }

    // MARK: - Search

    /// The search field used for filtering apps
    @IBOutlet var searchField: NSSearchField!

    // MARK: - Actions

    /// Updates the app at the given index.
    private func updateApp(atIndex index: Int) {
        guard let app = app(at: index) else { return }

        // Delay update to improve animations
        DispatchQueue.main.async {
            app.performUpdate()
        }
    }

    /// Sets the ignored state for the app at the given index
    private func setIgnored(_ ignored: Bool, forAppAt index: Int) {
        guard let app = app(at: index) else { return }
        UpdateCheckCoordinator.shared.appProvider.setIgnoredState(ignored, for: app)
    }

    /// Opens the app at a given index.
    private func openApp(at index: Int) {
        app(at: index)?.open()
    }

    /// Reveals the app at a given index in Finder
    private func showAppInFinder(at index: Int) {
        app(at: index)?.showInFinder()
    }

    /// Returns the app at the given index, if available.
    private func app(at index: Int) -> App? {
        guard index >= 0, index < apps.count else {
            return nil
        }

        return snapshot.app(at: index)
    }

    // MARK: - Interface Updating

    /// Updates the UI depending on available updates (show empty states or update list)
    private func updatePlaceholderVisibility() {
        // Only show placeholder if there are no apps and also no active search (which might produce an empty list)
        let showPlaceholder = apps.isEmpty && snapshot.filterQuery == nil

        if showPlaceholder, placeholderLabel.isHidden {
            tableView.isHidden = true
            placeholderLabel.isHidden = false
        } else if !showPlaceholder, !placeholderLabel.isHidden {
            tableView.isHidden = false
            placeholderLabel.isHidden = true
        }
    }

    /// Updates the title in the toolbar ("No / n updates available") and the badge of the app icon
    private func updateTitleAndBatch() {
        let showExternalUpdates = AppListSettings.shared.includeAppsWithLimitedSupport
        let count = UpdateCheckCoordinator.shared.appProvider.countOfAvailableUpdates(where: { showExternalUpdates || $0.usesBuiltInUpdater })
        let statusText: String

        // Update dock badge
        NSApplication.shared.dockTile.badgeLabel = count == 0 ? nil : NumberFormatter().string(from: count as NSNumber)

        let format = NSLocalizedString("NumberOfUpdatesAvailable", comment: "number of updates available")
        statusText = String.localizedStringWithFormat(format, count)

        scrubber?.reloadData()

        view.window?.subtitle = statusText
    }

    private func ensureSelection() {
        selectApp(at: selectedAppIndex)
    }

    /// Animates changes made to the apps list
    private func updateTableView(with oldSnapshot: AppListSnapshot, with newSnapshot: AppListSnapshot) {
        let oldValue = oldSnapshot.entries
        let newValue = newSnapshot.entries

        tableView.beginUpdates()

        var state = oldValue
        var i = 0, j = 0

        // Iterate both states
        while i < state.count || j < newValue.count {
            tableView.reloadData(forRowIndexes: IndexSet(integer: i), columnIndexes: IndexSet(integer: 0))

            // Skip identical items
            if i < state.count, j < newValue.count, state[i].isSimilar(to: newValue[j]) {
                i += 1
                j += 1
                continue
            }

            // Remove deleted elements
            if i < state.count, !newValue.contains(state[i]) {
                tableView.removeRows(at: IndexSet(integer: i), withAnimation: [.slideUp, .effectFade])
                state.remove(at: i)
                continue
            }

            // Move existing elements
            if let index = state.firstIndex(of: newValue[i]) {
                let newIndex = i - (index < i ? 1 : 0)
                tableView.moveRow(at: index, to: newIndex)

                state.remove(at: index)
                state.insert(newValue[j], at: newIndex)

                i += 1
                j += 1
                continue
            }

            // insert new elements
            tableView.insertRows(at: IndexSet(integer: i), withAnimation: [.slideDown, .effectFade])
            state.insert(newValue[j], at: i)

            i += 1
            j += 1
        }

        tableView.endUpdates()
    }

    /// Returns an appropriate title for update actions for the given app.
    private func updateTitle(for app: App) -> String {
        if let externalUpdater = app.externalUpdaterName {
            String(format: NSLocalizedString("ExternalUpdateAction", comment: "Action to update a given app outside of Latest. The placeholder is filled with the name of the external updater. (App Store, App Name)"), externalUpdater)
        } else {
            NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
        }
    }
}
