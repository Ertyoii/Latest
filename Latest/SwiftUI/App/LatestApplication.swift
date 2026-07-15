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

private struct LatestRootView: View {
	let environment: AppEnvironment

	@ObservedObject private var updatesViewModel: UpdatesListViewModel
	@ObservedObject private var updateCheckingService: UpdateCheckingService

	init(environment: AppEnvironment) {
		self.environment = environment
		_updatesViewModel = ObservedObject(wrappedValue: environment.updatesListViewModel)
		_updateCheckingService = ObservedObject(wrappedValue: environment.updateCheckingService)
	}

	var body: some View {
		NavigationSplitView(columnVisibility: .constant(.all)) {
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
				MainWindowChrome.configure(
					window,
					commands: environment.commands,
					refreshIsEnabled: !updateCheckingService.isRunning
				)
			}
		}
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				updateProgress
			}
		}
	}

	@ViewBuilder
	private var updateProgress: some View {
		if updateCheckingService.isRunning {
			if let progress = updateCheckingService.progressFraction {
				ProgressView(value: ToolbarProgressMetrics.normalized(progress))
					.id(ToolbarProgressMetrics.determinateIdentity)
					.frame(width: ToolbarProgressMetrics.width)
					.padding(.leading, ToolbarProgressMetrics.leadingPadding)
					.padding(.trailing, ToolbarProgressMetrics.trailingPadding)
					.accessibilityLabel("Checking for updates")
			} else {
				ProgressView()
					.id(ToolbarProgressMetrics.indeterminateIdentity)
					.controlSize(.small)
					.frame(width: ToolbarProgressMetrics.width)
					.padding(.leading, ToolbarProgressMetrics.leadingPadding)
					.padding(.trailing, ToolbarProgressMetrics.trailingPadding)
					.accessibilityLabel("Scanning applications")
			}
		}
	}
}

@MainActor
enum MainWindowChrome {
	private static var refreshTargetAssociationKey: UInt8 = 0

	static func configure(_ window: NSWindow, commands: AppCommands, refreshIsEnabled: Bool) {
		window.titlebarSeparatorStyle = .none
		if let contentView = window.contentView {
			configureSidebarGlassSurface(in: contentView)
		}

		let target = refreshTarget(for: window, commands: commands)
		repurposeSidebarToggleItem(in: window, target: target, isEnabled: refreshIsEnabled)

		// SwiftUI may finish installing its standard toolbar items on the next
		// main-loop pass. Repeat once so the native toggle is reliably retargeted.
		DispatchQueue.main.async { [weak window, weak target] in
			guard let window, let target else { return }
			if let contentView = window.contentView {
				configureSidebarGlassSurface(in: contentView)
			}
			repurposeSidebarToggleItem(in: window, target: target, isEnabled: refreshIsEnabled)
		}
	}

	static func configureSidebarGlassSurface(in rootView: NSView) {
		if let glassView = rootView as? NSGlassEffectView,
		   abs(glassView.bounds.width - VisualMetrics.sidebarIdealWidth) < 0.5,
		   glassView.bounds.height >= VisualMetrics.mainWindowMinHeight - (VisualMetrics.sidebarGlassInset * 2) {
			// The system insets this surface from the window by 8pt. A 20pt
			// inner radius follows the standard window's 28pt concentric curve.
			glassView.cornerRadius = VisualMetrics.sidebarGlassCornerRadius
		}

		for subview in rootView.subviews {
			configureSidebarGlassSurface(in: subview)
		}
	}

	static func repurposeSidebarToggleItem(
		_ item: NSToolbarItem,
		target: MainToolbarRefreshTarget,
		isEnabled: Bool = true
	) {
		let tooltip = NSLocalizedString(
			"CheckForUpdatesToolbarItemToolTip",
			comment: "Tool tip of a toolbar button that checks for updates"
		)
		let image = NSImage(
			systemSymbolName: "arrow.clockwise",
			accessibilityDescription: "Check for Updates"
		)

		item.label = "Check for Updates"
		item.paletteLabel = "Check for Updates"
		item.toolTip = tooltip
		item.image = image
		item.target = target
		item.action = #selector(MainToolbarRefreshTarget.reload(_:))

		let button = (item.view as? MainToolbarRefreshButton) ?? MainToolbarRefreshButton()
		button.image = image
		button.imagePosition = .imageOnly
		button.imageScaling = .scaleProportionallyDown
		button.isBordered = false
		button.bezelStyle = .toolbar
		button.controlSize = .regular
		button.target = target
		button.action = #selector(MainToolbarRefreshTarget.reload(_:))
		button.toolTip = tooltip
		button.isEnabled = isEnabled
		button.setAccessibilityLabel("Check for Updates")
		item.view = button
	}

	private static func repurposeSidebarToggleItem(
		in window: NSWindow,
		target: MainToolbarRefreshTarget,
		isEnabled: Bool
	) {
		guard let item = window.toolbar?.items.first(where: isSidebarToggleItem) else {
			return
		}
		repurposeSidebarToggleItem(item, target: target, isEnabled: isEnabled)
	}

	static func isSidebarToggleItem(_ item: NSToolbarItem) -> Bool {
		if item.itemIdentifier == .toggleSidebar || item.action == NSSelectorFromString("toggleSidebar:") {
			return true
		}

		let identifier = item.itemIdentifier.rawValue.lowercased()
		return identifier.contains("sidebar") && identifier.contains("toggle")
	}

	private static func refreshTarget(for window: NSWindow, commands: AppCommands) -> MainToolbarRefreshTarget {
		if let target = objc_getAssociatedObject(window, &refreshTargetAssociationKey) as? MainToolbarRefreshTarget {
			target.commands = commands
			return target
		}

		let target = MainToolbarRefreshTarget(commands: commands)
		objc_setAssociatedObject(
			window,
			&refreshTargetAssociationKey,
			target,
			.OBJC_ASSOCIATION_RETAIN_NONATOMIC
		)
		return target
	}
}

@MainActor
final class MainToolbarRefreshTarget: NSObject {
	weak var commands: AppCommands?

	init(commands: AppCommands) {
		self.commands = commands
	}

	@objc func reload(_ sender: Any?) {
		commands?.reload()
	}
}

@MainActor
final class MainToolbarRefreshButton: NSButton {}

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
