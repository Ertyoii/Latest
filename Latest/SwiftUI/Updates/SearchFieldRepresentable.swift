//
//  SearchFieldRepresentable.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

private final class UpdateSearchField: NSSearchField {
	override func cancelOperation(_ sender: Any?) {
		window?.makeFirstResponder(nil)
	}
}

struct SearchFieldRepresentable: NSViewRepresentable {
	@Binding var text: String
	let focusController: SearchFocusController
	let onTextChanged: (String) -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	func makeNSView(context: Context) -> NSSearchField {
		let field = UpdateSearchField()
		field.controlSize = .large
		field.delegate = context.coordinator
		field.target = context.coordinator
		field.action = #selector(Coordinator.searchFieldAction(_:))
		field.focusRingType = .none
		field.sendsSearchStringImmediately = true
		field.sendsWholeSearchString = false
		if let cell = field.cell as? NSSearchFieldCell {
			cell.controlSize = .large
			cell.bezelStyle = .roundedBezel
			cell.isScrollable = true
			cell.lineBreakMode = .byClipping
			cell.sendsSearchStringImmediately = true
		}
		focusController.searchField = field
		return field
	}

	func updateNSView(_ field: NSSearchField, context: Context) {
		context.coordinator.parent = self
		if field.stringValue != text {
			field.stringValue = text
		}
		if focusController.searchField !== field {
			focusController.searchField = field
		}
	}

	@MainActor
	final class Coordinator: NSObject, NSSearchFieldDelegate {
		var parent: SearchFieldRepresentable

		init(_ parent: SearchFieldRepresentable) {
			self.parent = parent
		}

		func controlTextDidChange(_ notification: Notification) {
			guard let field = notification.object as? NSSearchField else { return }
			parent.text = field.stringValue
			parent.onTextChanged(field.stringValue)
		}

		@objc func searchFieldAction(_ sender: NSSearchField) {
			parent.text = sender.stringValue
			parent.onTextChanged(sender.stringValue)
		}
	}
}
