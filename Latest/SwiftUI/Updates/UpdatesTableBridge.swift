//
//  UpdatesTableBridge.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

private enum AppKitTableGeometry {
	static let leadingOffset: CGFloat = 4
}

/// Keeps the selected application visually stable when focus moves between the
/// main and Settings windows. The source-list selection geometry remains
/// system-owned, but it always uses the neutral, unemphasized treatment.
@MainActor
final class StableSelectionTableRowView: NSTableRowView {
	override var isEmphasized: Bool {
		get { false }
		set { super.isEmphasized = false }
	}
}

/// Capability bridge retained because the native SwiftUI List candidate misses
/// the sidebar's population and scroll performance gates. SwiftUI still owns
/// feature state, search, and composition around this table renderer.
struct UpdatesTableBridge: NSViewRepresentable {
	@ObservedObject var viewModel: UpdatesListViewModel
	let showsSupportStatusOverride: Bool?

	func makeCoordinator() -> Coordinator {
		Coordinator(
			viewModel: viewModel,
			showsSupportStatusOverride: showsSupportStatusOverride
		)
	}

	func makeNSView(context: Context) -> NSScrollView {
		let tableView = SwiftUIUpdateTableView()
		tableView.delegate = context.coordinator
		tableView.dataSource = context.coordinator
		tableView.menu = context.coordinator.tableViewMenu
		tableView.onMouseDownRow = { [weak coordinator = context.coordinator] row in
			coordinator?.selectRow(at: row)
		}
		tableView.headerView = nil
		tableView.backgroundColor = .clear
		tableView.gridStyleMask = []
		tableView.rowHeight = VisualMetrics.appRowHeight
		tableView.usesAutomaticRowHeights = false
		tableView.intercellSpacing = .zero
		// The original table used the source-list selection treatment without
		// opting the whole table into source-list indentation. Applying `.sourceList`
		// here shifts every cell horizontally on macOS 26.
		tableView.selectionHighlightStyle = .sourceList
		tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		tableView.allowsColumnReordering = false
		tableView.allowsColumnResizing = false
		tableView.allowsMultipleSelection = false
		tableView.autoresizesSubviews = false
		tableView.autoresizingMask = [.width]

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("updates"))
		column.resizingMask = .autoresizingMask
		column.width = VisualMetrics.sidebarIdealWidth
		tableView.addTableColumn(column)

