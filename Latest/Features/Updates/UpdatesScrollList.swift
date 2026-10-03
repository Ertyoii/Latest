// Fork contributions © 2026 ertyoii.
// Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import Observation
import SwiftUI

// Xcode 26 builds keep the macOS 26 renderer. Native swipe coordination for
// custom scroll layouts is available starting with the macOS 27 SDK.
#if compiler(>=6.4)
  @available(macOS 27.0, *)
  struct UpdatesScrollList: View {
    @ObservedObject var viewModel: UpdatesListViewModel
    let showsSupportStatusOverride: Bool?
    let focus: FocusState<SidebarFocus?>.Binding
    @State private var navigation = SidebarScrollState()
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
      SidebarScrollingViewport(viewModel: viewModel, navigation: navigation) {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
          ForEach(viewModel.snapshot.sections) { group in
            Section {
              Color.clear.frame(height: 10)
                .accessibilityHidden(true)
              ForEach(group.apps, id: \.identifier) { app in
                UpdatesScrollRow(
                  app: app, viewModel: viewModel,
                  showsSupportStatus: showsSupportStatusOverride ?? true,
                  focus: focus,
                  selection: navigation.selection(for: app),
                  select: { select(app, keyboard: false) })
              }
            } header: {
              UpdateSectionHeaderView(section: group.section)
                .frame(height: VisualMetrics.sectionHeaderHeight)
                .background(Color(nsColor: .windowBackgroundColor))
                .accessibilityAddTraits(.isHeader)
            }
          }
        }
        .background(alignment: .topLeading) {
          SidebarListSelection(navigation: navigation)
        }
      }
      .scrollEdgeEffectHidden()
      .swipeActionsContainer()
      .focusable()
      .focusEffectDisabled()
      .focused(focus, equals: .list)
      .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
        guard press.modifiers.intersection([.command, .option, .control, .shift]).isEmpty else {
          return .ignored
        }
        moveSelection(down: press.key == .downArrow)
        return .handled
      }
      .onScrollGeometryChange(for: CGRect.self) {
        $0.visibleRect
      } action: { _, next in
        // Geometry is input to navigation, not presentation state. Updating it
        // must not rebuild visible rows on every scroll frame.
        navigation.viewport = next
      }
      .onScrollPhaseChange { _, phase in
        if phase == .idle {
          MigrationTelemetry.shared.endSidebarScroll()
        } else {
          MigrationTelemetry.shared.beginSidebarScroll()
        }
      }
      .onChange(of: viewModel.snapshotRevision, initial: true) { _, _ in
        navigation.apply(snapshot: viewModel.snapshot)
        navigation.synchronize(viewModel.selectedApp?.identifier)
        let maximum = max(0, navigation.contentHeight - navigation.viewport.height)
        if navigation.viewport.minY > maximum {
          scroll(to: maximum)
        }
      }
      .onChange(of: focus.wrappedValue, initial: true) { _, _ in
        navigation.setEmphasized(focus.wrappedValue == .list && controlActiveState != .inactive)
      }
      .onChange(of: controlActiveState) { _, _ in
        navigation.setEmphasized(focus.wrappedValue == .list && controlActiveState != .inactive)
      }
      .accessibilityIdentifier("updates.list")
      .accessibilityLabel("Apps")
    }

    private func moveSelection(down: Bool) {
      let snapshot = viewModel.snapshot
      let current = viewModel.selectedApp.flatMap { snapshot.firstIndex(of: $0) }
      var index = current.map { $0 + (down ? 1 : -1) } ?? 0
      while snapshot.entries.indices.contains(index) {
        if case .app(let app) = snapshot.entries[index] {
          moveSelection(to: app, row: navigation.frames[index])
          return
        }
        index += current == nil || down ? 1 : -1
      }
      if let current, case .app(let app) = snapshot.entries[current] {
        moveSelection(to: app, row: navigation.frames[current])
      }
    }

    private func moveSelection(to app: App, row: CGRect) {
      // Update both values in one transaction. No delayed scroll or animation may
      // move the viewport back after another key, a reversal, or a search change.
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        select(app, keyboard: true)
        let target = navigation.scrollOffset(for: row, viewport: navigation.viewport)
        if abs(target - navigation.viewport.minY) > 0.5 { scroll(to: target) }
      }
    }

    private func scroll(to y: CGFloat) {
      navigation.viewport.origin.y = y
      navigation.position.scrollTo(y: y)
    }

    private func select(_ app: App, keyboard: Bool) {
      navigation.synchronize(app.identifier)
      viewModel.select(app, isKeyboardSelection: keyboard)
    }
  }

  // Selection and ScrollPosition invalidate only this viewport. The lazy
  // stack's view value stays stable across arrows and retains its swipe/AX rows.
  private struct SidebarScrollingViewport<Content: View>: View {
    let viewModel: UpdatesListViewModel
    @Bindable var navigation: SidebarScrollState
    let content: Content

    init(
      viewModel: UpdatesListViewModel, navigation: SidebarScrollState,
      @ViewBuilder content: () -> Content
    ) {
      self.viewModel = viewModel
      self.navigation = navigation
      self.content = content()
    }

    var body: some View {
      ScrollView(.vertical) { content }
        .scrollPosition($navigation.position)
        .onChange(of: viewModel.selectedApp?.identifier, initial: true) { _, identifier in
          navigation.synchronize(identifier)
        }
        .contextMenu {
          if let app = viewModel.selectedApp {
            UpdatesRowMenu(app: app, viewModel: viewModel)
          }
        }
    }
  }

  // Reuse one native background as selection moves, rather than constructing
  // another table for every arrow press. Only this view observes its geometry.
  private struct SidebarListSelection: View {
    let navigation: SidebarScrollState

    var body: some View {
      SidebarSelectionBackground(emphasized: navigation.emphasized)
        .frame(height: VisualMetrics.appRowHeight)
        .offset(y: navigation.selectedFrame?.minY ?? 0)
        .opacity(navigation.selectedFrame == nil ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }

  /// Keep scroll geometry out of SwiftUI invalidation. Selection updates only
  /// its background and two rows; the dictionary is bounded by the snapshot.
  @MainActor
  @Observable
  private final class SidebarScrollState {
    var position = ScrollPosition()
    private(set) var selectedFrame: CGRect?
    private(set) var emphasized = false
    @ObservationIgnored var viewport = CGRect.zero
    @ObservationIgnored private(set) var frames: [CGRect] = []
    @ObservationIgnored private(set) var contentHeight: CGFloat = 0
    @ObservationIgnored private var selections: [App.Bundle.Identifier: UpdateRowSelection] = [:]
    @ObservationIgnored private var selected: App.Bundle.Identifier?
    @ObservationIgnored private var snapshot: AppListSnapshot?

    func selection(for app: App) -> UpdateRowSelection {
      if let selection = selections[app.identifier] { return selection }
      let selection = UpdateRowSelection()
      selection.style =
        selected == app.identifier
        ? (emphasized ? .active : .inactive) : .unselected
      selections[app.identifier] = selection
      return selection
    }

    func apply(snapshot: AppListSnapshot) {
      self.snapshot = snapshot
      frames = []
      frames.reserveCapacity(snapshot.entries.count)
      contentHeight = 0
      var identifiers = Set<App.Bundle.Identifier>()
      for entry in snapshot.entries {
        switch entry {
        case .section:
          frames.append(.zero)
          contentHeight += VisualMetrics.sectionHeaderHeight + 10
        case .app(let app):
          identifiers.insert(app.identifier)
          frames.append(
            CGRect(
              x: 0, y: contentHeight,
              width: VisualMetrics.sidebarIdealWidth, height: VisualMetrics.appRowHeight))
          contentHeight += VisualMetrics.appRowHeight
        }
      }
      selections = selections.filter { identifiers.contains($0.key) }
    }

    func scrollOffset(for row: CGRect, viewport: CGRect) -> CGFloat {
      guard viewport.height > 0 else { return viewport.minY }
      let margin = min(VisualMetrics.appRowHeight, viewport.height / 4)
      var y = viewport.minY
      if row.maxY > viewport.maxY - margin {
        y = row.maxY + margin - viewport.height
      } else if row.minY < viewport.minY + margin {
        y = row.minY - margin
      }
      return min(max(0, y), max(0, contentHeight - viewport.height))
    }

    func synchronize(_ identifier: App.Bundle.Identifier?) {
      if selected != identifier, let selected { selections[selected]?.style = .unselected }
      selected = identifier
      if let identifier { selections[identifier]?.style = emphasized ? .active : .inactive }
      selectedFrame = snapshot?.app(withIdentifier: identifier)
        .flatMap { snapshot?.firstIndex(of: $0) }
        .map { frames[$0] }
    }

    func setEmphasized(_ value: Bool) {
      guard emphasized != value else { return }
      emphasized = value
      synchronize(selected)
    }
  }

  @available(macOS 27.0, *)
  private struct UpdatesScrollRow: View {
    let app: App
    let viewModel: UpdatesListViewModel
    let focus: FocusState<SidebarFocus?>.Binding
    let selection: UpdateRowSelection
    let select: () -> Void
    private let content: UpdateRowView
    private var isSelected: Bool { selection.isSelected }

    init(
      app: App, viewModel: UpdatesListViewModel, showsSupportStatus: Bool,
      focus: FocusState<SidebarFocus?>.Binding, selection: UpdateRowSelection,
      select: @escaping () -> Void
    ) {
      self.app = app
      self.viewModel = viewModel
      self.focus = focus
      self.selection = selection
      self.select = select
      content = UpdateRowView(
        app: app, selection: selection,
        date: Self.dateFormatter.string(from: app.updateDate),
        showsSupportStatus: showsSupportStatus, updating: viewModel.updating)
    }

    var body: some View {
      content
        // The native source-list cell extends 16pt past the viewport. Preserve
        // that measured geometry instead of shrinking its text/status columns.
        .frame(width: VisualMetrics.sidebarIdealWidth, height: VisualMetrics.appRowHeight)
        .offset(x: 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: selectApp)
        .contextMenu { UpdatesRowMenu(app: app, viewModel: viewModel) }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
          Button {
            viewModel.open(app)
          } label: {
            Label(
              NSLocalizedString("OpenAction", comment: "Open app"),
              systemImage: "arrow.up.forward.app")
          }
          Button {
            viewModel.revealInFinder(app)
          } label: {
            Label(NSLocalizedString("RevealAction", comment: "Reveal app"), systemImage: "finder")
          }.tint(.gray)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
          if app.updateAvailable && !viewModel.updating.isUpdating(app) {
            Button {
              viewModel.update(app)
            } label: {
              Label(SidebarUpdateActionTitle.text(for: app), systemImage: "square.and.arrow.down")
            }.tint(.cyan)
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selectApp() }
        .accessibilityIdentifier("updates.app.\(app.identifier)")
    }

    private func selectApp() {
      focus.wrappedValue = .list
      select()
    }

    private static let dateFormatter: DateFormatter = {
      let formatter = DateFormatter()
      formatter.dateStyle = .short
      formatter.timeStyle = .none
      formatter.doesRelativeDateFormatting = true
      return formatter
    }()
  }

  private struct SidebarSelectionBackground: NSViewRepresentable {
    let emphasized: Bool

    func makeNSView(context: Context) -> SidebarSelectionView {
      SidebarSelectionView()
    }

    func updateNSView(_ view: SidebarSelectionView, context: Context) {
      view.table.emphasized = emphasized
      view.table.rowView(atRow: 0, makeIfNecessary: true)?.isEmphasized = emphasized
    }
  }

  private final class SidebarSelectionView: NSView {
    let table = SidebarSelectionTable()
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
      super.init(frame: .zero)
      clipsToBounds = true
      addSubview(table)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
      super.layout()
      let row = table.rect(ofRow: 0)
      // Align the native row, excluding the table's outer top padding.
      table.frame = NSRect(x: 0, y: -row.minY, width: bounds.width, height: row.maxY)
    }
  }

  /// AppKit owns source-list selection materials; this single empty row only paints the background.
  private final class SidebarSelectionTable: NSTableView, NSTableViewDataSource, NSTableViewDelegate
  {
    var emphasized = false
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
      super.init(frame: .zero)
      style = .sourceList
      backgroundColor = .clear
      headerView = nil
      intercellSpacing = .zero
      rowHeight = VisualMetrics.appRowHeight
      usesAutomaticRowHeights = false
      focusRingType = .none
      dataSource = self
      delegate = self
      let column = NSTableColumn(identifier: .init("selection"))
      column.width = VisualMetrics.sidebarIdealWidth
      addTableColumn(column)
      reloadData()
      selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func numberOfRows(in tableView: NSTableView) -> Int { 1 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      NSView()
    }
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
      rowView.isEmphasized = emphasized
    }
  }

  private struct UpdatesRowMenu: View {
    let app: App
    let viewModel: UpdatesListViewModel

    var body: some View {
      Button {
        viewModel.update(app)
      } label: {
        Label(SidebarUpdateActionTitle.text(for: app), systemImage: "square.and.arrow.down")
      }.disabled(!app.updateAvailable || viewModel.updating.isUpdating(app))
      Button {
        viewModel.setIgnored(!app.isIgnored, for: app)
      } label: {
        if app.isIgnored {
          Label(
            NSLocalizedString("UnignoreAction", value: "Don't Ignore", comment: "Unignore app"),
            image: "custom.app.dashed.slash")
        } else {
          Label(
            NSLocalizedString("IgnoreAction", value: "Ignore", comment: "Ignore app"),
            systemImage: "app.dashed")
        }
      }
      Divider()
      Button {
        viewModel.open(app)
      } label: {
        Label(
          NSLocalizedString("OpenAction", comment: "Open app"), systemImage: "arrow.up.forward.app")
      }
      Button {
        viewModel.revealInFinder(app)
      } label: {
        Label(NSLocalizedString("RevealAction", comment: "Reveal app"), systemImage: "finder")
      }
    }
  }
#endif
