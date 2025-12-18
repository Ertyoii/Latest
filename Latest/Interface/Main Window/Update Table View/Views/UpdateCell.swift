//
//  UpdateCell.swift
//  Latest
//
//  Created by Max Langer on 26.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

/**
 The cell that is used in the list of available updates
 */
@MainActor
class UpdateCell: NSTableCellView {
    // MARK: - View Lifecycle

    /// The label displaying the current version of the app
    @IBOutlet private var nameTextField: NSTextField!

    /// The label displaying the current version of the app
    @IBOutlet private var currentVersionTextField: NSTextField!

    /// The label displaying the newest version available for the app
    @IBOutlet private var newVersionTextField: NSTextField!

    /// The stack view holding the cells contents.
    @IBOutlet private var contentStackView: NSStackView!

    /// The constraint defining the leading inset of the content.
    @IBOutlet private var leadingConstraint: NSLayoutConstraint!

    /// Constraint controlling the trailing inset of the cell.
    @IBOutlet private var trailingConstraint: NSLayoutConstraint!

    /// Label displaying the last modified/update date for the app.
    @IBOutlet private var dateTextField: NSTextField!

    /// The button handling the update of the app.
    @IBOutlet private var updateButton: UpdateButton!

    /// Image view displaying a status indicator for the support status of the app.
    @IBOutlet private var supportStateImageView: NSImageView!

    override func awakeFromNib() {
        super.awakeFromNib()

        Task { @MainActor [weak self] in
            self?.leadingConstraint.constant = 0
            self?.trailingConstraint.constant = 0
        }
    }

    // MARK: - Update Progress

    /// The app represented by this cell
    var app: App? {
        willSet {
            // Remove observer from existing app
            if let app {
                UpdateQueue.shared.removeObserver(self, for: app.identifier)
            }
        }

        didSet {
            if let app {
                UpdateQueue.shared.addObserver(self, to: app.identifier) { [weak self] _ in
                    guard let self else { return }
                    supportStateImageView.isHidden = !showSupportState
                }
            }

            updateButton.app = app
            updateContents()
        }
    }

    var filterQuery: String? {
        didSet {
            if filterQuery != oldValue {
                updateTitle()
            }
        }
    }

    // MARK: - Utilities

    /// A date formatter for preparing the update date.
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .none
        dateFormatter.dateStyle = .short
        dateFormatter.doesRelativeDateFormatting = true

        return dateFormatter
    }()

    private func updateContents() {
        guard let app, let versionInformation = app.localizedVersionInformation else { return }

        updateTitle()

        // Update the contents of the cell
        currentVersionTextField.stringValue = versionInformation.current
        newVersionTextField.stringValue = versionInformation.new ?? ""
        newVersionTextField.isHidden = !app.updateAvailable
        dateTextField.stringValue = dateFormatter.string(from: app.updateDate)

        // Support state
        supportStateImageView.isHidden = !showSupportState
        if showSupportState {
            supportStateImageView.image = app.source.supportState.statusImage
            supportStateImageView.toolTip = app.source.supportState.label
        }
    }

    /// Whether the status indicator for the apps support state should be visible.
    private var showSupportState: Bool {
        guard let app else { return false }

        let isUpdating = switch UpdateQueue.shared.state(for: app.identifier) {
        case .none, .error: false
        default: true
        }

        return !isUpdating && (AppListSettings.shared.includeAppsWithLimitedSupport || AppListSettings.shared.includeUnsupportedApps)
    }

    private func updateTitle() {
        nameTextField.attributedStringValue = app?.highlightedName(for: filterQuery) ?? NSAttributedString()
    }
}
