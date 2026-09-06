//
//  UpdateRowView.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit

@MainActor
final class AppKitUpdateRowContentView: NSTableCellView {
  enum Layout {
    static let leftInset: CGFloat = 10
    static let rightInset: CGFloat = 32
    static let iconSize: CGFloat = 50
    static let iconTextSpacing: CGFloat = 8
    static let trailingWidth: CGFloat = 59
    static let statusSize: CGFloat = 16

  }

  var onSelect: (() -> Void)?
  private var updating: any AppUpdating = AppUpdateService.shared

  private let iconView = NSImageView()
  private let nameField = NSTextField(labelWithString: "")
  private let currentVersionField = NSTextField(labelWithString: "")
  private let newVersionField = NSTextField(labelWithString: "")
  private let dateField = NSTextField(labelWithString: "")
  private let updateButton = UpdateButton(frame: .zero)
  private let supportStateImageView = NSImageView()
  private let separator = NSBox()
  private var representedIdentifier: App.Bundle.Identifier?
  private var observedIdentifier: App.Bundle.Identifier?
  private var updateStateTask: Task<Void, Never>?
  private var displaysAsSelected = false

  override var backgroundStyle: NSView.BackgroundStyle {
    didSet {
      updateTextColors()
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  deinit {
    updateStateTask?.cancel()
  }

  func update(
    app: App,
    isSelected: Bool,
    filterQuery: String?,
    dateFormatter: DateFormatter,
    showsSupportStatusOverride: Bool? = nil,
    updating: any AppUpdating = AppUpdateService.shared
  ) {
    if self.updating !== updating {
      updateStateTask?.cancel()
      observedIdentifier = nil
    }
    self.updating = updating
    updateButton.updating = updating
    updateTitle(for: app, filterQuery: filterQuery)

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
    updateSupportState(for: app, showsSupportStatusOverride: showsSupportStatusOverride)
    updateSelection(isSelected)
    updateIcon(for: app)
    setAccessibilityLabel(
      SidebarInteractionPolicy.accessibilityLabel(for: app, dateFormatter: dateFormatter))
    setAccessibilitySelected(isSelected)
  }

  private func setupView() {
    setAccessibilityElement(true)
    setAccessibilityRole(.group)

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
    dateField.translatesAutoresizingMaskIntoConstraints = false
    addSubview(dateField)

    updateButton.cell = UpdateButtonCell()
    updateButton.target = updateButton
    updateButton.action = #selector(UpdateButton.performAction(_:))
    updateButton.isBordered = false
    updateButton.contentTintColor = UpdateButton.Style.tintColor
    updateButton.showActionButton = false
    updateButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(updateButton)

    supportStateImageView.imageScaling = .scaleProportionallyDown
    supportStateImageView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(supportStateImageView)

    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    addSubview(separator)

    let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(selectRow(_:)))
    addGestureRecognizer(clickRecognizer)

    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.leftInset),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: Layout.iconSize),
      iconView.heightAnchor.constraint(equalToConstant: Layout.iconSize),

      textStack.leadingAnchor.constraint(
        equalTo: iconView.trailingAnchor, constant: Layout.iconTextSpacing),
      textStack.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
      textStack.trailingAnchor.constraint(lessThanOrEqualTo: dateField.trailingAnchor),
      nameField.trailingAnchor.constraint(lessThanOrEqualTo: dateField.leadingAnchor),

      dateField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.rightInset),
      dateField.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      dateField.widthAnchor.constraint(equalToConstant: Layout.trailingWidth),

      updateButton.trailingAnchor.constraint(equalTo: dateField.trailingAnchor),
      updateButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      updateButton.widthAnchor.constraint(equalToConstant: Layout.trailingWidth),
      updateButton.heightAnchor.constraint(equalToConstant: 24),

      supportStateImageView.trailingAnchor.constraint(equalTo: dateField.trailingAnchor),
      supportStateImageView.topAnchor.constraint(equalTo: topAnchor, constant: 19),
      supportStateImageView.widthAnchor.constraint(equalToConstant: Layout.statusSize),
      supportStateImageView.heightAnchor.constraint(equalToConstant: Layout.statusSize),

      separator.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: dateField.trailingAnchor),
      separator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0.5),
    ])
  }

  private func updateTitle(for app: App, filterQuery: String?) {
    let title = NSMutableAttributedString(attributedString: app.highlightedName(for: filterQuery))
    title.addAttribute(
      .font, value: NSFont.systemFont(ofSize: 13, weight: .semibold),
      range: NSRange(location: 0, length: title.length))
    nameField.attributedStringValue = title
  }

  private func updateIcon(for app: App) {
    guard representedIdentifier != app.identifier else { return }
    representedIdentifier = app.identifier
    iconView.image = IconCache.shared.iconImmediately(for: app)
  }

  private var showsSupportStatusOverride: Bool?

  private func updateSupportState(for app: App, showsSupportStatusOverride: Bool? = nil) {
    if let showsSupportStatusOverride {
      self.showsSupportStatusOverride = showsSupportStatusOverride
    }
    let showSupportState =
      self.showsSupportStatusOverride
      ?? true
    let isUpdating =
      switch updating.state(for: app.identifier) {
      case .none, .error: false
      default: true
      }

    supportStateImageView.isHidden = !showSupportState || isUpdating
    if showSupportState {
      supportStateImageView.image = app.source.supportState.statusImage
      supportStateImageView.toolTip = app.source.supportState.label
    }
  }

  private func updateSelection(_ isSelected: Bool) {
    displaysAsSelected = isSelected
    separator.isHidden = isSelected
    updateTextColors()
  }

  private func updateTextColors() {
    // AppKit changes a selected row from emphasized to normal when focus leaves the table.
    let usesActiveSelectionColors = displaysAsSelected && backgroundStyle == .emphasized
    let titleColor: NSColor =
      usesActiveSelectionColors ? .alternateSelectedControlTextColor : .labelColor
    let textColor: NSColor =
      usesActiveSelectionColors ? .alternateSelectedControlTextColor : .secondaryLabelColor
    let title = NSMutableAttributedString(attributedString: nameField.attributedStringValue)
    if title.length > 0 {
      title.addAttribute(
        .foregroundColor, value: titleColor, range: NSRange(location: 0, length: title.length))
      nameField.attributedStringValue = title
    }
    currentVersionField.textColor = textColor
    newVersionField.textColor = textColor
    dateField.textColor = textColor
  }

  private func observeUpdateState(for app: App) {
    guard observedIdentifier != app.identifier else { return }
    updateStateTask?.cancel()
    observedIdentifier = app.identifier
    updateStateTask = Task { [weak self, weak app, updating] in
      guard let app else { return }
      for await _ in updating.states(for: app.identifier) {
        guard !Task.isCancelled, let self else { break }
        self.updateSupportState(for: app)
      }
    }
  }

  @objc private func selectRow(_ sender: NSClickGestureRecognizer) {
    onSelect?()
  }
}
