//
//  ReleaseNotesDetailView.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

struct ReleaseNotesDetailView: View {
	@ObservedObject var updatesViewModel: UpdatesListViewModel
	@StateObject private var detailViewModel: ReleaseNotesDetailViewModel
	let showsSupportStatus: Bool

	init(
		updatesViewModel: UpdatesListViewModel,
		detailViewModel: ReleaseNotesDetailViewModel = ReleaseNotesDetailViewModel(),
		showsSupportStatus: Bool = true
	) {
		self.updatesViewModel = updatesViewModel
		self.showsSupportStatus = showsSupportStatus
		_detailViewModel = StateObject(wrappedValue: detailViewModel)
	}

	var body: some View {
		ReleaseNotesDetailSurface(
			app: detailViewModel.app,
			contentState: detailViewModel.contentState,
			showsSupportStatus: showsSupportStatus,
			updating: updatesViewModel.updating
		)
		.task(id: selectionKey) {
			detailViewModel.display(updatesViewModel.selectedApp)
		}
		.transaction { transaction in
			transaction.animation = nil
			transaction.disablesAnimations = true
		}
	}

	private var selectionKey: String {
		updatesViewModel.selectedApp.map(ReleaseNotesDetailViewModel.displayKey(for:)) ?? "no-selection"
	}
}

struct ReleaseNotesDetailSurface: View {
	let app: App?
	let contentState: ReleaseNotesDetailContentState
	var showsSupportStatus = true
	var updating: any AppUpdating = AppUpdateService.shared

	var body: some View {
		VStack(spacing: 0) {
			if let app {
				ReleaseNotesHeaderView(app: app, showsSupportStatus: showsSupportStatus, updating: updating)
			}
			content
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(.background)
	}

	@ViewBuilder
	private var content: some View {
		switch contentState {
		case .message(let message):
			ReleaseNotesMessageView(message: message)
		case .loading:
			ProgressView()
				.controlSize(.regular)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.accessibilityLabel("Loading Release Notes")
		case .text(let text):
			SelectableReleaseNotesTextView(text: text)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}
}

struct ReleaseNotesHeaderView: View {
	let app: App
	var showsSupportStatus = true
	var updating: any AppUpdating = AppUpdateService.shared
	@State private var icon: NSImage?

	var body: some View {
		HStack(spacing: 5) {
			Group {
				if let icon {
					Image(nsImage: icon)
						.resizable()
						.scaledToFit()
				} else {
					Color.clear
				}
			}
			.frame(width: VisualMetrics.detailIconSize, height: VisualMetrics.detailIconSize)
			.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 0) {
				appTitle
					.offset(y: VisualMetrics.detailTitleVerticalCorrection)
					.frame(height: 19)

				if let version = app.localizedVersionInformation?.combined(includeNew: app.updateAvailable) {
					Text(version)
						.font(.system(size: NSFont.systemFontSize(for: .small)))
						.foregroundStyle(Color(nsColor: .secondaryLabelColor))
						.offset(y: VisualMetrics.detailMetadataLineVerticalCorrection)
						.lineLimit(1)
				}

				if let date = app.latestUpdateDate {
					Text(date, format: .dateTime.year().month(.wide).day())
						.font(.system(size: NSFont.systemFontSize(for: .small)))
						.foregroundStyle(Color(nsColor: .secondaryLabelColor))
						.offset(y: VisualMetrics.detailMetadataLineVerticalCorrection)
						.lineLimit(1)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.offset(y: VisualMetrics.detailMetadataVerticalOffset)
			.layoutPriority(1)

			UpdateActionView(app: app, updating: updating)
				.id(app.identifier)
		}
		.padding(.horizontal, VisualMetrics.detailHeaderHorizontalPadding)
		.frame(height: VisualMetrics.detailHeaderHeight)
		.background(.bar)
		.overlay(alignment: .bottom) {
			Divider()
		}
		.accessibilityElement(children: .contain)
		.accessibilityIdentifier("release-notes.header")
		.task(id: app.identifier) {
			let loadedIcon = await IconCache.shared.icon(for: app)
			guard !Task.isCancelled, app.identifier == self.app.identifier else { return }
			icon = loadedIcon
		}
	}

	@ViewBuilder
	private var appTitle: some View {
		if showsSupportStatus {
			ViewThatFits(in: .horizontal) {
				HStack(spacing: 8) {
					appName
						.fixedSize(horizontal: true, vertical: false)
					SupportStatusButton(app: app)
				}

				HStack(spacing: 5) {
					appName
					SupportStatusButton(app: app, showsLabel: false)
				}
			}
		} else {
			appName
		}
	}

	private var appName: some View {
		Text(app.name)
			.font(.system(size: 13, weight: .semibold))
			.lineLimit(1)
			.truncationMode(.tail)
	}
}

private struct ReleaseNotesMessageView: View {
	let message: ReleaseNotesMessage

	var body: some View {
		VStack(spacing: 8) {
			if let title = message.title, !title.isEmpty {
				Text(title)
					.font(.headline)
			}
			Text(message.description)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: 420)
		.padding(24)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.accessibilityElement(children: .combine)
		.accessibilityIdentifier("release-notes.message")
	}
}
