//
//  NativeUpdatesSidebarView.swift
//  Latest
//
//  Created by Codex on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Combine
import SwiftUI

/// The native sidebar candidate. SwiftUI owns selection, sections, keyboard
/// movement, context menus, and swipe actions; no view-hierarchy inspection or
/// responder interception is used here.
struct NativeUpdatesList: View {
	@ObservedObject var viewModel: UpdatesListViewModel
	let showsSupportStatusOverride: Bool?
	@State private var listSelection: App.Bundle.Identifier?

	init(viewModel: UpdatesListViewModel, showsSupportStatusOverride: Bool? = nil) {
		self.viewModel = viewModel
		self.showsSupportStatusOverride = showsSupportStatusOverride
		_listSelection = State(initialValue: viewModel.selectedApp?.identifier)
	}

	var body: some View {
		List(selection: $listSelection) {
			ForEach(viewModel.snapshot.sections) { content in
				Section {
					ForEach(content.apps, id: \.identifier) { app in
						NativeUpdateRow(
							app: app,
							filterQuery: viewModel.snapshot.filterQuery,
							isSelected: viewModel.selectedApp?.identifier == app.identifier,
							showsSupportStatusOverride: showsSupportStatusOverride
						)
						.tag(app.identifier)
						.listRowInsets(EdgeInsets())
						.listRowSeparator(.hidden)
						.contextMenu { contextMenu(for: app) }
						.swipeActions(edge: .leading, allowsFullSwipe: false) {
							Button {
								viewModel.open(app)
							} label: {
								Label(
									NSLocalizedString("OpenAction", comment: "Action to open a given app."),
									systemImage: "arrow.up.forward.app"
								)
							}

							Button {
								viewModel.revealInFinder(app)
							} label: {
								Label(
									NSLocalizedString("RevealAction", comment: "Reveal in Finder Row action"),
									systemImage: "finder"
								)
							}
							.tint(.gray)
						}
						.swipeActions(edge: .trailing, allowsFullSwipe: false) {
							if app.updateAvailable && !app.isUpdating {
								Button {
									viewModel.update(app)
								} label: {
									Label(updateTitle(for: app), systemImage: "square.and.arrow.down")
								}
								.tint(.cyan)
							}
						}
					}
				} header: {
					NativeUpdateSectionHeader(section: content.section)
				}
			}
		}
		.listStyle(.sidebar)
		.scrollContentBackground(.hidden)
		.contentMargins(.top, 0, for: .scrollContent)
		.onScrollPhaseChange { oldPhase, newPhase in
			if !oldPhase.isScrolling && newPhase.isScrolling {
				MigrationTelemetry.shared.beginSidebarScroll()
			} else if oldPhase.isScrolling && !newPhase.isScrolling {
				MigrationTelemetry.shared.endSidebarScroll()
			}
		}
		.transaction { transaction in
			transaction.animation = nil
			transaction.disablesAnimations = true
		}
		.task(id: listSelection) {
			viewModel.select(identifier: listSelection)
		}
		.onChange(of: viewModel.selectedApp?.identifier) { _, identifier in
			guard identifier != listSelection else { return }
			listSelection = identifier
		}
		.accessibilityIdentifier("updates.sidebar.native")
	}

	@ViewBuilder
	private func contextMenu(for app: App) -> some View {
		if app.updateAvailable && !app.isUpdating {
			Button {
				viewModel.update(app)
			} label: {
				Label(updateTitle(for: app), systemImage: "square.and.arrow.down")
			}
		}

		Button {
			viewModel.setIgnored(!app.isIgnored, for: app)
		} label: {
			if app.isIgnored {
				Label(
					NSLocalizedString("UnignoreAction", value: "Don't Ignore", comment: "Action to stop ignoring a given app."),
					image: "custom.app.dashed.slash"
				)
			} else {
				Label(
					NSLocalizedString("IgnoreAction", value: "Ignore", comment: "Action to ignore a given app."),
					systemImage: "app.dashed"
				)
			}
		}

		Divider()

		Button {
			viewModel.open(app)
		} label: {
			Label(
				NSLocalizedString("OpenAction", comment: "Action to open a given app."),
				systemImage: "arrow.up.forward.app"
			)
		}

		Button {
			viewModel.revealInFinder(app)
		} label: {
			Label(
				NSLocalizedString("RevealAction", comment: "Reveal in Finder Row action"),
				systemImage: "finder"
			)
		}
	}

	private func updateTitle(for app: App) -> String {
		if let externalUpdater = app.externalUpdaterName {
			return String(
				format: NSLocalizedString(
					"ExternalUpdateAction",
					comment: "Action to update a given app outside of Latest."
				),
				externalUpdater
			)
		}
		return NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
	}
}

private struct NativeUpdateSectionHeader: View {
	let section: AppListSnapshot.Section

	var body: some View {
		Text(SidebarSectionPresentation.attributedTitle(for: section))
			.lineLimit(1)
			.frame(maxWidth: .infinity, minHeight: VisualMetrics.sectionHeaderHeight, alignment: .leading)
			.padding(.leading, 14)
			.padding(.trailing, 30)
			.accessibilityLabel(SidebarSectionPresentation.accessibilityLabel(for: section))
	}
}

@MainActor
enum SidebarSectionPresentation {
	private static let numberFormatter = NumberFormatter()

