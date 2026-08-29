//
//  MigrationGallery.swift
//  Latest
//
//  Created by Codex on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI
@testable import Latest

private typealias App = Latest.App

/// Deterministic fixtures used by the SwiftUI migration's rendered regression suite.
///
/// The gallery intentionally uses only local symbols and fixed text. Production views
/// can be moved into this composition as they are cut over without making screenshots
/// depend on the user's installed applications, network, locale, or update queue.
struct MigrationGalleryScenario: Identifiable {
		enum Surface {
			case main(DetailState)
		case locations
		case updateStateShelf
		case toolbarStateShelf
		case sidebar
	}

	enum DetailState {
		case releaseNotes
		case empty
		case loading
		case error
	}

	let id: String
	let surface: Surface
	let size: CGSize
	let colorScheme: ColorScheme
	let controlActiveState: ControlActiveState
	let tint: Color
	let contrast: ColorSchemeContrast
	let reduceTransparency: Bool
	let dynamicTypeSize: DynamicTypeSize
	let locale: Locale
	let layoutDirection: LayoutDirection

	init(
		_ id: String,
		surface: Surface,
		size: CGSize = MigrationGalleryMetrics.defaultWindowSize,
		colorScheme: ColorScheme = .light,
		controlActiveState: ControlActiveState = .active,
		tint: Color = .blue,
		contrast: ColorSchemeContrast = .standard,
		reduceTransparency: Bool = false,
		dynamicTypeSize: DynamicTypeSize = .large,
		locale: Locale = Locale(identifier: "en_US"),
		layoutDirection: LayoutDirection = .leftToRight
	) {
		self.id = id
		self.surface = surface
		self.size = size
		self.colorScheme = colorScheme
		self.controlActiveState = controlActiveState
		self.tint = tint
		self.contrast = contrast
		self.reduceTransparency = reduceTransparency
		self.dynamicTypeSize = dynamicTypeSize
		self.locale = locale
		self.layoutDirection = layoutDirection
	}

	static let regressionCases: [MigrationGalleryScenario] = [
		MigrationGalleryScenario("main-default-light", surface: .main(.releaseNotes)),
		MigrationGalleryScenario(
			"main-minimum-dark-empty",
			surface: .main(.empty),
			size: MigrationGalleryMetrics.minimumWindowSize,
			colorScheme: .dark,
			tint: .green
		),
		MigrationGalleryScenario(
			"main-inactive-graphite",
			surface: .main(.releaseNotes),
			controlActiveState: .inactive,
			tint: .gray
		),
		MigrationGalleryScenario(
			"main-increased-contrast-orange",
			surface: .main(.releaseNotes),
			colorScheme: .dark,
			tint: .orange,
			contrast: .increased
		),
		MigrationGalleryScenario(
			"main-reduce-transparency-purple",
			surface: .main(.loading),
			tint: .purple,
			reduceTransparency: true
		),
		MigrationGalleryScenario(
			"main-large-text-error",
			surface: .main(.error),
			dynamicTypeSize: .accessibility1
		),
		MigrationGalleryScenario(
			"main-rtl-long-localization",
			surface: .main(.releaseNotes),
			locale: Locale(identifier: "ar"),
			layoutDirection: .rightToLeft
		),
		MigrationGalleryScenario("locations-light", surface: .locations),
		MigrationGalleryScenario(
			"locations-dark-inactive",
			surface: .locations,
			colorScheme: .dark,
			controlActiveState: .inactive,
			tint: .pink
		),
		MigrationGalleryScenario(
			"locations-contrast-large-rtl",
			surface: .locations,
			contrast: .increased,
			dynamicTypeSize: .accessibility1,
			locale: Locale(identifier: "ar"),
			layoutDirection: .rightToLeft
		),
		MigrationGalleryScenario("update-state-shelf-light", surface: .updateStateShelf),
		MigrationGalleryScenario(
			"update-state-shelf-dark",
			surface: .updateStateShelf,
			colorScheme: .dark,
			tint: .orange
		),
		MigrationGalleryScenario(
			"toolbar-state-shelf-light",
			surface: .toolbarStateShelf,
			size: MigrationGalleryMetrics.minimumWindowSize
		),
		MigrationGalleryScenario(
			"toolbar-state-shelf-dark",
			surface: .toolbarStateShelf,
			size: MigrationGalleryMetrics.minimumWindowSize,
			colorScheme: .dark,
			tint: .orange
		)
	]
}

