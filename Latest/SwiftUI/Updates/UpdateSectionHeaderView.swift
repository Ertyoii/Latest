//
//  UpdateSectionHeaderView.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import SwiftUI

struct UpdateSectionHeaderView: View {
	let section: AppListSnapshot.Section

	var body: some View {
		Text(localizedTitle)
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(.secondary)
			.lineLimit(1)
			.textCase(nil)
	}

	private var localizedTitle: String {
		let count = NumberFormatter.localizedString(
			from: NSNumber(value: section.numberOfApps),
			number: .none
		)
		let format = NSLocalizedString(
			"SectionTitle",
			comment: "The title of a section divider in the app list."
		)
		return String(format: format, section.title, count)
			.replacingOccurrences(of: "<u>", with: "")
			.replacingOccurrences(of: "</u>", with: "")
	}
}
