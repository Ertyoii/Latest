//
//  GeneralSettingsView.swift
//  Latest
//
//  Created by ertyoii on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-04.
//  Licensed under GPL-3.0; see LICENSE.md.

import SwiftUI

struct GeneralSettingsView: View {
  @ObservedObject var viewModel: SettingsViewModel
  @AppStorage(ApplicationAppearance.storageKey)
  private var appearanceRawValue = ApplicationAppearance.system.rawValue

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      settingsForm

      Spacer(minLength: 16)
      if viewModel.showsInstallHelperBanner {
        installHelperBanner
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 20)
    .padding(.bottom, 16)
    .frame(width: 440, height: 249, alignment: .topLeading)
    .onAppear {
      viewModel.refreshInstallHelperAvailability()
    }
  }

  private var settingsForm: some View {
    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 16) {
      GridRow {
        formLabel("Appearance:")

        appearancePicker
      }

      GridRow(alignment: .top) {
        formLabel("Include:")
          .padding(.top, 1)

        VStack(alignment: .leading, spacing: 14) {
          preferenceOption(
            title: "Apps with limited support",
            description:
              "List apps with limited support. Update information may be outdated or inaccurate, and updates cannot be performed directly in Latest.",
            isOn: limitedSupportBinding
          )

          preferenceOption(
            title: "Unsupported apps",
            description: "Show apps without any available update information.",
            isOn: unsupportedAppsBinding
          )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var appearancePicker: some View {
    Picker("Appearance", selection: $appearanceRawValue) {
      ForEach(ApplicationAppearance.allCases) { appearance in
        Text(appearance.title)
          .tag(appearance.rawValue)
      }
    }
    .labelsHidden()
    .pickerStyle(.segmented)
    .frame(width: 220, height: 24)
    .padding(.leading, 8)
    .accessibilityIdentifier("settings.appearance")
  }

  private var installHelperBanner: some View {
    VStack(alignment: .leading, spacing: 12) {
      Divider()

      HStack(spacing: 12) {
        Text("Enable a helper program to update App Store apps within Latest.")
          .font(.body)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 8)

        Button("Enable") {
          viewModel.registerInstallHelper()
        }
        .frame(width: 65)
      }
    }
  }

  private func formLabel(_ title: String) -> some View {
    Text(title)
      .font(.body)
      .frame(width: 80, alignment: .trailing)
  }

  private func preferenceOption(
    title: String,
    description: String,
    isOn: Binding<Bool>
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Toggle(title, isOn: isOn)
        .toggleStyle(.checkbox)

      Text(description)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
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
