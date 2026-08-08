//
//  SidebarInteractionPolicy.swift
//  Latest
//
//  Created by Codex on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation

/// Renderer-independent sidebar behavior. Keeping these decisions outside the
/// view makes keyboard movement and action availability directly testable.
@MainActor
struct SidebarInteractionPolicy {
	enum Movement {
		case previous
		case next
	}

	enum SwipeEdge {
		case leading
		case trailing
	}

	enum Action: Equatable {
		case update
		case open
		case revealInFinder
		case ignore
		case unignore
	}

	let entries: [AppListSnapshot.Entry]

	func isSelectable(row: Int) -> Bool {
		app(at: row) != nil
	}

	func isSectionHeader(row: Int) -> Bool {
		guard entries.indices.contains(row) else { return false }
		if case .section = entries[row] {
			return true
		}
		return false
	}

	func app(at row: Int) -> App? {
		guard entries.indices.contains(row), case .app(let app) = entries[row] else {
			return nil
		}
		return app
	}

	func selectableRow(from row: Int?, moving movement: Movement) -> Int? {
		guard !entries.isEmpty else { return nil }
		let stride: Int
		let start: Int
		switch movement {
		case .previous:
			stride = -1
			start = min((row ?? entries.count) - 1, entries.count - 1)
		case .next:
			stride = 1
			start = max((row ?? -1) + 1, 0)
		}

		var candidate = start
		while entries.indices.contains(candidate) {
			if isSelectable(row: candidate) {
				return candidate
			}
			candidate += stride
		}
		return nil
	}

	func targetApp(clickedRow: Int, selectedRow: Int) -> App? {
		if let clickedApp = app(at: clickedRow) {
			return clickedApp
		}
		return app(at: selectedRow)
	}

	func swipeActions(for row: Int, edge: SwipeEdge) -> [Action] {
		guard let app = app(at: row) else { return [] }
		switch edge {
		case .leading:
			return [.open, .revealInFinder]
		case .trailing:
			return app.updateAvailable && !app.isUpdating ? [.update] : []
		}
	}

	func contextActions(for app: App) -> [Action] {
		var actions: [Action] = []
		if app.updateAvailable && !app.isUpdating {
			actions.append(.update)
		}
		actions.append(app.isIgnored ? .unignore : .ignore)
		actions.append(contentsOf: [.open, .revealInFinder])
		return actions
	}

	static func accessibilityLabel(for app: App, dateFormatter: DateFormatter) -> String {
		var components = [app.name]
		if let version = app.localizedVersionInformation?.combined(includeNew: app.updateAvailable) {
			components.append(version)
		}
		components.append(dateFormatter.string(from: app.updateDate))
		components.append(app.source.supportState.label)
		if app.updateAvailable {
			components.append(NSLocalizedString("UpdateAction", comment: "Action to update a given app."))
		}
		return components.joined(separator: ", ")
	}
}
