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
		Form {
			Section("Include") {
				preferenceRow(
					title: "Apps with limited support",
					description: "List apps with limited support. Update information may be outdated or inaccurate, and updates cannot be performed directly in Latest.",
					isOn: limitedSupportBinding
				)

				preferenceRow(
					title: "Unsupported apps",
					description: "Show apps without any available update information.",
					isOn: unsupportedAppsBinding
				)
			}

			if viewModel.showsInstallHelperBanner {
				Section {
					HStack {
						Text("Enable a helper program to update App Store apps within Latest.")
						Spacer()
						Button("Enable") {
							viewModel.registerInstallHelper()
						}
						.buttonStyle(.borderedProminent)
					}
				}
			}
		}
		.formStyle(.grouped)
		.onAppear {
			viewModel.refreshInstallHelperAvailability()
		}
	}

	private func preferenceRow(
		title: String,
		description: String,
		isOn: Binding<Bool>
	) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Toggle(title, isOn: isOn)
			Text(description)
				.font(.caption)
				.foregroundStyle(.secondary)
				.padding(.leading, 20)
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
