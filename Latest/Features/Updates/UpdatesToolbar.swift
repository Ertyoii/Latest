//
//  UpdatesToolbar.swift
//  Latest
//
//  Structural split from the original implementation.
//

import SwiftUI

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
