//
//  UpdatesSidebarView.swift
//  Latest
//
//  Created by ertyoii on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-04.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI

struct UpdatesSidebarView: View {
  @ObservedObject var viewModel: UpdatesListViewModel
  @ObservedObject var searchFocusController: SearchFocusController
  let showsSupportStatusOverride: Bool?

  init(
    viewModel: UpdatesListViewModel,
    searchFocusController: SearchFocusController,
    showsSupportStatusOverride: Bool? = nil
  ) {
    self.viewModel = viewModel
    self.searchFocusController = searchFocusController
    self.showsSupportStatusOverride = showsSupportStatusOverride
  }

  var body: some View {
    VStack(spacing: 0) {
      UpdatesSidebarHeaderView(viewModel: viewModel, searchFocusController: searchFocusController)
      UpdatesTableBridge(
        viewModel: viewModel, showsSupportStatusOverride: showsSupportStatusOverride)
    }
    .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea(.container, edges: .top))
  }
}

struct UpdatesSidebarHeaderView: View {
  @ObservedObject var viewModel: UpdatesListViewModel
  @ObservedObject var searchFocusController: SearchFocusController
  @FocusState private var searchIsFocused: Bool
  @State private var focusTracker = SearchFocusTracker()

  var body: some View {
    HStack(spacing: 1) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .frame(width: 16)
        .offset(x: -1.5)
        .accessibilityHidden(true)

      TextField(
        "Search",
        text: Binding(
          get: { viewModel.searchQuery },
          set: viewModel.setSearchQuery
        )
      )
      .textFieldStyle(.plain)
      .font(.system(size: 13))
      .focused($searchIsFocused)
      .accessibilityIdentifier("updates.search")
      .accessibilityLabel("Search Apps")
      .onExitCommand(perform: restorePreviousFocus)

      if !viewModel.searchQuery.isEmpty {
        Button {
          viewModel.setSearchQuery("")
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .offset(x: 2.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear Search")
      }
    }
    .padding(.horizontal, 7)
    .frame(height: 28)
    .glassEffect(.regular, in: .capsule)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(SearchWindowReader(tracker: focusTracker))
    .onChange(of: searchFocusController.request, initial: true) { _, request in
      guard request != nil else { return }
      if !searchIsFocused { focusTracker.rememberFirstResponder() }
      searchIsFocused = true
    }
  }

  private func restorePreviousFocus() {
    searchIsFocused = false
    Task { @MainActor in
      focusTracker.restoreFirstResponder()
    }
  }
}

@MainActor
private final class SearchFocusTracker {
  weak var window: NSWindow?
  weak var previousFirstResponder: NSResponder?

  func rememberFirstResponder() {
    guard let current = window?.firstResponder else { return }
    if let editor = current as? NSTextView, let control = editor.delegate as? NSControl {
      previousFirstResponder = control
    } else {
      previousFirstResponder = current
    }
  }

  func restoreFirstResponder() {
    let previous = previousFirstResponder
    previousFirstResponder = nil
    if let previous, window?.makeFirstResponder(previous) == true { return }
    window?.makeFirstResponder(nil)
  }
}

private struct SearchWindowReader: NSViewRepresentable {
  let tracker: SearchFocusTracker

  func makeNSView(context: Context) -> SearchWindowView { SearchWindowView(tracker: tracker) }
  func updateNSView(_ view: SearchWindowView, context: Context) { view.tracker = tracker }
}

private final class SearchWindowView: NSView {
  var tracker: SearchFocusTracker

  init(tracker: SearchFocusTracker) {
    self.tracker = tracker
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    tracker.window = window
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
