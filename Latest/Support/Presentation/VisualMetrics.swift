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
	/// The original AppKit table resolves its prototype rows to 60 points at
	/// runtime. Keep the production list on that measured cadence; the former
	/// 65-point synthetic fixture made every following row drift farther down.
	static let appRowHeight: CGFloat = 60
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
	/// System Settings uses a 28pt outer curve and an 8pt visible inset, yielding
	/// a concentric 20pt sidebar curve.
	static let mainWindowCornerRadius: CGFloat = 28
	static let sidebarGlassInset: CGFloat = 8
	/// SwiftUI's window theme reserves 4pt before the content's leading edge,
	/// while the top and bottom content edges align with the visible window.
	/// Compensate in layout so the glass is visibly inset 8pt on every outer edge.
	static let sidebarGlassLeadingCompensation: CGFloat = 4
	static let sidebarGlassLeadingLayoutInset = sidebarGlassInset + sidebarGlassLeadingCompensation
	static let sidebarGlassCornerRadius = mainWindowCornerRadius - sidebarGlassInset
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
	// SwiftUI Text reserves more ascent space than the original NSTextField
	// stack. These measured offsets align the visible glyph baselines while the
	// header, icon, and action retain their native layout frames.
	static let detailMetadataVerticalOffset: CGFloat = -7
	static let detailMetadataLineVerticalCorrection: CGFloat = 1
	static let detailTitleVerticalCorrection: CGFloat = 0
	static let supportStatusHorizontalCorrection: CGFloat = -1
	static let detailUpdateButtonWidth: CGFloat = 59
	static let detailUpdateButtonHeight: CGFloat = 24

	// The original settings label intentionally starts 2pt before the table and
	// one point lower. Keep that small asymmetry explicit instead of changing the
	// native Table's content geometry.
	static let locationsLabelOffset = CGSize(width: -2, height: 1)
}
