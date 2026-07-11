//
//  LocationsSettingsView.swift
//  Latest
//
//  Created by Codex on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

struct LocationsSettingsView: View {
	@ObservedObject var viewModel: SettingsViewModel
	@State private var showsDirectoryImporter = false

	var body: some View {
		Form {
			Section("Check apps from") {
				List(selection: $viewModel.selectedDirectory) {
					ForEach(viewModel.directoryURLs, id: \.self) { url in
						DirectoryLocationRow(
							url: url,
							isReachable: viewModel.isReachable(url)
						)
						.tag(url)
					}
				}
				.listStyle(.inset(alternatesRowBackgrounds: true))
				.frame(height: 190)

				ControlGroup {
					Button {
						showsDirectoryImporter = true
					} label: {
						Image(systemName: "plus")
					}
					.accessibilityLabel("Add Location")

					Button {
						viewModel.removeSelectedDirectory()
					} label: {
						Image(systemName: "minus")
					}
					.accessibilityLabel("Remove Location")
					.disabled(!viewModel.canRemove(viewModel.selectedDirectory))
				}
				.controlSize(.small)
			}
		}
		.formStyle(.grouped)
		.fileImporter(
			isPresented: $showsDirectoryImporter,
			allowedContentTypes: [.folder],
			allowsMultipleSelection: true
		) { result in
			guard case .success(let urls) = result else { return }
			viewModel.addDirectories(urls)
		}
	}
}

private struct DirectoryLocationRow: View {
	let url: URL
	let isReachable: Bool

	@State private var appCount: Int?

	var body: some View {
		HStack(spacing: 6) {
			Image(systemName: isReachable ? "folder.fill" : "exclamationmark.triangle")
				.foregroundStyle(isReachable ? Color.accentColor : Color.secondary)
				.frame(width: 16)

			Text(url.relativePath)
				.foregroundStyle(isReachable ? .primary : .secondary)
				.lineLimit(1)
				.truncationMode(.middle)

			Spacer()

			if let appCount {
				Text(appCount, format: .number)
					.foregroundStyle(.secondary)
					.monospacedDigit()
			} else {
				ProgressView()
					.controlSize(.small)
			}
		}
		.task(id: url) {
			appCount = await DirectoryAppCountCache.shared.count(for: url)
		}
	}
}

private actor DirectoryAppCountCache {
	static let shared = DirectoryAppCountCache()

	private struct Entry {
		let count: Int
		let expiresAt: Date
		var lastAccessedAt: Date
	}

	private var entries = [URL: Entry]()
	private var inFlightTasks = [URL: Task<Int, Never>]()
	private let lifetime: TimeInterval = 60
	private let maximumEntryCount = 64

	func count(for url: URL) async -> Int {
		let key = url.standardizedFileURL
		let now = Date()
		if var entry = entries[key], entry.expiresAt > now {
			entry.lastAccessedAt = now
			entries[key] = entry
			return entry.count
		}
		entries[key] = nil

		if let task = inFlightTasks[key] {
			return await task.value
		}

		let task = Task.detached(priority: .utility) {
			if let count = BundleCollector.cachedBundleCount(at: key) {
				return count
			}
			return BundleCollector.collectBundles(at: key).count
		}
		inFlightTasks[key] = task

		let count = await task.value
		let storedAt = Date()
		entries[key] = Entry(
			count: count,
			expiresAt: storedAt.addingTimeInterval(lifetime),
			lastAccessedAt: storedAt
		)
		while entries.count > maximumEntryCount {
			guard let leastRecentlyUsedKey = entries.min(by: {
				$0.value.lastAccessedAt < $1.value.lastAccessedAt
			})?.key else { break }
			entries[leastRecentlyUsedKey] = nil
		}
		inFlightTasks[key] = nil
		return count
	}
}