	static func attributedTitle(for section: AppListSnapshot.Section) -> AttributedString {
		let count = numberFormatter.string(from: section.numberOfApps as NSNumber) ?? "0"
		let format = NSLocalizedString(
			"SectionTitle",
			comment: "Section name followed by a deemphasized app count"
		)
		let source = String(format: format, section.title, count)
		let plain = source.replacingOccurrences(of: "<u>", with: "").replacingOccurrences(of: "</u>", with: "")
		var title = AttributedString(plain)
		title.font = .system(size: 13, weight: .medium)
		title.foregroundColor = .secondary
		if let countRange = plain.range(of: count),
		   let attributedRange = Range(countRange, in: title) {
			title[attributedRange].font = .system(size: NSFont.systemFontSize(for: .small), weight: .bold)
			title[attributedRange].foregroundColor = Color(nsColor: .tertiaryLabelColor)
		}
		return title
	}

	static func accessibilityLabel(for section: AppListSnapshot.Section) -> String {
		String.localizedStringWithFormat("%@, %lld", section.title, section.numberOfApps)
	}
}

private struct NativeUpdateRow: View {
	let app: App
	let filterQuery: String?
	let isSelected: Bool
	let showsSupportStatusOverride: Bool?

	@State private var icon: NSImage?
	@StateObject private var updateState: SidebarUpdateStateObserver

	init(app: App, filterQuery: String?, isSelected: Bool, showsSupportStatusOverride: Bool?) {
		self.app = app
		self.filterQuery = filterQuery
		self.isSelected = isSelected
		self.showsSupportStatusOverride = showsSupportStatusOverride
		_updateState = StateObject(wrappedValue: SidebarUpdateStateObserver(identifier: app.identifier))
	}

	var body: some View {
		HStack(spacing: 8) {
			Group {
				if let icon {
					Image(nsImage: icon)
						.resizable()
						.scaledToFit()
				} else {
					Color.clear
				}
			}
			.frame(width: VisualMetrics.appIconSize, height: VisualMetrics.appIconSize)
			.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 0) {
				NativeHighlightedAppName(name: app.name, query: filterQuery)

				if let version = app.localizedVersionInformation {
					Text(version.current)
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
						.lineLimit(1)
					if app.updateAvailable, let newVersion = version.new {
						Text(newVersion)
							.font(.system(size: 11))
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.layoutPriority(1)

			VStack(alignment: .trailing, spacing: 4) {
				Text(Self.dateFormatter.string(from: app.updateDate))
					.font(.callout)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.frame(width: 59, alignment: .trailing)

				SidebarUpdateStatus(
					app: app,
					presentation: UpdateActionPresentation.make(
						for: app,
						progressState: updateState.state
					),
					showsSupportStatus: showsSupportStatusOverride
						?? (AppListSettings.shared.includeAppsWithLimitedSupport || AppListSettings.shared.includeUnsupportedApps)
				)
				.frame(width: 59, height: 18, alignment: .trailing)
			}
		}
		.padding(.leading, 10)
		.padding(.trailing, 32)
		.frame(height: VisualMetrics.appRowHeight)
		.contentShape(Rectangle())
		.overlay(alignment: .bottom) {
			if !isSelected {
				Divider()
					.padding(.leading, VisualMetrics.appIconSize + 18)
					.padding(.trailing, 32)
					.offset(y: -1.5)
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel(accessibilityLabel)
		.accessibilityIdentifier("updates.row.\(app.bundleIdentifier)")
		.task(id: app.identifier) {
			let loadedIcon = await IconCache.shared.icon(for: app)
			guard !Task.isCancelled, app.identifier == self.app.identifier else { return }
			icon = loadedIcon
		}
	}

	private var accessibilityLabel: String {
		var label = SidebarInteractionPolicy.accessibilityLabel(for: app, dateFormatter: Self.dateFormatter)
		switch UpdateActionPresentation.make(for: app, progressState: updateState.state) {
		case .waiting(let status), .progress(_, let status), .failed(let status):
			label += ", \(status)"
		case .update, .open:
			break
		}
		return label
	}

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.timeStyle = .none
		formatter.dateStyle = .short
		formatter.doesRelativeDateFormatting = true
		return formatter
	}()
}

private struct NativeHighlightedAppName: View {
	let name: String
	let query: String?

	var body: some View {
		Group {
			if let query,
			   !query.isEmpty,
			   let match = name.range(of: query, options: .caseInsensitive) {
				Text("\(Text(verbatim: String(name[..<match.lowerBound])).foregroundStyle(.tertiary))\(Text(verbatim: String(name[match])))\(Text(verbatim: String(name[match.upperBound...])).foregroundStyle(.tertiary))")
			} else {
				Text(verbatim: name)
			}
		}
		.font(.system(size: 13, weight: .semibold))
		.lineLimit(1)
		.truncationMode(.tail)
	}
}

@MainActor
private final class SidebarUpdateStateObserver: ObservableObject {
	@Published private(set) var state: UpdateOperation.ProgressState
	private var observationTask: Task<Void, Never>?

	init(identifier: App.Bundle.Identifier) {
		let feed = UpdateQueue.shared.stateChanges(for: identifier)
		_state = Published(initialValue: feed.current)
		observationTask = Task { [weak self] in
			guard let self else { return }
			for await state in feed.changes {
				guard !Task.isCancelled else { break }
				self.state = state
			}
		}
	}

	deinit {
		observationTask?.cancel()
	}
}
