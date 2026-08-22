//
//  LatestApplication.swift
//  Latest
//
//  Created by Codex on 11.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class ApplicationLifecycleDelegate: NSObject, NSApplicationDelegate {
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		true
	}
}

@MainActor
final class AppUpdateController: ObservableObject {
	private let updaterController = SPUStandardUpdaterController(
		startingUpdater: true,
		updaterDelegate: nil,
		userDriverDelegate: nil
	)

	func checkForAppUpdates() {
		updaterController.checkForUpdates(nil)
	}
}

enum ApplicationAppearance: String, CaseIterable, Identifiable {
	case system
	case light
	case dark

	static let storageKey = "applicationAppearance"

	var id: String { rawValue }

	var title: String {
		switch self {
		case .system:
			"System"
		case .light:
			"Light"
		case .dark:
			"Dark"
		}
	}

	var appKitAppearanceName: NSAppearance.Name? {
		switch self {
		case .system:
			nil
		case .light:
			.aqua
		case .dark:
			.darkAqua
		}
	}

	@MainActor
	func apply(to application: NSApplication) {
		guard application.appearance?.name != appKitAppearanceName else { return }
		application.appearance = appKitAppearanceName.flatMap(NSAppearance.init(named:))
	}

	static func resolve(_ rawValue: String) -> Self {
		Self(rawValue: rawValue) ?? .system
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
		#if DEBUG
		let usesLocalUATFixture = ProcessInfo.processInfo.environment["LATEST_LOCAL_UAT_FIXTURE"] == "1"
		_environment = StateObject(wrappedValue: usesLocalUATFixture ? .localUATFixture() : .live())
		startsLiveServices = !usesLocalUATFixture
		#else
		_environment = StateObject(wrappedValue: .live())
		startsLiveServices = true
		#endif
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
			SettingsRootView()
				.modifier(ApplicationAppearanceModifier(appearance: appearance))
		}
	}

	private var appearance: ApplicationAppearance {
		ApplicationAppearance.resolve(appearanceRawValue)
	}
}

private struct ApplicationAppearanceModifier: ViewModifier {
	let appearance: ApplicationAppearance

	func body(content: Content) -> some View {
		content
			.onAppear {
				appearance.apply(to: NSApplication.shared)
			}
			.onChange(of: appearance) { _, newAppearance in
				newAppearance.apply(to: NSApplication.shared)
			}
	}
}

struct LatestRootView: View {
	let environment: AppEnvironment

	@ObservedObject private var updatesViewModel: UpdatesListViewModel
	@ObservedObject private var updateCheckingService: UpdateCheckingService
	@State private var columnVisibility = MainWindowSidebarPolicy.defaultVisibility
	init(environment: AppEnvironment) {
		self.environment = environment
		_updatesViewModel = ObservedObject(wrappedValue: environment.updatesListViewModel)
		_updateCheckingService = ObservedObject(wrappedValue: environment.updateCheckingService)
	}

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			UpdatesSidebarView(
				viewModel: updatesViewModel,
				searchFocusController: environment.searchFocusController
			)
			.navigationSplitViewColumnWidth(
				min: VisualMetrics.sidebarIdealWidth,
				ideal: VisualMetrics.sidebarIdealWidth,
				max: VisualMetrics.sidebarIdealWidth
			)
		} detail: {
			ReleaseNotesDetailView(updatesViewModel: updatesViewModel)
				.frame(minWidth: VisualMetrics.detailMinWidth)
		}
		.navigationSplitViewStyle(.balanced)
		.navigationTitle("Latest")
		.navigationSubtitle(updatesViewModel.statusText)
		.background {
			WindowAccessor { window in
				MainWindowConfiguration.apply(to: window)
			}
		}
		.toolbar {
			ToolbarItem(placement: .navigation) {
				RefreshToolbarButton(isEnabled: !updateCheckingService.isRunning) {
					environment.commands.reload()
				}
			}
			ToolbarItem(placement: .primaryAction) {
				ToolbarUpdateProgressView(
					presentation: ToolbarProgressPresentation(
						isRunning: updateCheckingService.isRunning,
						fraction: updateCheckingService.progressFraction
					)
				)
			}
		}
	}
}

@MainActor
enum MainWindowSidebarPolicy {
	static let defaultVisibility = NavigationSplitViewVisibility.all
}

/// Applies the window behavior SwiftUI does not currently expose. System-owned
/// split-view and Liquid Glass surfaces are deliberately left untouched.
@MainActor
enum MainWindowConfiguration {
	static func apply(to window: NSWindow) {
		window.titlebarSeparatorStyle = .none
	}
}

struct RefreshToolbarButton: View {
	static let accessibilityIdentifier = "toolbar.refresh"
	static let accessibilityLabel = "Check for Updates"
	static let systemImageName = "arrow.clockwise"

	let isEnabled: Bool
	let action: () -> Void

	var body: some View {
		Button(action: performAction) {
			Label(Self.accessibilityLabel, systemImage: Self.systemImageName)
		}
		.labelStyle(.iconOnly)
		.help(NSLocalizedString(
			"CheckForUpdatesToolbarItemToolTip",
			comment: "Tool tip of a toolbar button that checks for updates"
		))
		.disabled(!isEnabled)
		.accessibilityIdentifier(Self.accessibilityIdentifier)
		.accessibilityLabel(Self.accessibilityLabel)
	}

	/// Kept as a small test seam because SwiftUI controls intentionally do not
	/// promise a one-to-one AppKit view hierarchy.
	func performAction() {
		action()
	}
}

enum ToolbarProgressPresentation: Equatable {
	case hidden
	case indeterminate
	case determinate(Double)

	init(isRunning: Bool, fraction: Double?) {
		guard isRunning else {
			self = .hidden
			return
		}
		if let fraction {
			self = .determinate(ToolbarProgressMetrics.normalized(fraction))
		} else {
			self = .indeterminate
		}
	}
}

struct ToolbarUpdateProgressView: View {
	let presentation: ToolbarProgressPresentation

	@ViewBuilder
	var body: some View {
		switch presentation {
		case .hidden:
			EmptyView()
		case .indeterminate:
			ProgressView()
				.id(ToolbarProgressMetrics.indeterminateIdentity)
				.controlSize(.small)
				.toolbarProgressFrame()
				.accessibilityLabel("Scanning applications")
		case .determinate(let fraction):
			ProgressView(value: fraction)
				.id(ToolbarProgressMetrics.determinateIdentity)
				.toolbarProgressFrame()
				.accessibilityLabel("Checking for updates")
		}
	}
}

private extension View {
	func toolbarProgressFrame() -> some View {
		frame(width: ToolbarProgressMetrics.width)
			.padding(.leading, ToolbarProgressMetrics.leadingPadding)
			.padding(.trailing, ToolbarProgressMetrics.trailingPadding)
	}
}

enum ToolbarProgressMetrics {
	static let width: CGFloat = 64
	static let leadingPadding: CGFloat = 10
	static let trailingPadding: CGFloat = 10
	static let determinateIdentity = "toolbar-progress-determinate"
	static let indeterminateIdentity = "toolbar-progress-indeterminate"

	static func normalized(_ fraction: Double) -> Double {
		min(max(fraction, 0), 1)
	}
}
