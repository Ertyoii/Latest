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

struct LatestApplication: SwiftUI.App {
	@NSApplicationDelegateAdaptor(ApplicationLifecycleDelegate.self)
	private var lifecycleDelegate

	@StateObject private var environment = AppEnvironment.live()
	@StateObject private var appUpdateController = AppUpdateController()

	var body: some Scene {
		Window("Latest", id: "main") {
			LatestRootView(environment: environment)
				.frame(
					minWidth: VisualMetrics.mainWindowMinWidth,
					minHeight: VisualMetrics.mainWindowMinHeight
				)
				.onAppear {
					environment.start()
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
		}
	}
}

struct LatestRootView: View {
	let environment: AppEnvironment
	let sidebarImplementation: SidebarImplementation

	@ObservedObject private var updatesViewModel: UpdatesListViewModel
	@ObservedObject private var updateCheckingService: UpdateCheckingService
	init(
		environment: AppEnvironment,
		sidebarImplementation: SidebarImplementation = .runtimeDefault
	) {
		self.environment = environment
		self.sidebarImplementation = sidebarImplementation
		_updatesViewModel = ObservedObject(wrappedValue: environment.updatesListViewModel)
		_updateCheckingService = ObservedObject(wrappedValue: environment.updateCheckingService)
	}

	var body: some View {
		NavigationSplitView(columnVisibility: MainWindowSidebarPolicy.columnVisibility) {
			UpdatesSidebarView(
				viewModel: updatesViewModel,
				searchFocusController: environment.searchFocusController,
				implementation: sidebarImplementation
			)
			.toolbar(removing: .sidebarToggle)
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
	static var columnVisibility: Binding<NavigationSplitViewVisibility> {
		.constant(.all)
	}
}

/// Keep the system-created sidebar glass concentric with the window. SwiftUI does
/// not expose the sidebar surface's shape, so this bridge adjusts only the public
/// `NSGlassEffectView` matching the fixed sidebar geometry.
@MainActor
enum MainWindowConfiguration {
	static func apply(to window: NSWindow) {
		window.titlebarSeparatorStyle = .none
		if let contentView = window.contentView {
			configureSidebarGlassSurface(in: contentView)
		}

		// SwiftUI can install the split-view glass after the accessor first runs.
		DispatchQueue.main.async { [weak window] in
			guard let contentView = window?.contentView else { return }
			configureSidebarGlassSurface(in: contentView)
		}
	}

	static func configureSidebarGlassSurface(in rootView: NSView) {
		if let glassView = rootView as? NSGlassEffectView,
		   abs(glassView.bounds.width - VisualMetrics.sidebarIdealWidth) < 0.5,
		   glassView.bounds.height >= VisualMetrics.mainWindowMinHeight - (VisualMetrics.sidebarGlassInset * 2) {
			glassView.cornerRadius = VisualMetrics.sidebarGlassCornerRadius
		}

		for subview in rootView.subviews {
			configureSidebarGlassSurface(in: subview)
		}
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
