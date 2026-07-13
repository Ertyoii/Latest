//
//  SearchFocusController.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Combine

@MainActor
final class SearchFocusController: ObservableObject {
	weak var searchField: NSSearchField?

	func focus() {
		guard let searchField else { return }
		searchField.window?.makeFirstResponder(searchField)
	}

	func resignFocus() {
		guard let searchField else { return }
		searchField.window?.makeFirstResponder(nil)
	}
}