		let scrollView = LockedHorizontalScrollView()
		scrollView.contentView = LockedHorizontalClipView()
		scrollView.borderType = .noBorder
		scrollView.autohidesScrollers = true
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.horizontalScrollElasticity = .none
		scrollView.usesPredominantAxisScrolling = false
		scrollView.automaticallyAdjustsContentInsets = false
		scrollView.drawsBackground = false
		scrollView.contentView.drawsBackground = false
		scrollView.contentInsets = NSEdgeInsets(top: 33, left: 0, bottom: 0, right: 0)
		scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: VisualMetrics.scrollBottomInset, right: 0)
		scrollView.documentView = tableView

		context.coordinator.tableView = tableView
		context.coordinator.observeLiveScrolling(in: scrollView)
		context.coordinator.resizeColumn(in: scrollView)
		context.coordinator.apply(viewModel: viewModel)
		return scrollView
	}

	func updateNSView(_ scrollView: NSScrollView, context: Context) {
		context.coordinator.resizeColumn(in: scrollView)
		context.coordinator.scheduleApply(viewModel: viewModel)
	}

	@MainActor
	final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
		weak var tableView: NSTableView? {
			didSet { menuController.tableView = tableView }
		}
		private var viewModel: UpdatesListViewModel
		private var entries: [AppListSnapshot.Entry] = []
		private var filterQuery: String?
		private var selectedIdentifier: App.Bundle.Identifier?
		private var selectedRowIndex: Int?
		private var contentState: TableContentState?
		private var pendingUpdate: TableUpdate?
		private var isUpdateScheduled = false
		private var isSynchronizingSelection = false
		private let showsSupportStatusOverride: Bool?
		private let menuController: SidebarTableMenuController
		var tableViewMenu: NSMenu { menuController.menu }

		init(viewModel: UpdatesListViewModel, showsSupportStatusOverride: Bool?) {
			self.viewModel = viewModel
			self.showsSupportStatusOverride = showsSupportStatusOverride
			self.menuController = SidebarTableMenuController(viewModel: viewModel)
		}

		deinit {
			NotificationCenter.default.removeObserver(self)
		}

		func observeLiveScrolling(in scrollView: NSScrollView) {
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(liveScrollDidStart(_:)),
				name: NSScrollView.willStartLiveScrollNotification,
				object: scrollView
			)
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(liveScrollDidEnd(_:)),
				name: NSScrollView.didEndLiveScrollNotification,
				object: scrollView
			)
		}

		@objc private func liveScrollDidStart(_ notification: Notification) {
			MigrationTelemetry.shared.beginSidebarScroll()
		}

		@objc private func liveScrollDidEnd(_ notification: Notification) {
			MigrationTelemetry.shared.endSidebarScroll()
		}

		func apply(viewModel: UpdatesListViewModel) {
			apply(TableUpdate(viewModel: viewModel), viewModel: viewModel)
		}

		func scheduleApply(viewModel: UpdatesListViewModel) {
			self.viewModel = viewModel
			let update = TableUpdate(viewModel: viewModel)
			pendingUpdate = update

			guard !isUpdateScheduled else { return }
			isUpdateScheduled = true

			Task { @MainActor [weak self, weak viewModel] in
				guard let self, let viewModel else { return }
				self.applyPendingUpdate(viewModel: viewModel)
			}
		}

		private func applyPendingUpdate(viewModel: UpdatesListViewModel) {
			isUpdateScheduled = false
			guard let update = pendingUpdate else { return }
			pendingUpdate = nil
			apply(update, viewModel: viewModel)
		}

		private func apply(_ update: TableUpdate, viewModel: UpdatesListViewModel) {
			self.viewModel = viewModel
			let previousEntries = entries
			let previousContentState = contentState
			let previousSelectedRowIndex = selectedRowIndex
			let needsContentUpdate = previousContentState != update.contentState
			let tableChange = needsContentUpdate ? TableViewSnapshotDiff(from: previousEntries, to: update.snapshot.entries).change : nil
			entries = update.snapshot.entries
			filterQuery = update.snapshot.filterQuery
			selectedIdentifier = update.selectedIdentifier
			selectedRowIndex = update.selectedRowIndex
			contentState = update.contentState
			menuController.update(viewModel: viewModel, entries: entries)

			if previousContentState == nil {
				tableView?.reloadData()
			} else if needsContentUpdate {
				apply(tableChange)
			} else if previousSelectedRowIndex != update.selectedRowIndex {
				refreshRows(at: [previousSelectedRowIndex, update.selectedRowIndex].compactMap { $0 })
			} else {
				refreshVisibleRows()
			}

			syncSelection()
		}

		func resizeColumn(in scrollView: NSScrollView) {
			guard let tableView else { return }
			let width = scrollView.contentSize.width
			guard width > 0 else { return }

			if abs(tableView.frame.width - width) > 0.5
				|| tableView.frame.origin.x != AppKitTableGeometry.leadingOffset {
				tableView.setFrameOrigin(NSPoint(
					x: AppKitTableGeometry.leadingOffset,
					y: tableView.frame.origin.y
				))
				tableView.setFrameSize(NSSize(width: width, height: tableView.frame.height))
			}

			if let column = tableView.tableColumns.first, abs(column.width - width) > 0.5 {
				column.width = width
			}

			if scrollView.contentView.bounds.origin.x != 0 {
				scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y))
				scrollView.reflectScrolledClipView(scrollView.contentView)
			}
		}

		func numberOfRows(in tableView: NSTableView) -> Int {
			entries.count
		}

		func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
			guard row >= 0, row < entries.count else { return -1 }
			return isSectionHeader(at: row) ? VisualMetrics.sectionHeaderHeight : VisualMetrics.appRowHeight
		}

		func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
			isSectionHeader(at: row)
		}

		func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
			SidebarInteractionPolicy(entries: entries).isSelectable(row: row)
		}

		func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
			if isSectionHeader(at: row) {
				return NoDrawingGroupRowView()
			}

			// Preserve the native source-list geometry without flashing the accent
			// color as focus moves between the main and Settings windows.
			return StableSelectionTableRowView()
		}

		func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
			guard row >= 0, row < entries.count else { return nil }

			switch entries[row] {
			case .section(let section):
				let identifier = NSUserInterfaceItemIdentifier("LatestSwiftUISectionCell")
				let view = tableView.makeView(withIdentifier: identifier, owner: self) as? AppKitUpdateSectionHeaderContentView
					?? AppKitUpdateSectionHeaderContentView()
				view.identifier = identifier
				view.update(section: section)
				return view

			case .app(let app):
				let identifier = NSUserInterfaceItemIdentifier("LatestSwiftUIUpdateCell")
				let view = tableView.makeView(withIdentifier: identifier, owner: self) as? AppKitUpdateRowContentView
					?? AppKitUpdateRowContentView()
				view.identifier = identifier
				view.onSelect = { [weak self] in
					self?.viewModel.select(app)
				}
				view.update(
					app: app,
					isSelected: selectedIdentifier == app.identifier,
					filterQuery: filterQuery,
					dateFormatter: Self.dateFormatter,
					showsSupportStatusOverride: showsSupportStatusOverride
				)
				return view
			}
		}

		func tableViewSelectionDidChange(_ notification: Notification) {
			guard !isSynchronizingSelection else { return }
			guard let tableView = notification.object as? NSTableView else { return }
			selectRow(at: tableView.selectedRow)
		}

		func selectRow(at row: Int) {
			guard row >= 0, row < entries.count else {
				viewModel.select(nil)
				return
			}
			if case .app(let app) = entries[row] {
				viewModel.select(app)
			}
		}

		func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
			let policy = SidebarInteractionPolicy(entries: entries)
			guard let app = policy.app(at: row) else { return [] }

			if edge == .trailing {
				guard policy.swipeActions(for: row, edge: .trailing).contains(.update) else { return [] }

				let action = NSTableViewRowAction(style: .regular, title: SidebarUpdateActionTitle.text(for: app)) { [weak self] _, _ in
					self?.viewModel.update(app)
					tableView.rowActionsVisible = false
				}
				action.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
				action.backgroundColor = .systemCyan
				return [action]
			}

			if edge == .leading {
				guard policy.swipeActions(for: row, edge: .leading) == [.open, .revealInFinder] else {
					return []
				}
				let open = NSTableViewRowAction(
					style: .regular,
					title: NSLocalizedString("OpenAction", comment: "Action to open a given app.")
				) { [weak self] _, _ in
					self?.viewModel.open(app)
					tableView.rowActionsVisible = false
				}
				open.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)

				let reveal = NSTableViewRowAction(
					style: .regular,
					title: NSLocalizedString("RevealAction", comment: "Reveal in Finder Row action")
				) { [weak self] _, _ in
					self?.viewModel.revealInFinder(app)
					tableView.rowActionsVisible = false
				}
				reveal.backgroundColor = .systemGray
				reveal.image = NSImage(systemSymbolName: "finder", accessibilityDescription: nil)

				return [open, reveal]
			}

			return []
		}

		private func isSectionHeader(at row: Int) -> Bool {
			SidebarInteractionPolicy(entries: entries).isSectionHeader(row: row)
		}

		private func syncSelection() {
			guard let tableView else { return }
			guard let selectedIdentifier else {
				tableView.deselectAll(nil)
				return
			}
			guard let index = selectedRowIndex,
			      index >= 0,
			      index < entries.count,
			      case .app(let selectedApp) = entries[index],
			      selectedApp.identifier == selectedIdentifier else {
				tableView.deselectAll(nil)
				return
			}
			if tableView.selectedRow != index {
				isSynchronizingSelection = true
				tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
				isSynchronizingSelection = false
			}
		}

		private func refreshVisibleRows() {
			guard let tableView else { return }
			let visibleRows = tableView.rows(in: tableView.visibleRect)
			guard visibleRows.location != NSNotFound else { return }

			refreshRows(at: Array(visibleRows.location..<NSMaxRange(visibleRows)))
		}

		private func refreshRows(at rows: [Int]) {
			guard let tableView else { return }
			for row in Set(rows) {
				guard row >= 0, row < entries.count, case .app(let app) = entries[row] else { continue }
				guard let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? AppKitUpdateRowContentView else { continue }
				view.update(
					app: app,
					isSelected: selectedIdentifier == app.identifier,
					filterQuery: filterQuery,
					dateFormatter: Self.dateFormatter,
					showsSupportStatusOverride: showsSupportStatusOverride
				)
			}
		}

		private func apply(_ change: TableViewSnapshotDiff.Change?) {
			guard let tableView else { return }

			switch change {
			case .none:
				refreshVisibleRows()
			case .reload(let indexes):
				guard let columnIndex = tableView.tableColumns.indices.first else {
					tableView.reloadData()
					return
				}
				tableView.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet(integer: columnIndex))
			case .append(let indexes):
				tableView.insertRows(at: indexes, withAnimation: [])
			case .remove(let indexes):
				tableView.removeRows(at: indexes, withAnimation: [])
			case .reloadAll:
				tableView.reloadData()
			}
		}

		@MainActor private struct TableUpdate {
			let snapshot: AppListSnapshot
			let selectedIdentifier: App.Bundle.Identifier?
			let selectedRowIndex: Int?
			let contentState: TableContentState

			init(viewModel: UpdatesListViewModel) {
				self.snapshot = viewModel.snapshot
				self.selectedIdentifier = viewModel.selectedApp?.identifier
				self.selectedRowIndex = viewModel.selectedApp.flatMap { viewModel.snapshot.firstIndex(of: $0) }
				self.contentState = TableContentState(snapshotRevision: viewModel.snapshotRevision)
			}
		}

		@MainActor private struct TableContentState: Equatable {
			let snapshotRevision: Int
		}

		private static let dateFormatter: DateFormatter = {
			let formatter = DateFormatter()
			formatter.timeStyle = .none
			formatter.dateStyle = .short
			formatter.doesRelativeDateFormatting = true
			return formatter
		}()
	}
}

