//
//  UpdatesSidebarView.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import SwiftUI

struct UpdatesSidebarView: View {
	@ObservedObject var viewModel: UpdatesListViewModel
	@ObservedObject private var searchFocusController: SearchFocusController
	@State private var isSearchPresented = false

	init(
		viewModel: UpdatesListViewModel,
		searchFocusController: SearchFocusController = SearchFocusController()
	) {
		self.viewModel = viewModel
		self.searchFocusController = searchFocusController
	}

	var body: some View {
		List(selection: selection) {
			ForEach(viewModel.snapshot.sections) { content in
				Section {
					ForEach(content.apps, id: \.identifier) { app in
						row(for: app)
					}
				} header: {
					UpdateSectionHeaderView(section: content.section)
				}
			}
		}
		.listStyle(.sidebar)
		.searchable(
			text: searchQuery,
			isPresented: $isSearchPresented,
			placement: .sidebar,
			prompt: Text("Search")
		)
		.navigationSplitViewColumnWidth(
			min: VisualMetrics.sidebarIdealWidth,
			ideal: VisualMetrics.sidebarIdealWidth,
			max: VisualMetrics.sidebarIdealWidth
		)
		.onChange(of: searchFocusController.focusRequest) {
			isSearchPresented = true
		}
	}

	private var searchQuery: Binding<String> {
		Binding(
			get: { viewModel.searchQuery },
			set: { viewModel.setSearchQuery($0) }
		)
	}

	private var selection: Binding<App.Bundle.Identifier?> {
		Binding(
			get: { viewModel.selectedApp?.identifier },
			set: { viewModel.select(viewModel.snapshot.app(withIdentifier: $0)) }
		)
	}

	private var showsSupportState: Bool {
		AppListSettings.shared.includeAppsWithLimitedSupport ||
			AppListSettings.shared.includeUnsupportedApps
	}

	private func row(for app: App) -> some View {
		UpdateRowView(app: app, showsSupportState: showsSupportState)
			.tag(app.identifier)
			.contextMenu {
				Button(updateTitle(for: app)) {
					viewModel.update(app)
				}
				.disabled(!app.updateAvailable || app.isUpdating)

				Button(app.isIgnored ? "Don't Ignore" : "Ignore") {
					viewModel.setIgnored(!app.isIgnored, for: app)
				}

				Divider()

				Button("Open") {
					viewModel.open(app)
				}
				Button("Show in Finder") {
					viewModel.revealInFinder(app)
				}
			}
			.swipeActions(edge: .trailing, allowsFullSwipe: false) {
				if app.updateAvailable && !app.isUpdating {
					Button {
						viewModel.update(app)
					} label: {
						Label(updateTitle(for: app), systemImage: "square.and.arrow.down")
					}
					.tint(.cyan)
				}
			}
			.swipeActions(edge: .leading, allowsFullSwipe: false) {
				Button {
					viewModel.open(app)
				} label: {
					Label("Open", systemImage: "arrow.up.forward.app")
				}

				Button {
					viewModel.revealInFinder(app)
				} label: {
					Label("Show in Finder", systemImage: "finder")
				}
				.tint(.gray)
			}
	}

	private func updateTitle(for app: App) -> String {
		if let externalUpdater = app.externalUpdaterName {
			return String(
				format: NSLocalizedString(
					"ExternalUpdateAction",
					comment: "Action to update a given app outside of Latest."
				),
				externalUpdater
			)
		}

		return NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
	}
}
