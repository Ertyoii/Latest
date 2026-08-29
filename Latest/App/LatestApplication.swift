//
//  LatestApplication.swift
//  Latest
//
//  Structural split from the original implementation.
//

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
	private let startsLiveServices: Bool

	init() {
		_environment = StateObject(wrappedValue: .live())
		startsLiveServices = true
	}

	var body: some Scene {
		Window("Latest", id: "main") {
			LatestRootView(environment: environment)
				.modifier(ApplicationAppearanceModifier(appearance: appearance))
				.frame(
					minWidth: VisualMetrics.mainWindowMinWidth,
					minHeight: VisualMetrics.mainWindowMinHeight
				)
				.onAppear {
					if startsLiveServices {
						environment.start()
					}
				}
				.onDisappear {
					environment.stop()
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

		Settings {
			SettingsRootView(viewModel: environment.settingsViewModel)
				.modifier(ApplicationAppearanceModifier(appearance: appearance))
		}
	}

	private var appearance: ApplicationAppearance {
		ApplicationAppearance.resolve(appearanceRawValue)
	}
}
