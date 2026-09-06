//
//  SearchFocusController.swift
//  Latest
//
//  Created by ertyoii on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-04.
//  Licensed under GPL-3.0; see LICENSE.md.

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
