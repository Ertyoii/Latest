//
//  MainWindowConfiguration.swift
//  Latest
//
//  Structural split from the original implementation.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-29.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit

/// Applies the window behavior SwiftUI does not currently expose. System-owned
/// split-view and Liquid Glass surfaces are deliberately left untouched.
@MainActor
enum MainWindowConfiguration {
  static func apply(to window: NSWindow) {
    window.titlebarSeparatorStyle = .none
  }
}
