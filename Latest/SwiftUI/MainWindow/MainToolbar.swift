//
//  MainToolbar.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import SwiftUI

struct MainToolbar: ToolbarContent {
	@ObservedObject var environment: AppEnvironment

	var body: some ToolbarContent {
		ToolbarItemGroup(placement: .automatic) {
			Spacer()

			if environment.updateCheckingService.isRunning {
				if let progressFraction = environment.updateCheckingService.progressFraction {
					ProgressView(value: progressFraction)
						.controlSize(.small)
						.frame(width: 28)
				} else {
					ProgressView()
						.controlSize(.small)
						.frame(width: 28)
				}
			}

			Button {
				environment.commands.reload()
			} label: {
				Image(systemName: "arrow.clockwise")
			}
			.help(NSLocalizedString("CheckForUpdatesToolbarItemToolTip", comment: "Tool tip of a toolbar button that checks for updates"))
			.disabled(environment.updateCheckingService.isRunning)

			Button {
				environment.commands.updateAll()
			} label: {
				Image("custom.arrow.down.square.stack")
			}
			.help(NSLocalizedString("UpdateAllToolbarItemToolTip", comment: "Tool tip of a toolbar button that performs updates for all apps with update available"))
			.disabled(!environment.updatesListViewModel.hasUpdatesAvailable)
		}
	}
}