@MainActor
private final class SidebarTableMenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
	weak var tableView: NSTableView?
	private var viewModel: UpdatesListViewModel
	private var entries = [AppListSnapshot.Entry]()
	private(set) lazy var menu: NSMenu = makeMenu()

	init(viewModel: UpdatesListViewModel) {
		self.viewModel = viewModel
	}

	func update(viewModel: UpdatesListViewModel, entries: [AppListSnapshot.Entry]) {
		self.viewModel = viewModel
		self.entries = entries
	}

	func menuNeedsUpdate(_ menu: NSMenu) {
		let app = targetApp()
		menu.items.forEach { item in
			guard !item.isSeparatorItem else { return }
			item.representedObject = app
		}
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return true }
		guard let app = targetApp(for: menuItem) else { return false }

		switch action {
		case #selector(updateApp(_:)):
			menuItem.title = SidebarUpdateActionTitle.text(for: app)
			return app.updateAvailable && !app.isUpdating
		case #selector(openApp(_:)), #selector(revealInFinder(_:)):
			return true
		case #selector(ignoreApp(_:)):
			menuItem.isHidden = app.isIgnored
			return true
		case #selector(unignoreApp(_:)):
			menuItem.isHidden = !app.isIgnored
			return true
		default:
			return false
		}
	}

	@objc private func updateApp(_ sender: NSMenuItem?) {
		guard let app = targetApp(for: sender) else { return }
		viewModel.update(app)
	}

	@objc private func ignoreApp(_ sender: NSMenuItem?) {
		guard let app = targetApp(for: sender) else { return }
		viewModel.setIgnored(true, for: app)
	}

	@objc private func unignoreApp(_ sender: NSMenuItem?) {
		guard let app = targetApp(for: sender) else { return }
		viewModel.setIgnored(false, for: app)
	}

	@objc private func openApp(_ sender: NSMenuItem?) {
		guard let app = targetApp(for: sender) else { return }
		viewModel.open(app)
	}

	@objc private func revealInFinder(_ sender: NSMenuItem?) {
		guard let app = targetApp(for: sender) else { return }
		viewModel.revealInFinder(app)
	}

	private func makeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.delegate = self
		menu.autoenablesItems = true
		menu.addItem(menuItem(
			title: NSLocalizedString("UpdateAction", comment: "Action to update a given app."),
			image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil),
			action: #selector(updateApp(_:))
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("IgnoreAction", value: "Ignore", comment: "Action to ignore a given app."),
			image: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil),
			action: #selector(ignoreApp(_:))
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("UnignoreAction", value: "Don't Ignore", comment: "Action to stop ignoring a given app."),
			image: NSImage(named: "custom.app.dashed.slash"),
			action: #selector(unignoreApp(_:))
		))
		menu.addItem(.separator())
		menu.addItem(menuItem(
			title: NSLocalizedString("OpenAction", comment: "Action to open a given app."),
			image: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil),
			action: #selector(openApp(_:))
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("RevealAction", comment: "Reveal in Finder Row action"),
			image: NSImage(systemSymbolName: "finder", accessibilityDescription: nil),
			action: #selector(revealInFinder(_:))
		))
		return menu
	}

	private func menuItem(title: String, image: NSImage?, action: Selector) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.target = self
		item.image = image
		return item
	}

	private func targetApp(for menuItem: NSMenuItem? = nil) -> App? {
		if let app = menuItem?.representedObject as? App {
			return app
		}
		guard let tableView else { return nil }
		return SidebarInteractionPolicy(entries: entries).targetApp(
			clickedRow: tableView.clickedRow,
			selectedRow: tableView.selectedRow
		)
	}
}

