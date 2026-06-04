//
//  WindowAccessor.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
	let configure: (NSWindow) -> Void

	func makeNSView(context: Context) -> NSView {
		let view = NSView(frame: .zero)
		DispatchQueue.main.async {
			if let window = view.window {
				configure(window)
			}
		}
		return view
	}

	func updateNSView(_ view: NSView, context: Context) {
		DispatchQueue.main.async {
			if let window = view.window {
				configure(window)
			}
		}
	}
}
