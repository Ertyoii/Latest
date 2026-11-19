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

  @AppStorage(AppStoreUpdateSettings.alwaysPerformManualUpdates.rawValue)
  private var useAppStore = false

  var body: some View {
    settingsForm.padding(20)
  }

  private var settingsForm: some View {
    VStack(spacing: 16) {
      GroupBox {
        HStack {
          Text("Appearance")
          Spacer(minLength: 16)
          appearancePicker
        }
        .padding(10)
      }

      GroupBox {
        HStack {
          Text("Install App Store updates with")
          Spacer(minLength: 16)
          Picker("Install App Store updates with", selection: $useAppStore) {
            Text("Latest").tag(false)
            Text("App Store").tag(true)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 150)
        }
        .padding(10)
      }

      GroupBox("App visibility") {
        VStack(alignment: .leading, spacing: 14) {
          preferenceOption(
            title: "Apps with limited support",
            description: "Update information may be inaccurate. Update these apps outside Latest.",
            isOn: limitedSupportBinding
          )

          Divider()

          preferenceOption(
            title: "Unsupported apps",
            description: "Show apps without any available update information.",
            isOn: unsupportedAppsBinding
          )
        }
        .padding(10)
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
    .frame(width: 230)
    .accessibilityIdentifier("settings.appearance")
  }

  private func preferenceOption(
    title: String,
    description: String,
    isOn: Binding<Bool>
  ) -> some View {
    Toggle(isOn: isOn) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .toggleStyle(.switch)
    .accessibilityLabel(title)
    .accessibilityHint(description)
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
