//
//  LatestApplication.swift
//  Latest
//
//  Structural split from the original implementation.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-29.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI

@MainActor
final class ApplicationLifecycleDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}

struct LatestApplication: SwiftUI.App {
  @NSApplicationDelegateAdaptor(ApplicationLifecycleDelegate.self)
  private var lifecycleDelegate

  @AppStorage(ApplicationAppearance.storageKey)
  private var appearanceRawValue = ApplicationAppearance.system.rawValue

  @StateObject private var environment: AppEnvironment
  @StateObject private var appUpdateController = AppUpdateController()

  init() {
    _environment = StateObject(wrappedValue: .live())
  }

  var body: some Scene {
    LatestMainWindowScene(
      environment: environment, appearance: appearance, appUpdateController: appUpdateController,
      start: environment.start, stop: environment.stop)

    Settings {
      SettingsRootView(viewModel: environment.settingsViewModel)
        .modifier(ApplicationAppearanceModifier(appearance: appearance))
    }
  }

  private var appearance: ApplicationAppearance {
    ApplicationAppearance.resolve(appearanceRawValue)
  }
}

/// The runnable app and capture app share one window composition.
/// Lifecycle actions belong to the composition owner, alongside its services.
struct LatestMainWindowScene: Scene {
  let environment: AppEnvironment
  let appearance: ApplicationAppearance
  let appUpdateController: AppUpdateController
  let start: () -> Void
  let stop: () -> Void

  var body: some Scene {
    Window("Latest", id: "main") {
      LatestRootView(environment: environment)
        .modifier(ApplicationAppearanceModifier(appearance: appearance))
        .frame(
          minWidth: VisualMetrics.mainWindowMinWidth,
          minHeight: VisualMetrics.mainWindowMinHeight
        )
        .onAppear {
          start()
        }
        .onDisappear {
          stop()
        }
    }
    .defaultSize(
      width: VisualMetrics.mainWindowDefaultWidth,
      height: VisualMetrics.mainWindowDefaultHeight
    )
    .windowResizability(.contentMinSize)
    .windowToolbarStyle(.unified)
    .commands {
      LatestCommands(
        appCommands: environment.commands,
        updatesViewModel: environment.updatesListViewModel,
        updateCheckingService: environment.updateCheckingService,
        appUpdateController: appUpdateController
      )
    }
  }
}
