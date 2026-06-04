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
	static let detailMinWidth: CGFloat = 460

	static let appIconSize: CGFloat = 50
	static let detailIconSize: CGFloat = 64

	static let rowHorizontalPadding: CGFloat = 12
	static let rowTextSpacing: CGFloat = 2

	static let detailHeaderHeight: CGFloat = 119
	static let detailHeaderHorizontalPadding: CGFloat = 20
	static let detailUpdateButtonWidth: CGFloat = 59
	static let detailUpdateButtonHeight: CGFloat = 24
}
