//
//  SettingsRootView.swift
//  Latest
//
//  Created by Codex on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import SwiftUI

struct SettingsRootView: View {
	@ObservedObject var viewModel: SettingsViewModel

	var body: some View {
		Group {
			switch viewModel.selectedTab {
			case .general:
				GeneralSettingsView(viewModel: viewModel)
			case .locations:
				LocationsSettingsView(viewModel: viewModel)
			}
		}
		.frame(
			width: viewModel.selectedTab.contentSize.width,
			height: viewModel.selectedTab.contentSize.height
		)
	}
}
