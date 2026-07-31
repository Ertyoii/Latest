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
	enum Request: Equatable {
		case none
		case focus(UInt)
		case resign(UInt)
	}

	@Published private(set) var request: Request = .none
	private var generation: UInt = 0

	func focus() {
		generation &+= 1
		request = .focus(generation)
	}

	func resignFocus() {
		generation &+= 1
		request = .resign(generation)
	}
}
