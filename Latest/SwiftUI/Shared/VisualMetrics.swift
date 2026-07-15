//
//  VisualMetrics.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import CoreGraphics

@MainActor
enum VisualMetrics {
	static let appRowHeight: CGFloat = 65
	static let sectionHeaderHeight: CGFloat = 27
	static let listTopInset: CGFloat = 36
	static let scrollBottomInset: CGFloat = 10
	static let releaseNotesTextInset: CGFloat = 14

	static let mainWindowDefaultWidth: CGFloat = 768
	static let mainWindowDefaultHeight: CGFloat = 516
	static let mainWindowMinWidth: CGFloat = 350
	static let mainWindowMinHeight: CGFloat = 300

	static let sidebarMinWidth: CGFloat = 300
	static let sidebarIdealWidth: CGFloat = 308
	static let sidebarGlassInset: CGFloat = 8
	static let sidebarGlassCornerRadius: CGFloat = 20
	static let detailMinWidth: CGFloat = 460

	static let appIconSize: CGFloat = 50
	static let detailIconSize: CGFloat = 64

	static let rowHorizontalPadding: CGFloat = 12
	static let rowTextSpacing: CGFloat = 2

	// The SwiftUI detail host starts below the unified toolbar. The former
	// full-size AppKit host included the 40pt toolbar inset in its 119pt header.
	// Keep the visible header at 79pt and center its 64pt content between the
	// toolbar and release-note separators.
	static let detailHeaderVerticalPadding: CGFloat = 7.5
	static let detailHeaderHeight: CGFloat = detailIconSize + (detailHeaderVerticalPadding * 2)
	static let detailHeaderHorizontalPadding: CGFloat = 24
	static let detailUpdateButtonWidth: CGFloat = 59
	static let detailUpdateButtonHeight: CGFloat = 24
}
