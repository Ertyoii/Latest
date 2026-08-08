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
	@ObservedObject var searchFocusController: SearchFocusController
	let implementation: SidebarImplementation
	let showsSupportStatusOverride: Bool?

	init(
		viewModel: UpdatesListViewModel,
		searchFocusController: SearchFocusController,
		implementation: SidebarImplementation = .runtimeDefault,
		showsSupportStatusOverride: Bool? = nil
	) {
		self.viewModel = viewModel
		self.searchFocusController = searchFocusController
		self.implementation = implementation
		self.showsSupportStatusOverride = showsSupportStatusOverride
	}

	var body: some View {
		ZStack(alignment: .top) {
			switch implementation {
			case .appKitTable:
				UpdatesTableBridge(
					viewModel: viewModel,
					showsSupportStatusOverride: showsSupportStatusOverride
				)
			case .nativeList:
				NativeUpdatesList(
					viewModel: viewModel,
					showsSupportStatusOverride: showsSupportStatusOverride
				)
				.padding(.top, 24)
			}

			UpdatesSidebarHeaderView(viewModel: viewModel, searchFocusController: searchFocusController)
		}
	}
}

/// The measured AppKit table remains the shipping renderer until the native
/// candidate matches its layout, interaction, and performance contract.
/// Developers can opt into that candidate without changing user defaults.
enum SidebarImplementation: String, CaseIterable {
	case appKitTable = "appkit"
	case nativeList = "native"

	static let environmentKey = "LATEST_SIDEBAR_IMPLEMENTATION"

	static var runtimeDefault: Self {
		resolve(
			environmentValue: ProcessInfo.processInfo.environment[environmentKey]
		)
	}

	static func resolve(
		environmentValue: String?,
		fallback: Self = .appKitTable
	) -> Self {
		if let environmentValue, let implementation = Self(rawValue: environmentValue) {
			return implementation
		}
		return fallback
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