@MainActor
private enum SidebarUpdateActionTitle {
	static func text(for app: App) -> String {
		if let externalUpdater = app.externalUpdaterName {
			return String(
				format: NSLocalizedString(
					"ExternalUpdateAction",
					comment: "Action to update a given app outside of Latest. The placeholder is filled with the name of the external updater. (App Store, App Name)"
				),
				externalUpdater
			)
		}

		return NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
	}
}

private final class SwiftUIUpdateTableView: NSTableView {
	var onMouseDownRow: ((Int) -> Void)?

	override func menu(for event: NSEvent) -> NSMenu? {
		let clickedPoint = convert(event.locationInWindow, from: nil)
		let clickedRow = row(at: clickedPoint)
		guard clickedRow >= 0,
		      !(delegate?.tableView?(self, isGroupRow: clickedRow) ?? false) else {
			return nil
		}
		return super.menu(for: event)
	}

	override func layout() {
		super.layout()
		lockHorizontalGeometry()
	}

	override func setFrameOrigin(_ newOrigin: NSPoint) {
		super.setFrameOrigin(NSPoint(x: AppKitTableGeometry.leadingOffset, y: newOrigin.y))
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let clickedPoint = convert(event.locationInWindow, from: nil)
		let clickedRow = row(at: clickedPoint)
		if clickedRow >= 0, delegate?.tableView?(self, shouldSelectRow: clickedRow) ?? true {
			selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
			onMouseDownRow?(clickedRow)
		}
		super.mouseDown(with: event)
	}

