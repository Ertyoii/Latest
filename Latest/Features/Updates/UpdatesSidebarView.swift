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
      UpdatesSidebarHeaderView(viewModel: viewModel, searchFocusController: searchFocusController)
      UpdatesTableBridge(
        viewModel: viewModel, showsSupportStatusOverride: showsSupportStatusOverride)
    }
    .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea(.container, edges: .top))
  }
}

struct UpdatesSidebarHeaderView: View {
  @ObservedObject var viewModel: UpdatesListViewModel
  @ObservedObject var searchFocusController: SearchFocusController

  var body: some View {
    SearchFieldRepresentable(
      text: viewModel.searchQuery,
      focusController: searchFocusController,
      onTextChanged: viewModel.setSearchQuery
    )
    .frame(height: 28)
    .glassEffect(.regular, in: .capsule)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}
