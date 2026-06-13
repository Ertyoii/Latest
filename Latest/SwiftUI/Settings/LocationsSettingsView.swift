//
//  LocationsSettingsView.swift
//  Latest
//
//  Created by Codex on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

struct LocationsSettingsView: View {
	@ObservedObject var viewModel: SettingsViewModel
	@State private var window: NSWindow?

	var body: some View {
		ZStack(alignment: .topLeading) {
			Text("Check apps from:")
				.font(.system(size: NSFont.systemFontSize))
				.frame(width: 404, height: 16, alignment: .leading)
				.offset(x: 18, y: 20)

			DirectoryLocationsTableRepresentable(viewModel: viewModel)
				.frame(width: 400, height: 200)
				.offset(x: 20, y: 44)

			DirectoryActionControlRepresentable(
				canRemove: viewModel.canRemove(viewModel.selectedDirectory),
				onAdd: { viewModel.addDirectory(attachedTo: window) },
				onRemove: { viewModel.removeSelectedDirectory() }
			)
			.frame(width: 61, height: 24)
			.offset(x: 20, y: 252)
		}
		.frame(width: 440, height: 296, alignment: .topLeading)
		.background(WindowAccessor { window = $0 })
	}
}

private struct DirectoryActionControlRepresentable: NSViewRepresentable {
	let canRemove: Bool
	let onAdd: () -> Void
	let onRemove: () -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(onAdd: onAdd, onRemove: onRemove)
	}

	func makeNSView(context: Context) -> NSSegmentedControl {
		let control = NSSegmentedControl(
			images: [
				NSImage(named: NSImage.addTemplateName) ?? NSImage(),
				NSImage(named: NSImage.removeTemplateName) ?? NSImage()
			],
			trackingMode: .momentary,
			target: context.coordinator,
			action: #selector(Coordinator.performAction(_:))
		)
		control.segmentStyle = .rounded
		control.setWidth(30, forSegment: 0)
		control.setWidth(30, forSegment: 1)
		return control
	}

	func updateNSView(_ control: NSSegmentedControl, context: Context) {
		context.coordinator.onAdd = onAdd
		context.coordinator.onRemove = onRemove
		control.setEnabled(canRemove, forSegment: 1)
	}

	final class Coordinator: NSObject {
		var onAdd: () -> Void
		var onRemove: () -> Void

		init(onAdd: @escaping () -> Void, onRemove: @escaping () -> Void) {
			self.onAdd = onAdd
			self.onRemove = onRemove
		}

		@MainActor
		@objc func performAction(_ sender: NSSegmentedControl) {
			switch sender.selectedSegment {
			case 0:
				onAdd()
			case 1:
				onRemove()
			default:
				break
			}
		}
	}
}

private struct DirectoryLocationsTableRepresentable: NSViewRepresentable {
	@ObservedObject var viewModel: SettingsViewModel

	func makeCoordinator() -> Coordinator {
		Coordinator(viewModel: viewModel)
	}

	func makeNSView(context: Context) -> NSScrollView {
		let tableView = NSTableView()
		tableView.delegate = context.coordinator
		tableView.dataSource = context.coordinator
		tableView.headerView = nil
		tableView.allowsExpansionToolTips = true
		tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
		tableView.usesAlternatingRowBackgroundColors = true
		tableView.allowsColumnReordering = false
		tableView.allowsColumnResizing = false
		tableView.allowsMultipleSelection = false
		tableView.rowHeight = 24
		tableView.intercellSpacing = NSSize(width: 17, height: 0)
		tableView.backgroundColor = .controlBackgroundColor

		let column = NSTableColumn(identifier: .directoryCell)
		column.width = 386
		column.minWidth = 40
		column.maxWidth = 1000
		column.resizingMask = .autoresizingMask
		tableView.addTableColumn(column)

		let scrollView = NSScrollView()
		scrollView.borderType = .lineBorder
		scrollView.autohidesScrollers = true
		scrollView.hasHorizontalScroller = false
		scrollView.hasVerticalScroller = true
		scrollView.usesPredominantAxisScrolling = false
		scrollView.horizontalScrollElasticity = .none
		scrollView.documentView = tableView

		context.coordinator.tableView = tableView
		context.coordinator.apply(viewModel)
		return scrollView
	}

	func updateNSView(_ scrollView: NSScrollView, context: Context) {
		context.coordinator.apply(viewModel)
		guard let tableView = context.coordinator.tableView else { return }
		if let column = tableView.tableColumns.first {
			column.width = max(40, scrollView.contentSize.width - 12)
		}
	}

	@MainActor
	final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
		weak var tableView: NSTableView?
		private var viewModel: SettingsViewModel
		private var urls: [URL] = []

		init(viewModel: SettingsViewModel) {
			self.viewModel = viewModel
		}

