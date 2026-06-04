//
//  SwiftUIMainWindowController.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

@MainActor
enum SwiftUIMainWindowController {
	static func makeSplitViewController(environment: AppEnvironment) -> NSSplitViewController {
		let splitViewController = NSSplitViewController()
		splitViewController.splitView.dividerStyle = .thin
		splitViewController.splitView.autosaveName = "MainSplitView"

		let sidebarController = NSHostingController(
			rootView: UpdatesSidebarView(
				viewModel: environment.updatesListViewModel,
				searchFocusController: environment.searchFocusController
			)
		)
		let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
		sidebarItem.canCollapse = false
		sidebarItem.minimumThickness = VisualMetrics.sidebarIdealWidth
		sidebarItem.maximumThickness = VisualMetrics.sidebarIdealWidth
		sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)

		let detailController = NSHostingController(
			rootView: ReleaseNotesDetailView(updatesViewModel: environment.updatesListViewModel)
		)
		let detailItem = NSSplitViewItem(viewController: detailController)
		detailItem.minimumThickness = VisualMetrics.detailMinWidth
		detailItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings

		splitViewController.addSplitViewItem(sidebarItem)
		splitViewController.addSplitViewItem(detailItem)

		return splitViewController
	}
}
