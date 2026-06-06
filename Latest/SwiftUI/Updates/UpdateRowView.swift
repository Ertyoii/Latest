//
//  UpdateRowView.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit

@MainActor
final class LegacyUpdateRowContentView: NSTableCellView {
	private enum Metrics {
		static let leftInset: CGFloat = 10
		static let selectionLeadingInset: CGFloat = 6
		static let selectionTrailingInset: CGFloat = 20
		static let rightInset: CGFloat = 32
		static let iconSize: CGFloat = 50
		static let iconTextSpacing: CGFloat = 8
		static let trailingWidth: CGFloat = 59
		static let trailingHeight: CGFloat = 61
		static let supportStateVerticalOffset: CGFloat = -30
	}

	var onSelect: (() -> Void)?

	private let iconView = NSImageView()
	private let nameField = NSTextField(labelWithString: "")
	private let currentVersionField = NSTextField(labelWithString: "")
	private let newVersionField = NSTextField(labelWithString: "")
	private let dateField = NSTextField(labelWithString: "")
	private let updateButton = UpdateButton(frame: .zero)
	private let supportStateImageView = NSImageView()
	private let selectionBackground = NSBox()
	private let separator = NSBox()
	private var representedIdentifier: App.Bundle.Identifier?
	private var observedIdentifier: App.Bundle.Identifier?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setupView()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupView()
	}

	deinit {
		if let observedIdentifier {
			UpdateQueue.shared.removeObserver(self, for: observedIdentifier)
		}
	}

	func update(app: App, isSelected: Bool, drawsSelectionBackground: Bool, filterQuery: String?, dateFormatter: DateFormatter) {
		updateTitle(for: app, filterQuery: filterQuery, isSelected: isSelected)

		if let versionInformation = app.localizedVersionInformation {
			currentVersionField.stringValue = versionInformation.current
			newVersionField.stringValue = versionInformation.new ?? ""
			newVersionField.isHidden = !app.updateAvailable
		} else {
			currentVersionField.stringValue = ""
			newVersionField.stringValue = ""
			newVersionField.isHidden = true
		}

		dateField.stringValue = dateFormatter.string(from: app.updateDate)
		updateButton.app = app
		observeUpdateState(for: app)
		updateSupportState(for: app)
		updateSelection(isSelected, drawsSelectionBackground: drawsSelectionBackground)
		updateIcon(for: app)
	}

	private func setupView() {
		selectionBackground.boxType = .custom
		selectionBackground.cornerRadius = 6
		selectionBackground.fillColor = .controlAccentColor
		selectionBackground.borderColor = .clear
		selectionBackground.translatesAutoresizingMaskIntoConstraints = false
		selectionBackground.isHidden = true
		addSubview(selectionBackground)

		iconView.imageScaling = .scaleProportionallyUpOrDown
		iconView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(iconView)
		self.imageView = iconView

		nameField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
		nameField.textColor = .labelColor
		nameField.lineBreakMode = .byTruncatingTail
		nameField.maximumNumberOfLines = 1
		nameField.allowsDefaultTighteningForTruncation = true

		currentVersionField.font = NSFont.systemFont(ofSize: 11)
		currentVersionField.textColor = .secondaryLabelColor
		currentVersionField.lineBreakMode = .byTruncatingTail
		currentVersionField.maximumNumberOfLines = 1

		newVersionField.font = NSFont.systemFont(ofSize: 11)
		newVersionField.textColor = .secondaryLabelColor
		newVersionField.lineBreakMode = .byTruncatingTail
		newVersionField.maximumNumberOfLines = 1

		let textStack = NSStackView(views: [nameField, currentVersionField, newVersionField])
		textStack.orientation = .vertical
		textStack.alignment = .leading
		textStack.spacing = 0
		textStack.detachesHiddenViews = true
		textStack.setContentHuggingPriority(.required, for: .vertical)
		textStack.setContentCompressionResistancePriority(.required, for: .vertical)
		textStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(textStack)

		dateField.font = NSFont.preferredFont(forTextStyle: .callout, options: [:])
		dateField.textColor = .secondaryLabelColor
		dateField.lineBreakMode = .byClipping
		dateField.alignment = .right
		dateField.setContentHuggingPriority(.defaultHigh, for: .horizontal)

		updateButton.cell = UpdateButtonCell()
		updateButton.target = updateButton
		updateButton.action = #selector(UpdateButton.performAction(_:))
		updateButton.isBordered = false
		updateButton.contentTintColor = UpdateButton.Style.tintColor
		updateButton.showActionButton = false
		updateButton.translatesAutoresizingMaskIntoConstraints = false

		supportStateImageView.imageScaling = .scaleProportionallyDown
		supportStateImageView.translatesAutoresizingMaskIntoConstraints = false

		let supportStateContainer = NSView()
		supportStateContainer.translatesAutoresizingMaskIntoConstraints = false
		supportStateContainer.addSubview(supportStateImageView)

		let trailingStack = NSStackView(views: [dateField, updateButton, supportStateContainer])
		trailingStack.orientation = .vertical
		trailingStack.alignment = .trailing
		trailingStack.distribution = .equalSpacing
		trailingStack.spacing = 0
		trailingStack.detachesHiddenViews = true
		trailingStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(trailingStack)

		separator.boxType = .separator
		separator.translatesAutoresizingMaskIntoConstraints = false
		addSubview(separator)

		let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(selectRow(_:)))
		addGestureRecognizer(clickRecognizer)

		NSLayoutConstraint.activate([
			selectionBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.selectionLeadingInset),
			selectionBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.selectionTrailingInset),
			selectionBackground.topAnchor.constraint(equalTo: topAnchor, constant: 2),
			selectionBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.leftInset),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
			iconView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

			textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Metrics.iconTextSpacing),
			textStack.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
			textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -8),

			trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.rightInset),
			trailingStack.centerYAnchor.constraint(equalTo: centerYAnchor),
			trailingStack.widthAnchor.constraint(equalToConstant: Metrics.trailingWidth),
			trailingStack.heightAnchor.constraint(equalToConstant: Metrics.trailingHeight),
			separator.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: trailingStack.trailingAnchor),
			separator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1.5),

			updateButton.widthAnchor.constraint(equalToConstant: Metrics.trailingWidth),
			updateButton.heightAnchor.constraint(equalToConstant: 24),
			supportStateContainer.widthAnchor.constraint(equalToConstant: 16),
			supportStateContainer.heightAnchor.constraint(equalToConstant: 16),
			supportStateImageView.trailingAnchor.constraint(equalTo: supportStateContainer.trailingAnchor),
			supportStateImageView.topAnchor.constraint(equalTo: supportStateContainer.topAnchor, constant: Metrics.supportStateVerticalOffset),
			supportStateImageView.widthAnchor.constraint(equalToConstant: 16),
			supportStateImageView.heightAnchor.constraint(equalToConstant: 16)
		])
	}

	private func updateTitle(for app: App, filterQuery: String?, isSelected: Bool) {
		let title = NSMutableAttributedString(attributedString: app.highlightedName(for: filterQuery))
		title.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: NSRange(location: 0, length: title.length))
		title.addAttribute(.foregroundColor, value: isSelected ? NSColor.selectedControlTextColor : NSColor.labelColor, range: NSRange(location: 0, length: title.length))
		nameField.attributedStringValue = title
	}

	private func updateIcon(for app: App) {
		guard representedIdentifier != app.identifier else { return }
		representedIdentifier = app.identifier
		IconCache.shared.icon(for: app) { [weak self] image in
			guard self?.representedIdentifier == app.identifier else { return }
			self?.iconView.image = image
		}
	}

	private func updateSupportState(for app: App) {
		let showSupportState = AppListSettings.shared.includeAppsWithLimitedSupport || AppListSettings.shared.includeUnsupportedApps
		let isUpdating = switch UpdateQueue.shared.state(for: app.identifier) {
		case .none, .error: false
		default: true
		}

		supportStateImageView.isHidden = !showSupportState || isUpdating
		if showSupportState {
			supportStateImageView.image = app.source.supportState.statusImage
			supportStateImageView.toolTip = app.source.supportState.label
		}
	}

	private func updateSelection(_ isSelected: Bool, drawsSelectionBackground: Bool) {
		selectionBackground.fillColor = .controlAccentColor
		selectionBackground.isHidden = !drawsSelectionBackground || !isSelected
		separator.isHidden = isSelected
		let textColor: NSColor = isSelected ? .selectedControlTextColor : .secondaryLabelColor
		currentVersionField.textColor = textColor
		newVersionField.textColor = textColor
		dateField.textColor = textColor
	}

	private func observeUpdateState(for app: App) {
		guard observedIdentifier != app.identifier else { return }

		if let observedIdentifier {
			UpdateQueue.shared.removeObserver(self, for: observedIdentifier)
		}

		observedIdentifier = app.identifier
		UpdateQueue.shared.addObserver(self, to: app.identifier) { [weak self, weak app] _ in
			guard let self, let app else { return }
			self.updateSupportState(for: app)
		}
	}

	@objc private func selectRow(_ sender: NSClickGestureRecognizer) {
		onSelect?()
	}
}
