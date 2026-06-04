//
//  UpdateButtonRepresentable.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

struct UpdateButtonRepresentable: NSViewRepresentable {
	let app: App?
	let showActionButton: Bool

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeNSView(context: Context) -> UpdateButton {
		let button = UpdateButton(frame: .zero)
		button.cell = UpdateButtonCell()
		button.target = button
		button.action = #selector(UpdateButton.performAction(_:))
		button.isBordered = false
		button.contentTintColor = UpdateButton.Style.tintColor
		button.showActionButton = showActionButton
		button.app = app
		context.coordinator.appIdentifier = app?.identifier
		return button
	}

	func updateNSView(_ button: UpdateButton, context: Context) {
		button.showActionButton = showActionButton
		guard context.coordinator.appIdentifier != app?.identifier else { return }
		button.app = app
		context.coordinator.appIdentifier = app?.identifier
	}

	final class Coordinator {
		var appIdentifier: App.Bundle.Identifier?
	}
}
