//
//  UpdateTableView.swift
//  Latest
//
//  Created by Max Langer on 16.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import Cocoa

/// The tableView behind the updates list
class UpdateTableView: NSTableView {
    /// Only the separator lines for populated rows will be drawn
    override func drawGrid(inClipRect _: NSRect) {}

    override func menu(for event: NSEvent) -> NSMenu? {
        let clickedPoint = convert(event.locationInWindow, from: nil)
        let row = row(at: clickedPoint)

        if row < 0 || delegate?.tableView!(self, isGroupRow: row) ?? false {
            return nil
        }

        return super.menu(for: event)
    }
}