		func apply(_ viewModel: SettingsViewModel) {
			self.viewModel = viewModel
			guard urls != viewModel.directoryURLs else {
				syncSelection()
				return
			}

			urls = viewModel.directoryURLs
			tableView?.reloadData()
			syncSelection()
		}

		func numberOfRows(in tableView: NSTableView) -> Int {
			urls.count
		}

		func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
			guard row >= 0, row < urls.count else { return nil }
			let identifier = NSUserInterfaceItemIdentifier.directoryCell
			let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? DirectoryLocationCellView
				?? DirectoryLocationCellView()
			cell.identifier = identifier
			cell.url = urls[row]
			return cell
		}

		func tableViewSelectionDidChange(_ notification: Notification) {
			guard let tableView = notification.object as? NSTableView else { return }
			let row = tableView.selectedRow
			viewModel.selectedDirectory = row >= 0 && row < urls.count ? urls[row] : nil
		}

		private func syncSelection() {
			guard let tableView else { return }
			guard let selectedDirectory = viewModel.selectedDirectory, let row = urls.firstIndex(of: selectedDirectory) else {
				tableView.deselectAll(nil)
				return
			}
			if tableView.selectedRow != row {
				tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			}
		}
	}
}

private final class DirectoryLocationCellView: NSTableCellView {
	private let iconImageView = NSImageView()
	private let titleLabel = NSTextField(labelWithString: "")
	private let activityIndicator = NSProgressIndicator()
	private let appCountLabel = NSTextField(labelWithString: "")
	private var appCountTask: Task<Void, Never>?

	var url: URL? {
		didSet {
			guard url != oldValue else { return }
			appCountTask?.cancel()
			setupContent()
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setupView()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupView()
	}

	deinit {
		appCountTask?.cancel()
	}

	private func setupView() {
		iconImageView.imageScaling = .scaleProportionallyDown
		iconImageView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(iconImageView)
		imageView = iconImageView

		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(titleLabel)

		activityIndicator.controlSize = .small
		activityIndicator.style = .spinning
		activityIndicator.isDisplayedWhenStopped = false
		activityIndicator.translatesAutoresizingMaskIntoConstraints = false
		addSubview(activityIndicator)

		appCountLabel.textColor = .secondaryLabelColor
		appCountLabel.alignment = .right
		appCountLabel.lineBreakMode = .byClipping
		appCountLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(appCountLabel)

		NSLayoutConstraint.activate([
			iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
			iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconImageView.widthAnchor.constraint(equalToConstant: 16),
			iconImageView.heightAnchor.constraint(equalToConstant: 16),

			titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 6),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

			activityIndicator.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
			activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
			activityIndicator.widthAnchor.constraint(equalToConstant: 16),
			activityIndicator.heightAnchor.constraint(equalToConstant: 16),

			appCountLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
			appCountLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
			appCountLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			appCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 24)
		])
	}

	private func setupContent() {
		guard let url else {
			titleLabel.stringValue = ""
			iconImageView.image = nil
			appCountLabel.isHidden = true
			activityIndicator.stopAnimation(nil)
			return
		}

		let isReachable = (try? url.checkResourceIsReachable()) == true
		titleLabel.stringValue = url.relativePath
		titleLabel.textColor = isReachable ? .labelColor : .secondaryLabelColor
		iconImageView.image = if isReachable {
			NSWorkspace.shared.icon(forFile: url.relativePath)
		} else {
			NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "")
		}

		appCountLabel.isHidden = true
		activityIndicator.startAnimation(nil)
		appCountTask = Task {
			let count = await DirectoryAppCountCache.shared.count(for: url)

			guard !Task.isCancelled, self.url == url else { return }
			self.appCountLabel.stringValue = NumberFormatter.localizedString(from: NSNumber(value: count), number: .none)
			self.appCountLabel.isHidden = false
			self.activityIndicator.stopAnimation(nil)
		}
	}
}

private extension NSUserInterfaceItemIdentifier {
	static let directoryCell = NSUserInterfaceItemIdentifier("directoryCellView")
}

private actor DirectoryAppCountCache {
	static let shared = DirectoryAppCountCache()

	private struct Entry {
		let count: Int
		let expiresAt: Date
	}

	private var entries = [URL: Entry]()
	private var inFlightTasks = [URL: Task<Int, Never>]()
	private let lifetime: TimeInterval = 60

	func count(for url: URL) async -> Int {
		let key = url.standardizedFileURL
		let now = Date()
		if let entry = entries[key], entry.expiresAt > now {
			return entry.count
		}

		if let task = inFlightTasks[key] {
			return await task.value
		}

		let task = Task.detached(priority: .utility) {
			BundleCollector.collectBundles(at: key).count
		}
		inFlightTasks[key] = task

		let count = await task.value
		entries[key] = Entry(count: count, expiresAt: Date().addingTimeInterval(lifetime))
		inFlightTasks[key] = nil
		return count
	}
}
