//
//  SearchFocusController.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Combine

@MainActor
final class SearchFocusController: ObservableObject {
	@Published private(set) var focusRequest = 0

	func focus() {
		focusRequest &+= 1
	}
}
