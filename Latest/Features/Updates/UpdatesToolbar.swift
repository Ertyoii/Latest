//
//  UpdatesToolbar.swift
//  Latest
//
//  Structural split from the original implementation.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-29.
//  Licensed under GPL-3.0; see LICENSE.md.

import SwiftUI

/// Observe scan progress at the toolbar boundary, without invalidating the app list.
struct UpdatesToolbar: ToolbarContent {
  @ObservedObject var service: UpdateCheckingService
  let reload: () -> Void

  var body: some ToolbarContent {
    ToolbarSpacer(.flexible, placement: .primaryAction)
    ToolbarItem(placement: .primaryAction) {
      ToolbarUpdateProgressView(
        presentation: ToolbarProgressPresentation(
          isRunning: service.isRunning, fraction: service.progressFraction))
    }
    ToolbarItem(placement: .primaryAction) {
      RefreshToolbarButton(isEnabled: !service.isRunning, action: reload)
    }
  }
}

struct RefreshToolbarButton: View {
  let isEnabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label("Check for Updates", systemImage: "arrow.clockwise")
    }
    .labelStyle(.iconOnly)
    .help(
      NSLocalizedString(
        "CheckForUpdatesToolbarItemToolTip",
        comment: "Tool tip of a toolbar button that checks for updates"
      )
    )
    .disabled(!isEnabled)
    .accessibilityIdentifier("toolbar.refresh")
    .accessibilityLabel("Check for Updates")
  }
}

enum ToolbarProgressPresentation: Equatable {
  case hidden
  case indeterminate
  case determinate(Double)

  init(isRunning: Bool, fraction: Double?) {
    guard isRunning else {
      self = .hidden
      return
    }
    if let fraction {
      self = .determinate(ToolbarProgressMetrics.normalized(fraction))
    } else {
      self = .indeterminate
    }
  }
}

struct ToolbarUpdateProgressView: View {
  let presentation: ToolbarProgressPresentation

  @ViewBuilder
  var body: some View {
    switch presentation {
    case .hidden:
      EmptyView()
    case .indeterminate:
      ProgressView()
        .id(ToolbarProgressMetrics.indeterminateIdentity)
        .controlSize(.small)
        .toolbarProgressFrame()
        .accessibilityLabel("Scanning applications")
    case .determinate(let fraction):
      ProgressView(value: fraction)
        .id(ToolbarProgressMetrics.determinateIdentity)
        .toolbarProgressFrame()
        .accessibilityLabel("Checking for updates")
    }
  }
}

extension View {
  fileprivate func toolbarProgressFrame() -> some View {
    frame(width: ToolbarProgressMetrics.width)
      .padding(.leading, ToolbarProgressMetrics.leadingPadding)
      .padding(.trailing, ToolbarProgressMetrics.trailingPadding)
  }
}

enum ToolbarProgressMetrics {
  static let width: CGFloat = 64
  static let leadingPadding: CGFloat = 10
  static let trailingPadding: CGFloat = 10
  static let determinateIdentity = "toolbar-progress-determinate"
  static let indeterminateIdentity = "toolbar-progress-indeterminate"

  static func normalized(_ fraction: Double) -> Double {
    min(max(fraction, 0), 1)
  }
}
