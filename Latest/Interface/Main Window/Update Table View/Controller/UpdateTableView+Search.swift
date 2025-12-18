//
//  UpdateTableView+Search.swift
//  Latest
//
//  Created by Max Langer on 27.12.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import AppKit

/// Custom search field subclass that resigns first responder on ESC
class UpdateSearchField: NSSearchField {
    override func cancelOperation(_: Any?) {
        window?.makeFirstResponder(nil)
    }
}

extension UpdateTableViewController {
    @IBAction func searchFieldTextDidChange(_ sender: NSSearchField) {
        var searchQuery: String? = sender.stringValue
        if sender.stringValue.isEmpty {
            searchQuery = nil
        }
        scheduleTableViewUpdate(with: snapshot.updated(with: searchQuery), animated: false)

        // Reload all visible lists
        scrubber?.reloadData()
    }
}