	private func lockHorizontalGeometry() {
		guard let scrollView = enclosingScrollView else { return }
		let width = scrollView.contentSize.width
		if width > 0, abs(frame.width - width) > 0.5 {
			setFrameSize(NSSize(width: width, height: frame.height))
		}
		if frame.origin.x != AppKitTableGeometry.leadingOffset {
			setFrameOrigin(NSPoint(x: AppKitTableGeometry.leadingOffset, y: frame.origin.y))
		}
		if scrollView.contentView.bounds.origin.x != 0 {
			scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y))
			scrollView.reflectScrolledClipView(scrollView.contentView)
		}
	}
}

private final class NoDrawingGroupRowView: NSTableRowView {
	override func drawBackground(in dirtyRect: NSRect) {}
}

private final class LockedHorizontalScrollView: NSScrollView {
	override func scrollWheel(with event: NSEvent) {
		super.scrollWheel(with: event)
		guard contentView.bounds.origin.x != 0 else { return }
		contentView.bounds.origin.x = 0
		reflectScrolledClipView(contentView)
	}
}

private final class LockedHorizontalClipView: NSClipView {
	override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
		var bounds = super.constrainBoundsRect(proposedBounds)
		bounds.origin.x = 0
		return bounds
	}

	override func scroll(to newOrigin: NSPoint) {
		let lockedOrigin = NSPoint(x: 0, y: newOrigin.y)
		guard bounds.origin.x != lockedOrigin.x || bounds.origin.y != lockedOrigin.y else { return }
		super.scroll(to: lockedOrigin)
	}
}
