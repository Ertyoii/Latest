// Fork contributions © 2026 ertyoii.
// Licensed under GPL-3.0; see LICENSE.md.

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
      SidebarScrollingViewport(navigation: navigation) {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
          ForEach(viewModel.snapshot.sections) { group in
            Section {
              Color.clear.frame(height: SidebarNavigationLayout.sectionSpacing)
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
        let maximum = max(0, navigation.layout.contentHeight - navigation.viewport.height)
        if navigation.viewport.minY > maximum {
          scroll(to: maximum)
        }
      }
      .background {
        SidebarSelectionObserver(viewModel: viewModel, navigation: navigation)
      }
      .onChange(of: focus.wrappedValue, initial: true) { _, _ in
        navigation.setEmphasized(focus.wrappedValue == .list && controlActiveState != .inactive)
      }
      .onChange(of: controlActiveState) { _, _ in
        navigation.setEmphasized(focus.wrappedValue == .list && controlActiveState != .inactive)
      }
      .modifier(SidebarSelectionMenu(viewModel: viewModel))
      .accessibilityIdentifier("updates.list")
      .accessibilityLabel("Apps")
    }

    private func moveSelection(down: Bool) {
      guard let app = navigation.layout.next(after: viewModel.selectedApp?.identifier, down: down),
        let row = navigation.layout.frames[app.identifier]
      else { return }
      // Update both values in one transaction. No delayed scroll or animation may
      // move the viewport back after another key, a reversal, or a search change.
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        select(app, keyboard: true)
        let target = navigation.layout.scrollOffset(for: row, viewport: navigation.viewport)
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

  // ScrollPosition changes only invalidate the viewport. Keep the lazy stack's
  // view value stable rather than recreating its swipe/AX rows for each arrow.
  private struct SidebarScrollingViewport<Content: View>: View {
    @Bindable var navigation: SidebarScrollState
    let content: Content

    init(navigation: SidebarScrollState, @ViewBuilder content: () -> Content) {
      self.navigation = navigation
      self.content = content()
    }

    var body: some View {
      ScrollView(.vertical) { content }
        .scrollPosition($navigation.position)
    }
  }

  // Reading selection here confines Observation invalidation to this observer;
  // the lazy stack does not recreate every visible swipe container per arrow.
  private struct SidebarSelectionObserver: View {
    let viewModel: UpdatesListViewModel
    let navigation: SidebarScrollState

    var body: some View {
      Color.clear.accessibilityHidden(true)
        .onChange(of: viewModel.selectedApp?.identifier, initial: true) { _, identifier in
          navigation.synchronize(identifier)
        }
    }
  }

  private struct SidebarSelectionMenu: ViewModifier {
    let viewModel: UpdatesListViewModel

    func body(content: Content) -> some View {
      content.contextMenu {
        if let app = viewModel.selectedApp {
          UpdatesRowMenu(app: app, viewModel: viewModel)
        }
      }
    }
  }

  /// Keep geometry out of SwiftUI invalidation, and notify only the two rows
  /// whose selection changes. The dictionary is bounded by the current snapshot.
  @MainActor
  @Observable
  private final class SidebarScrollState {
    var position = ScrollPosition()
    @ObservationIgnored var viewport = CGRect.zero
    @ObservationIgnored var layout = SidebarNavigationLayout()
    @ObservationIgnored private var selections: [App.Bundle.Identifier: UpdateRowSelection] = [:]
    @ObservationIgnored private var selected: App.Bundle.Identifier?
    @ObservationIgnored private var emphasized = false

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
      layout = SidebarNavigationLayout(snapshot: snapshot)
      let identifiers = Set(layout.apps.map(\.identifier))
      selections = selections.filter { identifiers.contains($0.key) }
    }

    func synchronize(_ identifier: App.Bundle.Identifier?) {
      if selected != identifier, let selected { selections[selected]?.style = .unselected }
      selected = identifier
      if let identifier { selections[identifier]?.style = emphasized ? .active : .inactive }
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
    let showsSupportStatus: Bool
    let focus: FocusState<SidebarFocus?>.Binding
    let selection: UpdateRowSelection
    let select: () -> Void
    private var isSelected: Bool { selection.isSelected }
    private var isEmphasized: Bool { selection.usesActiveSelectionColors }

    var body: some View {
      let content = UpdateRowView(
        app: app, selection: selection, filterQuery: viewModel.snapshot.filterQuery,
        date: Self.dateFormatter.string(from: app.updateDate),
        showsSupportStatus: showsSupportStatus, updating: viewModel.updating)
      return
        content
        // The native source-list cell extends 16pt past the viewport. Preserve
        // that measured geometry instead of shrinking its text/status columns.
        .frame(width: VisualMetrics.sidebarIdealWidth, height: VisualMetrics.appRowHeight)
        .offset(x: 16)
        .background {
          if isSelected {
            RoundedRectangle(cornerRadius: 8)
              .fill(
                Color(
                  nsColor: isEmphasized
                    ? .selectedContentBackgroundColor : .unemphasizedSelectedTextBackgroundColor)
              )
              .padding(.horizontal, 10)
          }
        }
        .contentShape(Rectangle())
        .onTapGesture {
          focus.wrappedValue = .list
          select()
        }
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
        .accessibilityAction {
          focus.wrappedValue = .list
          select()
        }
        .accessibilityIdentifier("updates.app.\(app.identifier)")
        .id(app.identifier)
    }

    private static let dateFormatter: DateFormatter = {
      let formatter = DateFormatter()
      formatter.dateStyle = .short
      formatter.timeStyle = .none
      formatter.doesRelativeDateFormatting = true
      return formatter
    }()
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

/// Fixed geometry shared by keyboard navigation and the visible SwiftUI layout.
/// Snapshot changes rebuild the index once; held arrows perform constant work.
@MainActor
struct SidebarNavigationLayout {
  static let sectionSpacing: CGFloat = 10
  var apps: [App] = []
  var frames: [App.Bundle.Identifier: CGRect] = [:]
  private var indexes: [App.Bundle.Identifier: Int] = [:]
  private(set) var contentHeight: CGFloat = 0

  init() {}

  init(snapshot: AppListSnapshot) {
    for group in snapshot.sections {
      contentHeight += VisualMetrics.sectionHeaderHeight + Self.sectionSpacing
      for app in group.apps {
        indexes[app.identifier] = apps.count
        apps.append(app)
        frames[app.identifier] = CGRect(
          x: 0, y: contentHeight,
          width: VisualMetrics.sidebarIdealWidth, height: VisualMetrics.appRowHeight)
        contentHeight += VisualMetrics.appRowHeight
      }
    }
  }

  func next(after identifier: App.Bundle.Identifier?, down: Bool) -> App? {
    guard !apps.isEmpty else { return nil }
    guard let identifier, let index = indexes[identifier] else { return apps.first }
    return apps[min(apps.count - 1, max(0, index + (down ? 1 : -1)))]
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
}
