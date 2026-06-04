//
//  MainWindowView.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import SwiftUI

struct MainWindowView: View {
	@ObservedObject var environment: AppEnvironment

	var body: some View {
		MainSplitView(
			updatesViewModel: environment.updatesListViewModel,
			searchFocusController: environment.searchFocusController
		)
		.background(WindowAccessor { window in
			window.titlebarAppearsTransparent = true
			window.toolbarStyle = .unified
			window.title = Bundle.main.localizedInfoDictionary?[kCFBundleNameKey as String] as? String ?? "Latest"
			window.titleVisibility = .visible
			window.subtitle = environment.updatesListViewModel.statusText
			_ = window.setFrameAutosaveName("MainWindowSize")
		})
	}
}