enum MigrationGalleryMetrics {
	static let defaultWindowSize = CGSize(width: 768, height: 516)
	static let minimumWindowSize = CGSize(width: 560, height: 360)
	static let sidebarWidth: CGFloat = 308
	static let detailHeaderHeight: CGFloat = 79
	static let locationsContentSize = CGSize(width: 440, height: 296)
	static let locationsTableSize = CGSize(width: 400, height: 200)
	static let sidebarFixtureSize = CGSize(width: sidebarWidth, height: 420)
	static let appRowHeight: CGFloat = 60

	static func sidebarFrame(in size: CGSize) -> CGRect {
		CGRect(x: 0, y: 0, width: min(sidebarWidth, size.width), height: size.height)
	}

	static func detailFrame(in size: CGSize) -> CGRect {
		let sidebarWidth = min(self.sidebarWidth, size.width)
		return CGRect(x: sidebarWidth, y: 0, width: max(0, size.width - sidebarWidth), height: size.height)
	}
}

struct MigrationGalleryView: View {
	let scenario: MigrationGalleryScenario

	var body: some View {
		content
			.frame(width: scenario.size.width, height: scenario.size.height)
			.environment(\.colorScheme, scenario.colorScheme)
			.environment(\.controlActiveState, scenario.controlActiveState)
			.environment(\.dynamicTypeSize, scenario.dynamicTypeSize)
			.environment(\.locale, scenario.locale)
			.environment(\.layoutDirection, scenario.layoutDirection)
			.tint(scenario.tint)
			.contrast(scenario.contrast == .increased ? 1.18 : 1)
			.background {
				if scenario.reduceTransparency {
					Color(nsColor: .windowBackgroundColor)
				}
			}
	}

	@ViewBuilder
	private var content: some View {
		switch scenario.surface {
		case .main(let state):
			MigrationMainWindowFixture(detailState: state)
		case .locations:
			MigrationLocationsFixture()
		case .updateStateShelf:
			MigrationUpdateStateShelf()
		case .toolbarStateShelf:
			MigrationToolbarStateShelf()
		case .sidebar:
			MigrationSidebarFixture()
		}
	}
}

private struct MigrationMainWindowFixture: View {
	let detailState: MigrationGalleryScenario.DetailState
	@State private var selection: String? = MigrationAppFixture.cursor.id
	@State private var searchText = ""

	var body: some View {
		HStack(spacing: 0) {
			VStack(spacing: 0) {
				TextField("Search Apps", text: $searchText)
					.textFieldStyle(.roundedBorder)
					.padding(.horizontal, 20)
					.frame(height: 39)

				List(selection: $selection) {
					Section("Available Updates (2)") {
						MigrationSidebarRow(app: .discord)
						MigrationSidebarRow(app: .telegram)
					}
					Section("Installed Apps (3)") {
						MigrationSidebarRow(app: .cursor)
						MigrationSidebarRow(app: .browser)
						MigrationSidebarRow(app: .notes)
					}
				}
				.listStyle(.sidebar)
			}
			.frame(width: MigrationGalleryMetrics.sidebarWidth)
			.background(.ultraThinMaterial)

			Divider()

			MigrationDetailFixture(state: detailState)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.background(.background)
	}
}

private struct MigrationAppFixture: Identifiable {
	let id: String
	let name: String
	let version: String
	let date: String
	let symbol: String
	let color: Color
	let updateAvailable: Bool

	static let discord = MigrationAppFixture(
		id: "com.example.discord",
		name: "Discord",
		version: "0.0.400 -> 0.0.401",
		date: "Today",
		symbol: "bubble.left.and.bubble.right.fill",
		color: .indigo,
		updateAvailable: true
	)
	static let telegram = MigrationAppFixture(
		id: "com.example.telegram",
		name: "Telegram",
		version: "7.0.1 -> 7.0.3",
		date: "Yesterday",
		symbol: "paperplane.fill",
		color: .cyan,
		updateAvailable: true
	)
	static let cursor = MigrationAppFixture(
		id: "com.example.cursor",
		name: "Cursor",
		version: "Version 3.12.17",
		date: "Today",
		symbol: "cursorarrow.rays",
		color: .black,
		updateAvailable: false
	)
	static let browser = MigrationAppFixture(
		id: "com.example.browser",
		name: "A Browser with a Deliberately Long Localized Name",
		version: "Version 150.0.7871.129",
		date: "Jul 18",
		symbol: "globe",
		color: .blue,
		updateAvailable: false
	)
	static let notes = MigrationAppFixture(
		id: "com.example.notes",
		name: "Notes",
		version: "Version 26.5",
		date: "Jul 17",
		symbol: "note.text",
		color: .yellow,
		updateAvailable: false
	)
}

private struct MigrationSidebarRow: View {
	let app: MigrationAppFixture

