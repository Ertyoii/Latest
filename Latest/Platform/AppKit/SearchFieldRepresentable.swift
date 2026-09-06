//
//  SearchFieldRepresentable.swift
//  Latest
//
//  Created by ertyoii on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-06-04.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI

/// A deliberately narrow bridge for the sidebar-local search control. macOS
/// SwiftUI's searchable modifier moves the field into toolbar chrome and does
/// not preserve the app's established geometry or Escape focus restoration.
final class UpdateSearchField: NSSearchField {
  weak var previousFirstResponder: NSResponder?

  func requestFocus() {
    guard let window else { return }
    if window.firstResponder !== self,
      window.firstResponder !== currentEditor()
    {
      if let fieldEditor = window.firstResponder as? NSTextView,
        let control = fieldEditor.delegate as? NSControl
      {
        previousFirstResponder = control
      } else {
        previousFirstResponder = window.firstResponder
      }
    }
    window.makeFirstResponder(self)
  }

  func resignFocus(restoringPreviousResponder: Bool) {
    guard let window else { return }
    let previousResponder = previousFirstResponder
    previousFirstResponder = nil
    if restoringPreviousResponder,
      let previousResponder,
      previousResponder !== self,
      window.makeFirstResponder(previousResponder)
    {
      return
    }
    window.makeFirstResponder(nil)
  }

  override func cancelOperation(_ sender: Any?) {
    resignFocus(restoringPreviousResponder: true)
  }
}

struct SearchFieldRepresentable: NSViewRepresentable {
  @Binding var text: String
  @ObservedObject var focusController: SearchFocusController
  let onTextChanged: (String) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> UpdateSearchField {
    let field = UpdateSearchField()
    field.controlSize = .large
    field.delegate = context.coordinator
    field.target = context.coordinator
    field.action = #selector(Coordinator.searchFieldAction(_:))
    field.focusRingType = .none
    field.sendsSearchStringImmediately = true
    field.sendsWholeSearchString = false
    field.setAccessibilityIdentifier("updates.search")
    field.setAccessibilityLabel("Search Apps")
    if let cell = field.cell as? NSSearchFieldCell {
      cell.controlSize = .large
      cell.bezelStyle = .roundedBezel
      cell.isScrollable = true
      cell.lineBreakMode = .byClipping
      cell.sendsSearchStringImmediately = true
    }
    context.coordinator.applyFocusRequest(to: field)
    return field
  }

  func updateNSView(_ field: UpdateSearchField, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != text {
      field.stringValue = text
    }
    context.coordinator.applyFocusRequest(to: field)
  }

  @MainActor
  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: SearchFieldRepresentable
    private var appliedFocusRequest: SearchFocusController.Request = .none

    init(_ parent: SearchFieldRepresentable) {
      self.parent = parent
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSSearchField else { return }
      parent.onTextChanged(field.stringValue)
    }

    @objc func searchFieldAction(_ sender: NSSearchField) {
      parent.onTextChanged(sender.stringValue)
    }

    func applyFocusRequest(to field: UpdateSearchField) {
      let request = parent.focusController.request
      guard request != appliedFocusRequest else { return }
      appliedFocusRequest = request
      switch request {
      case .none:
        break
      case .focus:
        field.requestFocus()
      case .resign:
        field.resignFocus(restoringPreviousResponder: true)
      }
    }
  }
}
