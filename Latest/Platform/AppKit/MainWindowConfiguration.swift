//
//  MainWindowConfiguration.swift
//  Latest
//
//  Structural split from the original implementation.
//

import AppKit

/// Applies the window behavior SwiftUI does not currently expose. System-owned
/// split-view and Liquid Glass surfaces are deliberately left untouched.
@MainActor
enum MainWindowConfiguration {
	static func apply(to window: NSWindow) {
		window.titlebarSeparatorStyle = .none
	}
}