	var body: some View {
		HStack(spacing: 8) {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.fill(app.color.gradient)
				.overlay {
					Image(systemName: app.symbol)
						.font(.title2)
						.foregroundStyle(app.color == .yellow ? .black : .white)
				}
				.frame(width: 50, height: 50)

			VStack(alignment: .leading, spacing: 2) {
				Text(app.name)
					.font(.system(size: 13, weight: .semibold))
					.lineLimit(1)
				Text(app.version)
					.font(.system(size: 11))
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}

			Spacer(minLength: 4)

			VStack(alignment: .trailing, spacing: 5) {
				Text(app.date)
					.font(.callout)
					.foregroundStyle(.secondary)
				Image(systemName: app.updateAvailable ? "arrow.down.circle.fill" : "checkmark.circle.fill")
					.foregroundStyle(app.updateAvailable ? .cyan : .secondary)
			}
		}
		.frame(height: MigrationGalleryMetrics.appRowHeight)
		.tag(app.id)
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(app.name), \(app.version), \(app.date)")
	}
}

private struct MigrationDetailFixture: View {
	let state: MigrationGalleryScenario.DetailState

	var body: some View {
		ReleaseNotesDetailSurface(app: fixtureApp, contentState: contentState)
	}

	private var contentState: ReleaseNotesDetailContentState {
		switch state {
		case .releaseNotes:
			return .text(fixtureReleaseNotes)
		case .empty:
			return .message(ReleaseNotesMessage(
				title: "No Release Notes",
				description: "Release notes are not available for this application."
			))
		case .loading:
			return .loading
		case .error:
			return .message(ReleaseNotesMessage(
				title: "Release Notes Unavailable",
				description: "The server response could not be rendered. Try checking for updates again."
			))
		}
	}

	private var fixtureApp: App {
		let bundle = App.Bundle(
			version: Version(versionNumber: "3.12.17", buildNumber: nil),
			name: "Cursor",
			bundleIdentifier: "com.example.cursor",
			fileURL: URL(fileURLWithPath: "/Applications/Cursor Migration Fixture.app", isDirectory: true),
			source: .homebrew
		)
		return App(bundle: bundle, update: nil, isIgnored: false)
	}

	private var fixtureReleaseNotes: NSAttributedString {
		let text = NSMutableAttributedString(string: "Improvements to Cursor\n\n")
		text.addAttribute(
			.font,
			value: NSFont.systemFont(ofSize: 20, weight: .semibold),
			range: NSRange(location: 0, length: 22)
		)
		text.append(NSAttributedString(
			string: "Cursor now shares a plan before it starts, preserves context across repositories, and reports progress with clearer status updates.\n\n"
		))
		text.append(NSAttributedString(
			string: "Interaction improvements\n",
			attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
		))
		text.append(NSAttributedString(
			string: "Links remain selectable, keyboard copy continues to work, and paragraph spacing stays stable for long release notes.\n\n"
		))
		text.append(NSAttributedString(
			string: "Read the full changelog",
			attributes: [.link: URL(string: "https://example.com/changelog")!]
		))
		return text
	}
}

private struct MigrationLocationsFixture: View {
	private static let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
	private static let utilitiesURL = URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true)
	private static let archiveURL = URL(fileURLWithPath: "/Volumes/Archived Applications", isDirectory: true)
	private static let urls = [applicationsURL, utilitiesURL, archiveURL]

	@State private var selection: URL? = applicationsURL

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Check apps from:")

			DirectoryLocationsTable(
				urls: Self.urls,
				selection: $selection,
				loadDetails: Self.loadDetails
			)
			.frame(
				width: MigrationGalleryMetrics.locationsTableSize.width,
				height: MigrationGalleryMetrics.locationsTableSize.height
			)

