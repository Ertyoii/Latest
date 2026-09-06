//
//  UpdatesSidebarView.swift
//  Latest
//
//  Created by ertyoii on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-04.
//  Licensed under GPL-3.0; see LICENSE.md.

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
    ZStack(alignment: .top) {

      UpdatesTableBridge(
        viewModel: viewModel, showsSupportStatusOverride: showsSupportStatusOverride)

      UpdatesSidebarHeaderView(viewModel: viewModel, searchFocusController: searchFocusController)
    }
    .background {
      SidebarGlassGeometryAccessor(
        cornerRadius: VisualMetrics.sidebarGlassCornerRadius,
        leadingLayoutInset: VisualMetrics.sidebarGlassLeadingLayoutInset
      )
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}

struct UpdatesSidebarHeaderView: View {
  @ObservedObject var viewModel: UpdatesListViewModel
  @ObservedObject var searchFocusController: SearchFocusController

  var body: some View {
    SearchFieldRepresentable(
      text: $viewModel.searchQuery,
      focusController: searchFocusController,
      onTextChanged: viewModel.setSearchQuery
    )
    .frame(height: 28)
    .padding(.top, -1)
    .padding(.leading, 24)
    .padding(.trailing, 20)
    .frame(maxWidth: .infinity, minHeight: 39, maxHeight: 39, alignment: .top)
  }
}
