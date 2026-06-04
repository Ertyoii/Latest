//
//  HighlightedAppNameText.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

struct HighlightedAppNameText: NSViewRepresentable {
	let app: App
	let query: String?
	let font: NSFont

	func makeNSView(context: Context) -> NSTextField {
		let field = NSTextField(labelWithString: "")
		field.lineBreakMode = .byTruncatingTail
		field.maximumNumberOfLines = 1
		field.allowsDefaultTighteningForTruncation = true
		field.font = font
		return field
	}

	func updateNSView(_ field: NSTextField, context: Context) {
		let text = NSMutableAttributedString(attributedString: app.highlightedName(for: query))
		text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))
		field.attributedStringValue = text
	}
}
