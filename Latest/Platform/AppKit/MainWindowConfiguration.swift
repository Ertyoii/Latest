//
//  MainWindowConfiguration.swift
//  Latest
//
//  Structural split from the original implementation.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-29.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit

/// Keeps the titlebar joined to the attached sidebar and detail surfaces.
@MainActor
enum MainWindowConfiguration {
  static func apply(to window: NSWindow) {
    window.titlebarSeparatorStyle = .none
  }
}
