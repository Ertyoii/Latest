//
//  UpdateSectionHeaderView.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit

final class LegacyUpdateSectionHeaderContentView: NSView {
	private static let numberFormatter = NumberFormatter()
	private let titleField = NSTextField(labelWithString: "")

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setupView()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupView()
	}

	func update(section: AppListSnapshot.Section) {
		let count = Self.numberFormatter.string(from: section.numberOfApps as NSNumber) ?? "0"
		let format = NSLocalizedString(
			"SectionTitle",
			comment: "The title of a section divider in the app list. The first placeholder is the name of the section. The value in paranthesis describes how many apps are in that section, number of apps is inserted in the second placeholder. Use the HTML underline tag <u> to mark the deemphasized part of the text, which should be the count. Example: 'Installed Apps (42)'"
		)
		let sectionText = String(format: format, section.title, count)

		guard let htmlData = sectionText.data(using: .utf8),
			  let text = try? NSAttributedString(data: htmlData, options: [
				.documentType: NSAttributedString.DocumentType.html,
				.characterEncoding: String.Encoding.utf8.rawValue
			  ], documentAttributes: nil) else {
			titleField.stringValue = section.title
			return
	}

		var countRange = NSRange(location: 0, length: 0)
		text.enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: text.length)) { value, range, stop in
			if value != nil {
				countRange = range
				stop.pointee = true
			}
		}

		let formattedText = NSMutableAttributedString(string: text.string)
		formattedText.addAttributes([
			.foregroundColor: NSColor.secondaryLabelColor,
			.font: NSFont.systemFont(ofSize: 13, weight: .medium)
		], range: NSRange(location: 0, length: formattedText.length))
		formattedText.setAttributes([
			.foregroundColor: NSColor.tertiaryLabelColor,
			.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize(for: .small))
		], range: countRange)
		titleField.attributedStringValue = formattedText
	}

	private func setupView() {
		wantsLayer = true
		layer?.backgroundColor = NSColor.clear.cgColor

		titleField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
		titleField.textColor = .secondaryLabelColor
		titleField.lineBreakMode = .byTruncatingTail
		titleField.maximumNumberOfLines = 1
		titleField.translatesAutoresizingMaskIntoConstraints = false
		addSubview(titleField)

		NSLayoutConstraint.activate([
			titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
			titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -38),
			titleField.topAnchor.constraint(equalTo: topAnchor, constant: 5),
			titleField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
			])
		}
}
