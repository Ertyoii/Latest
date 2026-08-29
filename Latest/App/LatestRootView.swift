//
//  LatestRootView.swift
//  Latest
//
//  Structural split from the original implementation.
//

import SwiftUI

struct LatestRootView: View {
	let environment: AppEnvironment

	@ObservedObject private var updatesViewModel: UpdatesListViewModel
	@ObservedObject private var updateCheckingService: UpdateCheckingService
	@State private var columnVisibility = MainWindowSidebarPolicy.defaultVisibility
	init(environment: AppEnvironment) {
		self.environment = environment
		_updatesViewModel = ObservedObject(wrappedValue: environment.updatesListViewModel)
		_updateCheckingService = ObservedObject(wrappedValue: environment.updateCheckingService)
	}

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			UpdatesSidebarView(
				viewModel: updatesViewModel,
				searchFocusController: environment.searchFocusController,
				showsSupportStatusOverride: updatesViewModel.showsSupportStatus
			)
			.navigationSplitViewColumnWidth(
				min: VisualMetrics.sidebarIdealWidth,
				ideal: VisualMetrics.sidebarIdealWidth,
				max: VisualMetrics.sidebarIdealWidth
			)
		} detail: {
			ReleaseNotesDetailView(
				updatesViewModel: updatesViewModel,
				showsSupportStatus: updatesViewModel.showsSupportStatus
			)
				.frame(minWidth: VisualMetrics.detailMinWidth)
		}
		.navigationSplitViewStyle(.balanced)
		.navigationTitle("Latest")
		.navigationSubtitle(updatesViewModel.statusText)
		.background {
			WindowAccessor { window in
				MainWindowConfiguration.apply(to: window)
			}
		}
		.toolbar {
			ToolbarItem(placement: .navigation) {
				RefreshToolbarButton(isEnabled: !updateCheckingService.isRunning) {
					environment.commands.reload()
				}
			}
			ToolbarItem(placement: .primaryAction) {
				ToolbarUpdateProgressView(
					presentation: ToolbarProgressPresentation(
						isRunning: updateCheckingService.isRunning,
						fraction: updateCheckingService.progressFraction
					)
				)
			}
		}
	}
}

@MainActor
enum MainWindowSidebarPolicy {
	static let defaultVisibility = NavigationSplitViewVisibility.all
}
