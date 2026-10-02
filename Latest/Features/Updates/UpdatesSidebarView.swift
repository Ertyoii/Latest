//
//  UpdatesSidebarView.swift
//  Latest
//
//  Created by ertyoii on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-04.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI

struct UpdatesSidebarView: View {
  @ObservedObject var viewModel: UpdatesListViewModel
  @ObservedObject var searchFocusController: SearchFocusController
  let showsSupportStatusOverride: Bool?
  @FocusState private var focus: SidebarFocus?
  @Environment(\.windowFocus) private var windowFocus
  @State private var previousFocus = SidebarFocus.list
  @State private var keyboardFocusRequest: UInt = 0

  private var activeFocus: FocusState<SidebarFocus?>.Binding { windowFocus ?? $focus }

  init(
    viewModel: UpdatesListViewModel,
    searchFocusController: SearchFocusController,
    showsSupportStatusOverride: Bool? = nil
  ) {
    self.viewModel = viewModel
    self.searchFocusController = searchFocusController
    self.showsSupportStatusOverride = showsSupportStatusOverride
  }

  var body: some View {
    VStack(spacing: 0) {
      UpdatesSidebarHeaderView(
        viewModel: viewModel, searchFocusController: searchFocusController,
        restoreFocus: restorePreviousFocus)
      UpdatesTableBridge(
        viewModel: viewModel, showsSupportStatusOverride: showsSupportStatusOverride,
        keyboardFocusRequest: keyboardFocusRequest,
        keyboardFocusDidBegin: { previousFocus = .list }
      )
    }
    .onChange(of: activeFocus.wrappedValue) { _, new in
      if let new { previousFocus = new }
    }
    .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea(.container, edges: .top))
  }

  private func restorePreviousFocus() {
    activeFocus.wrappedValue = previousFocus == .releaseNotes ? .releaseNotes : nil
    if previousFocus == .list {
      // The native table owns its responder through its existing bridge.
      keyboardFocusRequest &+= 1
    }
  }

}

enum SidebarFocus: Hashable {
  case list
  case releaseNotes
}

extension EnvironmentValues {
  @Entry var windowFocus: FocusState<SidebarFocus?>.Binding?
}

struct UpdatesSidebarHeaderView: View {
  @ObservedObject var viewModel: UpdatesListViewModel
  @ObservedObject var searchFocusController: SearchFocusController
  // Preserve the native placeholder raster in full-size-content toolbar windows.
  @FocusState private var searchIsFocused: Bool
  let restoreFocus: () -> Void

  var body: some View {
    HStack(spacing: 1) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .frame(width: 16)
        .offset(x: -1.5)
        .accessibilityHidden(true)

      TextField(
        "Search",
        // An explicit setter avoids an actor-isolation thunk crash in Xcode 26.6.
        text: Binding(
          get: { viewModel.searchQuery },
          set: { viewModel.setSearchQuery($0) }
        )
      )
      .textFieldStyle(.plain)
      .font(.system(size: 13))
      .focused($searchIsFocused)
      .accessibilityIdentifier("updates.search")
      .accessibilityLabel("Search Apps")
      .onExitCommand {
        searchIsFocused = false
        Task { @MainActor in restoreFocus() }
      }

      if !viewModel.searchQuery.isEmpty {
        Button {
          viewModel.setSearchQuery("")
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .offset(x: 2.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear Search")
      }
    }
    .padding(.horizontal, 7)
    .frame(height: 28)
    .glassEffect(.regular, in: .capsule)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .onChange(of: searchFocusController.request, initial: true) { _, request in
      guard request != nil else { return }
      searchIsFocused = true
    }
  }
}
