//
//  SupportStatusInfoViewController.swift
//  Latest
//
//  Created by Max Langer on 15.02.25.
//  Copyright © 2025 Max Langer. All rights reserved.
//

import Cocoa

/// View explaining the support state of the given app.
class SupportStatusInfoViewController: NSViewController {
    /// The app for which the support state is explained.
    var app: App? {
        didSet {
            guard isViewLoaded else { return }
            updateUI()
        }
    }

    // MARK: - Interface

    @IBOutlet private var statusImageView: NSImageView!
    @IBOutlet private var titleLabel: NSTextField!
    @IBOutlet private var descriptionLabel: NSTextField!

    @IBOutlet private var reportIssueButton: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        updateUI()
    }

    private func updateUI() {
        guard let app else { return }

        statusImageView.image = app.source.supportState.statusImage
        titleLabel.stringValue = app.source.supportState.label

        switch app.source.supportState {
        case .none:
            descriptionLabel.stringValue = NSLocalizedString("NoSupportDescription", comment: "Description for apps without support.")
            reportIssueButton.isHidden = true
        case .limited:
            descriptionLabel.stringValue = NSLocalizedString("LimitedSupportDescription", comment: "Description for apps with limited support.")
            reportIssueButton.isHidden = true
        case .full:
            descriptionLabel.stringValue = NSLocalizedString("FullSupportDescription", comment: "Description for apps with full support.")
            reportIssueButton.isHidden = false
        }
    }

    // MARK: - Actions

    /// Opens the issue page on GitHub.
    @IBAction func reportIssue(_: NSButton) {
        NSWorkspace.shared.open(URL(string: "https://github.com/mangerlahn/Latest/issues")!)
    }
}
