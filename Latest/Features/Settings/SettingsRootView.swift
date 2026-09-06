//
//  SettingsRootView.swift
//  Latest
//
//  Created by ertyoii on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-04.
//  Licensed under GPL-3.0; see LICENSE.md.

import SwiftUI

struct SettingsRootView: View {
  @ObservedObject private var viewModel: SettingsViewModel

  init(viewModel: SettingsViewModel = SettingsViewModel()) {
    self.viewModel = viewModel
  }

  var body: some View {
    TabView(selection: $viewModel.selectedTab) {
      GeneralSettingsView(viewModel: viewModel)
        .frame(width: 440, height: 255, alignment: .topLeading)
        .tabItem {
          Label(
            SettingsViewModel.Tab.general.title,
            systemImage: SettingsViewModel.Tab.general.systemImageName)
        }
        .tag(SettingsViewModel.Tab.general)

      LocationsSettingsView(viewModel: viewModel)
        .tabItem {
          Label(
            SettingsViewModel.Tab.locations.title,
            systemImage: SettingsViewModel.Tab.locations.systemImageName)
        }
        .tag(SettingsViewModel.Tab.locations)
    }
    .frame(
      width: viewModel.selectedTab.contentSize.width,
      height: viewModel.selectedTab.contentSize.height
    )
  }
}
