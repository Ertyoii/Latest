//
//  SettingsRootView.swift
//  Latest
//
//  Created by Codex on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import SwiftUI

struct SettingsRootView: View {
	@StateObject private var viewModel: SettingsViewModel

	init(viewModel: SettingsViewModel = SettingsViewModel()) {
		_viewModel = StateObject(wrappedValue: viewModel)
	}

	var body: some View {
		TabView(selection: $viewModel.selectedTab) {
			GeneralSettingsView(viewModel: viewModel)
				.tabItem {
					Label(SettingsViewModel.Tab.general.title, systemImage: SettingsViewModel.Tab.general.systemImageName)
				}
				.tag(SettingsViewModel.Tab.general)

			LocationsSettingsView(viewModel: viewModel)
				.tabItem {
					Label(SettingsViewModel.Tab.locations.title, systemImage: SettingsViewModel.Tab.locations.systemImageName)
				}
				.tag(SettingsViewModel.Tab.locations)
		}
		.frame(width: 440, height: 300)
	}
}
