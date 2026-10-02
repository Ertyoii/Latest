//
//  UpdatesTableBridge.swift
//  Latest
//
//  Created by ertyoii on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-04.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI

/// Shipping sidebar renderer. NSTableView owns row geometry, selection, and
/// scrolling; SwiftUI owns feature state, search, and surrounding composition.
struct UpdatesTableBridge: View {
  @ObservedObject var viewModel: UpdatesListViewModel
  let showsSupportStatusOverride: Bool?
  var keyboardFocusRequest: UInt = 0
  var keyboardFocusDidBegin: (() -> Void)?

  var body: some View {
    UpdatesTableView(
      viewModel: viewModel,
      snapshotRevision: viewModel.snapshotRevision,
      selectedIdentifier: viewModel.selectedApp?.identifier,
      showsSupportStatusOverride: showsSupportStatusOverride,
      keyboardFocusRequest: keyboardFocusRequest,
      keyboardFocusDidBegin: keyboardFocusDidBegin)
  }
}

private struct UpdatesTableView: NSViewRepresentable {
  let viewModel: UpdatesListViewModel
  let snapshotRevision: Int
  let selectedIdentifier: App.Bundle.Identifier?
  let showsSupportStatusOverride: Bool?
  let keyboardFocusRequest: UInt
  let keyboardFocusDidBegin: (() -> Void)?

  func makeCoordinator() -> Coordinator {
    Coordinator(
      viewModel: viewModel,
      showsSupportStatusOverride: showsSupportStatusOverride
    )
  }

  func makeNSView(context: Context) -> NSScrollView {
    let tableView = SwiftUIUpdateTableView()
    tableView.keyboardFocusDidBegin = keyboardFocusDidBegin
    tableView.delegate = context.coordinator
    tableView.dataSource = context.coordinator
    tableView.menu = context.coordinator.tableViewMenu
    tableView.headerView = nil
    tableView.gridStyleMask = []
    tableView.rowHeight = VisualMetrics.appRowHeight
    tableView.usesAutomaticRowHeights = false
    tableView.intercellSpacing = .zero
    tableView.style = .sourceList
    tableView.floatsGroupRows = true
    tableView.backgroundColor = .clear
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
    scrollView.contentInsets = NSEdgeInsetsZero
    scrollView.scrollerInsets = NSEdgeInsets(
      top: 0, left: 0, bottom: VisualMetrics.scrollBottomInset, right: 0)
    scrollView.documentView = tableView

    context.coordinator.tableView = tableView
    context.coordinator.observeLiveScrolling(in: scrollView)
    tableView.sizeToViewport()
    context.coordinator.apply(viewModel: viewModel)
    context.coordinator.requestKeyboardFocus(keyboardFocusRequest)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.tableView?.keyboardFocusDidBegin = keyboardFocusDidBegin
    context.coordinator.requestKeyboardFocus(keyboardFocusRequest)
    context.coordinator.showsSupportStatusOverride = showsSupportStatusOverride
    context.coordinator.scheduleApply(
      viewModel: viewModel, snapshotRevision: snapshotRevision,
      selectedIdentifier: selectedIdentifier)
  }

  @MainActor
  final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    weak var tableView: SwiftUIUpdateTableView? {
      didSet { menuController.tableView = tableView }
    }
    private var lastKeyboardFocusRequest: UInt = 0
    private var viewModel: UpdatesListViewModel
    private var entries: [AppListSnapshot.Entry] = []
    private var filterQuery: String?
    private var selectedIdentifier: App.Bundle.Identifier?
    private var selectedRowIndex: Int?
    private var snapshotRevision: Int?
    private var appliedShowsSupportStatusOverride: Bool?
    private var isUpdateScheduled = false
    private var isSynchronizingSelection = false
    var showsSupportStatusOverride: Bool?
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

