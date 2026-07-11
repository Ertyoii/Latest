//
//  UpdateRowView.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Combine
import SwiftUI

struct UpdateRowView: View {
	enum Layout {
		static let leadingPadding: CGFloat = 2
		static let trailingPadding: CGFloat = 6
		static let horizontalSpacing: CGFloat = 8
		static let iconSize: CGFloat = 50
		static let trailingWidth: CGFloat = 59

		static func availableVersionWidth(rowWidth: CGFloat) -> CGFloat {
			rowWidth - leadingPadding - trailingPadding - iconSize - trailingWidth - (horizontalSpacing * 2)
		}
	}

	let app: App
	let showsSupportState: Bool

	@StateObject private var updateState: UpdateRowState
	@State private var icon: NSImage?

	init(app: App, showsSupportState: Bool) {
		self.app = app
		self.showsSupportState = showsSupportState
		_updateState = StateObject(wrappedValue: UpdateRowState(identifier: app.identifier))
	}

	var body: some View {
		HStack(spacing: Layout.horizontalSpacing) {
			appIcon

			VStack(alignment: .leading, spacing: 0) {
				Text(app.name)
					.font(.system(size: 13, weight: .semibold))
					.lineLimit(1)

				if let versionInformation = app.localizedVersionInformation {
					Text(versionInformation.current)
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
						.lineLimit(1)

					if app.updateAvailable, let newVersion = versionInformation.new {
						Text(newVersion)
							.font(.system(size: 11))
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)

			VStack(alignment: .trailing, spacing: 6) {
				Text(Self.dateFormatter.string(from: app.updateDate))
					.font(.callout)
					.foregroundStyle(.secondary)
					.lineLimit(1)

				statusIndicator
			}
			.frame(width: Layout.trailingWidth, alignment: .trailing)
		}
		.padding(.leading, Layout.leadingPadding)
		.padding(.trailing, Layout.trailingPadding)
		.frame(height: VisualMetrics.appRowHeight)
		.contentShape(.rect)
		.onAppear {
			IconCache.shared.icon(for: app) { image in
				icon = image
			}
		}
	}

	private var appIcon: some View {
		Group {
			if let icon {
				Image(nsImage: icon)
					.resizable()
					.scaledToFit()
			} else {
				Image(systemName: "app")
					.resizable()
					.scaledToFit()
					.foregroundStyle(.secondary)
			}
		}
		.frame(width: Layout.iconSize, height: Layout.iconSize)
		.accessibilityHidden(true)
	}

	@ViewBuilder
	private var statusIndicator: some View {
		switch updateState.state {
		case .downloading(let loadedSize, let totalSize) where totalSize > 0:
			ProgressView(value: Double(loadedSize), total: Double(totalSize))
				.progressViewStyle(.circular)
				.controlSize(.small)
				.accessibilityLabel("Downloading update")
		case .extracting(let progress):
			ProgressView(value: progress)
				.progressViewStyle(.circular)
				.controlSize(.small)
				.accessibilityLabel("Extracting update")
		case .pending, .initializing, .downloading, .installing, .cancelling:
			ProgressView()
				.controlSize(.small)
				.accessibilityLabel("Updating")
		case .error:
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(.red)
				.help("The update failed")
		case .none:
			if showsSupportState {
				Circle()
					.fill(supportColor)
					.frame(width: 9, height: 9)
					.help(app.source.supportState.label)
					.accessibilityLabel(app.source.supportState.label)
			}
		}
	}

	private var supportColor: Color {
		switch app.source.supportState {
		case .full: .green
		case .limited: .orange
		case .none: .gray
		}
	}

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.timeStyle = .none
		formatter.dateStyle = .short
		formatter.doesRelativeDateFormatting = true
		return formatter
	}()
}

@MainActor
private final class UpdateRowState: ObservableObject {
	@Published private(set) var state: UpdateOperation.ProgressState

	private var observationTask: Task<Void, Never>?

	init(identifier: App.Bundle.Identifier) {
		self.state = UpdateQueue.shared.state(for: identifier)
		self.observationTask = Task { [weak self] in
			for await state in UpdateQueue.shared.states(for: identifier) {
				guard !Task.isCancelled, let self else { break }
				self.state = state
			}
		}
	}

	deinit {
		observationTask?.cancel()
	}
}
