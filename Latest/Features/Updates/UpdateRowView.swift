//
//  UpdateRowView.swift
//  Latest
//
//  Created by ertyoii on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-04.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import Observation
import SwiftUI

/// Presentation of the native table's selection, without rebuilding row content.
@MainActor
@Observable
final class UpdateRowSelection {
  enum Style {
    case unselected, inactive, active
  }
  var style = Style.unselected
  var isSelected: Bool { style != .unselected }
  var usesActiveSelectionColors: Bool { style == .active }
}

struct UpdateRowView: View {
  let app: App
  let selection: UpdateRowSelection
  let showsSupportStatus: Bool
  let updating: any AppUpdating
  private let icon: NSImage
  private let name: AttributedString
  private let versions: App.DisplayableVersionInformation?
  private let formattedDate: AttributedString
  @Environment(\.controlActiveState) private var controlActiveState
  @State private var observedUpdate: ObservedUpdate?

  init(
    app: App, selection: UpdateRowSelection,
    filterQuery: String?, date: String, showsSupportStatus: Bool, updating: any AppUpdating
  ) {
    self.app = app
    self.selection = selection
    self.showsSupportStatus = showsSupportStatus
    self.updating = updating
    icon = IconCache.shared.iconImmediately(for: app)
    var title = AttributedString(app.highlightedName(for: filterQuery))
    // The native row applies selection color to the entire attributed title.
    // Let the SwiftUI foreground style do the same for filtered names.
    title.foregroundColor = nil
    name = title
    versions = app.localizedVersionInformation
    formattedDate = AttributedString(
      NSAttributedString(
        string: date,
        attributes: [.font: NSFont.preferredFont(forTextStyle: .callout, options: [:])]
      ))
  }

  private var observationKey: ObservationKey {
    ObservationKey(app: app.identifier, service: ObjectIdentifier(updating))
  }

  private var isUpdating: Bool {
    if let observedUpdate, observedUpdate.key == observationKey { return observedUpdate.isActive }
    return Self.isActive(updating.state(for: app.identifier))
  }

  private static func isActive(_ state: UpdateProgressState) -> Bool {
    switch state {
    case .none, .error: false
    default: true
    }
  }

  var body: some View {
    HStack(spacing: 8) {
      Image(nsImage: icon)
        .resizable()
        .scaledToFit()
        .frame(width: 50, height: 50)
        .opacity(controlActiveState == .inactive ? 0.5 : 1)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 0) {
        Text(name)
          .font(.system(size: 13, weight: .semibold))
          .modifier(UpdateRowTextStyle(selection: selection, secondary: false))
          .frame(height: 16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.trailing, 59)
        Text(versions?.current ?? "")
          .font(.system(size: 11))
          .modifier(UpdateRowTextStyle(selection: selection, secondary: true))
          .frame(height: 14)
          .frame(maxWidth: .infinity, alignment: .leading)
        if app.updateAvailable, let versions {
          Text(versions.new ?? "")
            .font(.system(size: 11))
            .modifier(UpdateRowTextStyle(selection: selection, secondary: true))
            .frame(height: 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .lineLimit(1)
      .truncationMode(.tail)
    }
    .padding(.trailing, 36)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .topTrailing) {
      Text(formattedDate)
        .modifier(UpdateRowTextStyle(selection: selection, secondary: true))
        .lineLimit(1)
        .frame(width: 59, height: 16, alignment: .trailing)
        .padding(.top, 3.5)
        .padding(.trailing, 35.75)
    }
    .overlay(alignment: .topTrailing) {
      Image(nsImage: app.source.supportState.statusImage)
        .frame(width: 16, height: 16)
        .opacity(showsSupportStatus && !isUpdating ? 1 : 0)
        .help(app.source.supportState.label)
        .accessibilityLabel(app.source.supportState.label)
        .accessibilityHidden(!showsSupportStatus || isUpdating)
        .padding(.top, 19)
        .padding(.trailing, 36)
    }
    .overlay(alignment: .bottom) {
      UpdateRowSeparator(selection: selection)
    }
    .task(id: observationKey) {
      let key = observationKey
      for await state in updating.states(for: app.identifier) {
        guard !Task.isCancelled else { return }
        let value = ObservedUpdate(key: key, isActive: Self.isActive(state))
        if observedUpdate != value { observedUpdate = value }
      }
    }
  }

  private struct ObservationKey: Equatable {
    let app: App.Bundle.Identifier
    let service: ObjectIdentifier
  }

  private struct ObservedUpdate: Equatable {
    let key: ObservationKey
    let isActive: Bool
  }
}

/// Color changes leave the text's content and measured layout untouched.
private struct UpdateRowTextStyle: ViewModifier {
  let selection: UpdateRowSelection
  let secondary: Bool

  func body(content: Content) -> some View {
    content.foregroundStyle(
      Color(
        nsColor: selection.usesActiveSelectionColors
          ? .alternateSelectedControlTextColor : (secondary ? .secondaryLabelColor : .labelColor)))
  }
}

private struct UpdateRowSeparator: View {
  let selection: UpdateRowSelection

  var body: some View {
    Rectangle()
      .fill(Color(nsColor: .separatorColor))
      .frame(height: 1)
      .padding(.leading, 58)
      .padding(.trailing, 36)
      .opacity(selection.isSelected ? 0 : 1)
      .accessibilityHidden(true)
  }
}