			ControlGroup {
				Button("Add Location", systemImage: "plus") {}
					.labelStyle(.iconOnly)
				Button("Remove Location", systemImage: "minus") {}
					.labelStyle(.iconOnly)
			}
			.controlSize(.small)
			.fixedSize()
		}
		.padding(.horizontal, 20)
		.padding(.top, 19)
		.frame(
			width: MigrationGalleryMetrics.locationsContentSize.width,
			height: MigrationGalleryMetrics.locationsContentSize.height,
			alignment: .topLeading
		)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(.background)
	}

	private static func loadDetails(for url: URL) async -> DirectoryLocationDetails {
		switch url {
		case utilitiesURL:
			try? await Task.sleep(for: .seconds(30))
			return DirectoryLocationDetails(isReachable: true, appCount: 12)
		case archiveURL:
			return DirectoryLocationDetails(isReachable: false, appCount: 0)
		default:
			return DirectoryLocationDetails(isReachable: true, appCount: 38)
		}
	}
}

@MainActor
private enum MigrationUpdateFixtureState: String, CaseIterable, Identifiable {
	case ready = "Ready to Update"
	case open = "Up to Date / Open"
	case pending = "Pending"
	case initializing = "Initializing"
	case downloading = "Downloading 42%"
	case extracting = "Extracting 50%"
	case installing = "Installing"
	case cancelling = "Cancelling"
	case failed = "Failed"
	case external = "External Updater"

	var id: String { rawValue }

	var fixture: (app: App, presentation: UpdateActionPresentation) {
		let app: App
		let progressState: UpdateOperation.ProgressState
		switch self {
		case .ready:
			app = Self.makeApp(remoteVersion: "2.0", action: .builtIn { _ in })
			progressState = .none
		case .open:
			app = Self.makeApp(remoteVersion: "1.0", action: .builtIn { _ in })
			progressState = .none
		case .pending:
			app = Self.makeApp(remoteVersion: "2.0", action: .builtIn { _ in })
			progressState = .pending
		case .initializing:
			app = Self.makeApp(remoteVersion: "2.0", action: .builtIn { _ in })
			progressState = .initializing
		case .downloading:
			app = Self.makeApp(remoteVersion: "2.0", action: .builtIn { _ in })
			progressState = .downloading(loadedSize: 42, totalSize: 100)
		case .extracting:
			app = Self.makeApp(remoteVersion: "2.0", action: .builtIn { _ in })
			progressState = .extracting(progress: 0.5)
		case .installing:
			app = Self.makeApp(remoteVersion: "2.0", action: .builtIn { _ in })
			progressState = .installing
		case .cancelling:
			app = Self.makeApp(remoteVersion: "2.0", action: .builtIn { _ in })
			progressState = .cancelling
		case .failed:
			app = Self.makeApp(remoteVersion: "2.0", action: .builtIn { _ in })
			progressState = .error(LatestError.updateInfoUnavailable)
		case .external:
			app = Self.makeApp(remoteVersion: "2.0", action: .external(label: "Zed") { _ in })
			progressState = .none
		}
		return (app, UpdateActionPresentation.make(for: app, progressState: progressState))
	}

	private static func makeApp(remoteVersion: String, action: App.Update.Action) -> App {
		let bundle = App.Bundle(
			version: Version(versionNumber: "1.0", buildNumber: nil),
			name: "Fixture",
			bundleIdentifier: "com.example.update-action-fixture",
			fileURL: URL(fileURLWithPath: "/Applications/Update Action Fixture.app"),
			source: .appStore
		)
		let update = App.Update(
			app: bundle,
			remoteVersion: Version(versionNumber: remoteVersion, buildNumber: nil),
			minimumOSVersion: nil,
			source: .appStore,
			date: Date(timeIntervalSince1970: 1_750_000_000),
			releaseNotes: .html(string: "<p>Release notes</p>"),
			updateAction: action
		)
		return App(bundle: bundle, update: .success(update), isIgnored: false)
	}
}

private struct MigrationUpdateStateShelf: View {
	private let columns = [
		GridItem(.flexible(), spacing: 20, alignment: .leading),
		GridItem(.flexible(), alignment: .leading)
	]

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Update Action States")
				.font(.title2.weight(.semibold))
			Text("Every state is rendered together so state-model changes cannot silently drop a label, progress indicator, or disabled treatment.")
				.foregroundStyle(.secondary)

			LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
				ForEach(MigrationUpdateFixtureState.allCases) { state in
					HStack(spacing: 8) {
						Text(state.rawValue)
							.frame(width: 142, alignment: .leading)
						MigrationUpdateActionFixture(state: state)
					}
					.frame(maxWidth: .infinity, minHeight: VisualMetrics.detailIconSize, alignment: .leading)
				}
			}
			Spacer()
		}
		.padding(20)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.background(.background)
	}
}

private struct MigrationUpdateActionFixture: View {
	let state: MigrationUpdateFixtureState

	var body: some View {
		let fixture = state.fixture
		UpdateActionSurface(
			app: fixture.app,
			presentation: fixture.presentation,
			pausesAnimations: true,
			performAction: {}
		)
	}
}

private struct MigrationToolbarStateShelf: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			Text("Main Window Toolbar")
				.font(.title2.weight(.semibold))
			Text("The system owns sidebar toggling and Liquid Glass. Latest contributes only a refresh action and scan progress.")
				.foregroundStyle(.secondary)

			toolbarRow("Ready", isRefreshEnabled: true, progress: .hidden)
			toolbarRow("Scanning", isRefreshEnabled: false, progress: .indeterminate)
			toolbarRow("Checking 42%", isRefreshEnabled: false, progress: .determinate(0.42))
			Spacer()
		}
		.padding(20)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.background(.background)
	}

	private func toolbarRow(
		_ label: String,
		isRefreshEnabled: Bool,
		progress: ToolbarProgressPresentation
	) -> some View {
		HStack(spacing: 0) {
			Text(label)
				.frame(width: 120, alignment: .leading)
			HStack(spacing: 10) {
				RefreshToolbarButton(isEnabled: isRefreshEnabled) {}
				ToolbarUpdateProgressView(presentation: progress)
			}
			.padding(.horizontal, 10)
			.frame(width: 210, height: 42, alignment: .leading)
			.background(.bar, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
		}
	}
}

@MainActor
private struct MigrationSidebarFixture: View {
	@StateObject private var viewModel: UpdatesListViewModel

	init() {
		let apps = Self.makeApps()
		let viewModel = UpdatesListViewModel(snapshot: AppListSnapshot(withApps: apps, filterQuery: nil))
		viewModel.select(apps.first)
		_viewModel = StateObject(wrappedValue: viewModel)
	}

	var body: some View {
		ZStack {
			Color(nsColor: .windowBackgroundColor)
			NativeUpdatesList(
				viewModel: viewModel,
				showsSupportStatusOverride: true
			)
		}
	}

	private static func makeApps() -> [App] {
		[
			makeApp(
				name: "Notes",
				path: "/System/Applications/Notes.app",
				currentVersion: "26.4",
				remoteVersion: "26.5",
				date: Date(timeIntervalSince1970: 1_753_000_000)
			),
			makeApp(
				name: "Terminal",
				path: "/System/Applications/Utilities/Terminal.app",
				currentVersion: "2.14",
				remoteVersion: "2.15",
				date: Date(timeIntervalSince1970: 1_752_000_000)
			),
			makeApp(
				name: "TextEdit",
				path: "/System/Applications/TextEdit.app",
				currentVersion: "1.19",
				remoteVersion: "1.20",
				date: Date(timeIntervalSince1970: 1_751_000_000)
			)
		]
	}

	private static func makeApp(
		name: String,
		path: String,
		currentVersion: String,
		remoteVersion: String,
		date: Date
	) -> App {
		let bundle = App.Bundle(
			version: Version(versionNumber: currentVersion, buildNumber: nil),
			name: name,
			bundleIdentifier: "com.example.migration.\(name)",
			fileURL: URL(fileURLWithPath: path, isDirectory: true),
			source: .appStore
		)
		let update = App.Update(
			app: bundle,
			remoteVersion: Version(versionNumber: remoteVersion, buildNumber: nil),
			minimumOSVersion: nil,
			source: .appStore,
			date: date,
			releaseNotes: nil,
			updateAction: .builtIn { _ in }
		)
		return App(bundle: bundle, update: .success(update), isIgnored: false)
	}
}
