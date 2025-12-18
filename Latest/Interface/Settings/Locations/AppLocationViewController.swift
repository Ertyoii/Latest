//
//  AppLocationViewController.swift
//  Latest
//
//  Created by Max Langer on 29.02.24.
//  Copyright © 2024 Max Langer. All rights reserved.
//

import AppKit

/// View displaying a list of directories to be checked for apps with updates.
class AppDirectoryViewController: SettingsTabItemViewController, NSTableViewDataSource, NSTableViewDelegate {
    // MARK: - View Lifecycle

    @IBOutlet private var tableView: NSTableView!
    @IBOutlet private var actionControl: NSSegmentedControl!

    override func viewDidLoad() {
        super.viewDidLoad()
        validateButtons()
    }

    private lazy var directoryStore: AppDirectoryStore = .init(updateHandler: { [weak self] in
        Task { @MainActor [weak self] in
            self?.tableView.reloadData()
            self?.validateButtons()
        }
    })

    // MARK: - Table

    func numberOfRows(in _: NSTableView) -> Int {
        directoryStore.URLs.count
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("directoryCellView"), owner: self) as? AppDirectoryCellView else { return nil }
        view.url = directoryStore.URLs[row]

        return view
    }

    func tableViewSelectionDidChange(_: Notification) {
        validateButtons()
    }

    // MARK: - Actions

    /// Possible actions on the segmented control.
    private enum Action: Int {
        /// Add a new directory to the list.
        case add = 0

        /// Remove the selected directory from the list.
        case delete = 1
    }

    @IBAction func performAction(_ sender: NSSegmentedControl) {
        switch Action(rawValue: sender.selectedSegment) {
        case .add:
            presentOpenPanel()
        case .delete:
            let selectedIndex = tableView.selectedRow
            guard selectedIndex != -1 else { return }
            let url = directoryStore.URLs[selectedIndex]
            if directoryStore.canRemove(url) {
                directoryStore.remove(url)
            }
        case .none:
            ()
        }
    }

    private func validateButtons() {
        let selectedIndex = tableView.selectedRow
        let enabled = if selectedIndex == -1 {
            false
        } else {
            directoryStore.canRemove(directoryStore.URLs[selectedIndex])
        }

        actionControl.setEnabled(enabled, forSegment: Action.delete.rawValue)
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true

        panel.beginSheetModal(for: view.window!) { response in
            guard response == .OK else { return }
            for url in panel.urls {
                self.directoryStore.add(url)
            }
        }
    }
}
