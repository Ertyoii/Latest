//
//  GeneralSettingsView.swift
//  Latest
//
//  Created by Codex on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import SwiftUI

struct GeneralSettingsView: View {
	@ObservedObject var viewModel: SettingsViewModel

	var body: some View {
		ZStack(alignment: .topLeading) {
			settingsGrid
				.frame(width: 400, height: 120, alignment: .topLeading)
				.offset(x: 20, y: 20)

			if viewModel.showsInstallHelperBanner {
				installHelperBanner
					.frame(width: 400, height: 59, alignment: .topLeading)
					.offset(x: 20, y: 150)
			}
		}
		.frame(width: 440, height: 219, alignment: .topLeading)
		.onAppear {
			viewModel.refreshInstallHelperAvailability()
		}
	}

	private var settingsGrid: some View {
		ZStack(alignment: .topLeading) {
			Text("Include:")
				.font(.body)
				.frame(width: 52, height: 16, alignment: .trailing)
				.offset(x: -2, y: 0)

			Toggle("Apps with limited support", isOn: limitedSupportBinding)
				.toggleStyle(.checkbox)
				.frame(width: 346, height: 16, alignment: .leading)
				.offset(x: 54, y: 0)

			Text("List apps with limited support. Update information may be outdated or inaccurate, and updates cannot be performed directly in Latest.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
				.frame(width: 330, height: 56, alignment: .topLeading)
				.offset(x: 72, y: 22)

			Toggle("Unsupported apps", isOn: unsupportedAppsBinding)
				.toggleStyle(.checkbox)
				.frame(width: 346, height: 16, alignment: .leading)
				.offset(x: 54, y: 84)

			Text("Show apps without any available update information.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.frame(width: 330, height: 14, alignment: .topLeading)
				.offset(x: 72, y: 106)
		}
	}

	private var installHelperBanner: some View {
		ZStack(alignment: .topLeading) {
			Divider()
				.frame(width: 400)
				.offset(y: 10)

			Text("Enable a helper program to update App Store apps within Latest.")
				.font(.body)
				.textSelection(.enabled)
				.frame(width: 319, height: 30, alignment: .leading)
				.offset(x: -2, y: 19)

			Button("Enable") {
				viewModel.registerInstallHelper()
			}
			.frame(width: 65, height: 30)
			.offset(x: 335, y: 19)
		}
	}

	private var limitedSupportBinding: Binding<Bool> {
		Binding(
			get: { viewModel.includeAppsWithLimitedSupport },
			set: { viewModel.includeAppsWithLimitedSupport = $0 }
		)
	}

	private var unsupportedAppsBinding: Binding<Bool> {
		Binding(
			get: { viewModel.includeUnsupportedApps },
			set: { viewModel.includeUnsupportedApps = $0 }
		)
	}
}