    func requestKeyboardFocus(_ request: UInt) {
      guard request != lastKeyboardFocusRequest else { return }
      lastKeyboardFocusRequest = request
      Task { @MainActor [weak tableView] in
        guard let tableView else { return }
        tableView.window?.makeFirstResponder(tableView)
      }
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

    func scheduleApply(
      viewModel: UpdatesListViewModel, snapshotRevision: Int,
      selectedIdentifier: App.Bundle.Identifier?
    ) {
      self.viewModel = viewModel
      // Native selection already updated these rows during the key event.
      guard
        self.snapshotRevision != snapshotRevision
          || self.selectedIdentifier != selectedIdentifier
          || appliedShowsSupportStatusOverride != showsSupportStatusOverride
      else { return }
      guard !isUpdateScheduled else { return }
      isUpdateScheduled = true

      Task { @MainActor [weak self] in
        guard let self else { return }
        self.isUpdateScheduled = false
        // Read current selection here: a captured selection can be obsolete
        // after another key event and move the native table backwards.
        self.apply(viewModel: self.viewModel)
      }
    }

    func apply(viewModel: UpdatesListViewModel) {
      self.viewModel = viewModel
      let snapshot = viewModel.snapshot
      let nextSelectedApp = viewModel.selectedApp
      let nextSelectedRowIndex = nextSelectedApp.flatMap { snapshot.firstIndex(of: $0) }
      let nextRevision = viewModel.snapshotRevision
      let previousEntries = entries
      let previousRevision = snapshotRevision
      let previousSelectedRowIndex = selectedRowIndex
      let needsContentUpdate = previousRevision != nextRevision
      let needsSupportUpdate = appliedShowsSupportStatusOverride != showsSupportStatusOverride
      let tableChange =
        needsContentUpdate
        ? TableViewSnapshotDiff(from: previousEntries, to: snapshot.entries).change : nil
      entries = snapshot.entries
      filterQuery = snapshot.filterQuery
      selectedIdentifier = nextSelectedApp?.identifier
      selectedRowIndex = nextSelectedRowIndex
      snapshotRevision = nextRevision
      appliedShowsSupportStatusOverride = showsSupportStatusOverride
      menuController.update(viewModel: viewModel, entries: entries)

      if previousRevision == nil {
        tableView?.reloadData()
      } else if needsContentUpdate {
        apply(tableChange)
      } else if needsSupportUpdate {
        refreshVisibleRows()
      }

      syncSelection()
      if previousSelectedRowIndex != nextSelectedRowIndex {
        refreshSelection(at: previousSelectedRowIndex)
        refreshSelection(at: nextSelectedRowIndex)
      }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
      entries.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
      guard row >= 0, row < entries.count else { return -1 }
      return isSectionHeader(at: row)
        ? VisualMetrics.sectionHeaderHeight : VisualMetrics.appRowHeight
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
      isSectionHeader(at: row)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
      SidebarInteractionPolicy(entries: entries, updating: viewModel.updating).isSelectable(
        row: row)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
      if isSectionHeader(at: row) {
        return SidebarSectionRowView()
      }

      return NSTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      guard row >= 0, row < entries.count else { return nil }

      switch entries[row] {
      case .section(let section):
        let identifier = NSUserInterfaceItemIdentifier("LatestSwiftUISectionCell")
        let view =
          tableView.makeView(withIdentifier: identifier, owner: self)
          as? NSHostingView<UpdateSectionHeaderView>
          ?? NSHostingView(rootView: UpdateSectionHeaderView(section: section))
        view.identifier = identifier
        view.rootView = UpdateSectionHeaderView(section: section)
        return view

      case .app(let app):
        let identifier = NSUserInterfaceItemIdentifier("LatestSwiftUIUpdateCell")
        let view =
          tableView.makeView(withIdentifier: identifier, owner: self) as? UpdateRowHostingCell
          ?? UpdateRowHostingCell()
        view.identifier = identifier
        view.update(
          app: app,
          isSelected: selectedIdentifier == app.identifier,
          filterQuery: filterQuery,
          dateFormatter: Self.dateFormatter,
          showsSupportStatusOverride: showsSupportStatusOverride,
          updating: viewModel.updating
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
      let app = SidebarInteractionPolicy(entries: entries, updating: viewModel.updating).app(
        at: row)
      let nextRowIndex = app == nil ? nil : row
      guard selectedRowIndex != nextRowIndex else { return }
      let previousSelectedRowIndex = selectedRowIndex
      selectedIdentifier = app?.identifier
      selectedRowIndex = nextRowIndex
      refreshSelection(at: previousSelectedRowIndex)
      refreshSelection(at: nextRowIndex)
      let isKeyboardSelection = tableView?.isHandlingArrowKey ?? false
      viewModel.select(app, isKeyboardSelection: isKeyboardSelection)
    }

    private func refreshSelection(at row: Int?) {
      guard let tableView, let row, row >= 0, row < tableView.numberOfRows,
        let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
          as? UpdateRowHostingCell
      else { return }
      cell.updateSelection(row == selectedRowIndex)
    }

    func tableView(
      _ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge
    ) -> [NSTableViewRowAction] {
      let policy = SidebarInteractionPolicy(entries: entries, updating: viewModel.updating)
      guard let app = policy.app(at: row) else { return [] }

      if edge == .trailing {
        guard policy.swipeActions(for: row, edge: .trailing).contains(.update) else { return [] }

        let action = NSTableViewRowAction(
          style: .regular, title: SidebarUpdateActionTitle.text(for: app)
        ) { [weak self] _, _ in
          self?.viewModel.update(app)
          tableView.rowActionsVisible = false
        }
        action.image = NSImage(
          systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
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
        open.image = NSImage(
          systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)

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
      SidebarInteractionPolicy(entries: entries, updating: viewModel.updating).isSectionHeader(
        row: row)
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
        selectedApp.identifier == selectedIdentifier
      else {
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

      for row in visibleRows.location..<NSMaxRange(visibleRows) {
        guard row >= 0, row < entries.count, case .app(let app) = entries[row] else { continue }
        guard
          let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
            as? UpdateRowHostingCell
        else { continue }
        view.update(
          app: app,
          isSelected: selectedIdentifier == app.identifier,
          filterQuery: filterQuery,
          dateFormatter: Self.dateFormatter,
          showsSupportStatusOverride: showsSupportStatusOverride,
          updating: viewModel.updating
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

    private static let dateFormatter: DateFormatter = {
      let formatter = DateFormatter()
      formatter.timeStyle = .none
      formatter.dateStyle = .short
      formatter.doesRelativeDateFormatting = true
      return formatter
    }()
  }
}

/// NSTableCellView forwards native selection emphasis to SwiftUI row content.
final class UpdateRowHostingCell: NSTableCellView {
  private var host: UpdateRowHostingView?
  private let selection = UpdateRowSelection()

  override init(frame frameRect: NSRect) { super.init(frame: frameRect) }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var backgroundStyle: NSView.BackgroundStyle {
    didSet {
      updateSelectionEmphasis()
    }
  }

  func update(
    app: App,
    isSelected: Bool,
    filterQuery: String?,
    dateFormatter: DateFormatter,
    showsSupportStatusOverride: Bool? = nil,
    updating: any AppUpdating = AppUpdateService.shared
  ) {
    selection.style =
      isSelected ? (backgroundStyle == .emphasized ? .active : .inactive) : .unselected
    let content = UpdateRowView(
      app: app, selection: selection,
      filterQuery: filterQuery, date: dateFormatter.string(from: app.updateDate),
      showsSupportStatus: showsSupportStatusOverride ?? true, updating: updating)
    if let host {
      host.rootView = content
    } else {
      let host = UpdateRowHostingView(rootView: content)
      host.sizingOptions = []
      host.frame = bounds
      host.autoresizingMask = [.width, .height]
      addSubview(host)
      self.host = host
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(content.accessibilityLabel)
    setAccessibilitySelected(isSelected)
  }

  private func updateSelectionEmphasis() {
    let selected =
      backgroundStyle == .emphasized
      || ((superview as? NSTableRowView)?.isSelected ?? selection.isSelected)
    updateSelection(selected)
  }

  func updateSelection(_ selected: Bool) {
    guard let host else { return }
    let emphasized = selected && backgroundStyle == .emphasized
    let style: UpdateRowSelection.Style =
      selected ? (emphasized ? .active : .inactive) : .unselected
    guard selection.style != style else { return }
    let changesTextColor = selection.usesActiveSelectionColors != emphasized
    selection.style = style
    setAccessibilitySelected(selected)
    // Resolve SwiftUI text colors in the same turn as the native highlight.
    if changesTextColor { host.layoutSubtreeIfNeeded() }
  }
}

/// Passive SwiftUI content handles the click without focusing its native table.
/// Keep keyboard navigation with the table after clicking a hosted row.
private final class UpdateRowHostingView: NSHostingView<UpdateRowView> {
  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    if let table = enclosingScrollView?.documentView as? NSTableView {
      window?.makeFirstResponder(table)
    }
  }
}
