//
//  MainSplitView.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import SwiftUI

struct MainSplitView: View {
	@ObservedObject var updatesViewModel: UpdatesListViewModel
	@ObservedObject var searchFocusController: SearchFocusController

	var body: some View {
		HSplitView {
			UpdatesSidebarView(viewModel: updatesViewModel, searchFocusController: searchFocusController)
				.frame(width: VisualMetrics.sidebarIdealWidth)

			ReleaseNotesDetailView(updatesViewModel: updatesViewModel)
				.frame(minWidth: VisualMetrics.detailMinWidth)
		}
	}
}
