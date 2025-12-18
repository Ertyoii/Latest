//
//  ReleaseNotesViewController.swift
//  Latest
//
//  Created by Max Langer on 26.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa
import WebKit

/// The container for release notes content
private enum ReleaseNotesContent {
    /// The possible values when loading release notes content
    enum ContentType {
        /// The release notes view should display a loading indicator.
        case loading

        /// The release notes should display an error.
        case error

        /// Release notes contents should be displayed.
        case text

        /// Whether the currently displayed content is scrollable.
        var isScrollable: Bool {
            switch self {
            case .loading, .error:
                false

            case .text:
                true
            }
        }
    }

    /// The loading screen, presenting an activity indicator
    case loading(ReleaseNotesLoadingViewController?)

    /// The error screen, explaining what went wrong
    case error(ReleaseNotesErrorViewController?)

    /// The actual content
    case text(ReleaseNotesTextViewController?)

    /// Exposes the view controller holding the release notes, if available.
    var textController: ReleaseNotesTextViewController? {
        switch self {
        case let .text(controller):
            controller
        default:
            nil
        }
    }

    /// Exposes the view controller indicating a loading action, if available.
    var loadingController: ReleaseNotesLoadingViewController? {
        switch self {
        case let .loading(controller):
            controller
        default:
            nil
        }
    }

    /// Exposes the view controller holding an error, if available.
    var errorController: ReleaseNotesErrorViewController? {
        switch self {
        case let .error(controller):
            controller
        default:
            nil
        }
    }

    /// Returns the current view controller
    var controller: NSViewController? {
        switch self {
        case let .loading(controller):
            controller
        case let .error(controller):
            controller
        case let .text(controller):
            controller
        }
    }
}

/**
 This is a super rudimentary implementation of an release notes viewer.
 It can open urls or display HTML strings right away.
 */
class ReleaseNotesViewController: NSViewController {
    @IBOutlet var appInfoBackgroundView: NSVisualEffectView!
    @IBOutlet var appInfoContentView: NSStackView!

    @IBOutlet var updateButton: UpdateButton!
    @IBOutlet var externalUpdateLabel: NSTextField!

    @IBOutlet var appNameTextField: NSTextField!
    @IBOutlet var appDateTextField: NSTextField!
    @IBOutlet var appVersionTextField: NSTextField!
    @IBOutlet var appIconImageView: NSImageView!

    /// Button indicating the support state of a given app.
    @IBOutlet private var supportStateButton: NSButton!

    private let releaseNotesProvider = ReleaseNotesProvider()

    /// The app currently presented
    private(set) var app: App? {
        didSet {
            // Forward app
            updateButton.app = app
        }
    }

    /// The current content presented on screen
    private var content: ReleaseNotesContent?

    // MARK: - View Lifecycle

    override func viewWillAppear() {
        super.viewWillAppear()

        let constraint = NSLayoutConstraint(item: appInfoContentView!, attribute: .top, relatedBy: .equal, toItem: view.window?.contentLayoutGuide, attribute: .top, multiplier: 1.0, constant: 0)
        constraint.isActive = true

        setEmptyState()
    }

    // MARK: - Actions

    @objc func update(_: NSButton) {
        app?.performUpdate()
    }

    @objc func cancelUpdate(_: NSButton) {
        app?.cancelUpdate()
    }

    // MARK: - Display Methods

    /**
     Loads the content of the URL and displays them
     - parameter content: The content to be displayed
     */
    func display(releaseNotesFor app: App?) {
        // Cancel existing task
        loadingTask?.cancel()
        loadingTask = nil

        guard let app else {
            setEmptyState()
            return
        }

        display(app)

        loadingTask = Task { @MainActor [weak self] in
            // Delay the loading screen to avoid flickering
            try? await Task.sleep(nanoseconds: 200_000_000)

            guard !Task.isCancelled else { return }
            self?.loadContent(.loading)

            do {
                for try await content in self?.releaseNotesProvider.releaseNotes(for: app) ?? .init(unfolding: { nil }) {
                    self?.update(with: content.attributedString)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.show(error)
            }
        }
    }

    /// The current loading task.
    private var loadingTask: Task<Void, Never>?

    // MARK: - User Interface Stuff

    /// Date formatter used to display the apps update date.
    private lazy var appDateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        return dateFormatter
    }()

    private func display(_ app: App) {
        // Update header
        appInfoBackgroundView.isHidden = false
        self.app = app
        appNameTextField.stringValue = app.name

        // Version Information
        if let versionInformation = app.localizedVersionInformation {
            appVersionTextField.stringValue = versionInformation.combined(includeNew: app.updateAvailable)
        }

        // Support state
        supportStateButton.isHidden = !(AppListSettings.shared.includeUnsupportedApps || AppListSettings.shared.includeAppsWithLimitedSupport)
        if !supportStateButton.isHidden {
            supportStateButton.title = app.source.supportState.compactLabel
            supportStateButton.image = app.source.supportState.statusImage
        }

        // Icon
        IconCache.shared.icon(for: app) { image in
            self.appIconImageView.image = image
        }

        // Date
        if let date = app.latestUpdateDate {
            appDateTextField.stringValue = appDateFormatter.string(from: date)
            appDateTextField.isHidden = false
        } else {
            appDateTextField.isHidden = true
        }

        // Update Action
        if app.updateAvailable, let name = app.externalUpdaterName {
            externalUpdateLabel.stringValue = String(format: NSLocalizedString("ExternalUpdateActionWithAppName", comment: "An explanatory text indicating where the update will be performed. The placeholder will be filled with the name of the external updater (App Store, App Name). The text will appear below the Update button, so that it reads: \"Update in XY\""), name)
        } else {
            externalUpdateLabel.stringValue = ""
        }

        updateInsets()
    }

    private func setEmptyState() {
        app = nil

        // Prepare for empty state
        let error = LatestError.custom(title: NSLocalizedString("NoAppSelectedTitle", comment: "Title of release notes empty state"),
                                       description: NSLocalizedString("NoAppSelectedDescription", comment: "Description of release notes empty state"))
        show(error)

        appInfoBackgroundView.isHidden = true
    }

    private func loadContent(_ type: ReleaseNotesContent.ContentType) {
        // Remove the old content
        if let oldController = content?.controller {
            oldController.view.removeFromSuperview()
            oldController.removeFromParent()
        }

        initializeContent(of: type)

        guard let controller = content?.controller else { return }
        let view = controller.view

        addChild(controller)
        self.view.addSubview(view, positioned: .below, relativeTo: self.view.subviews.first)
        view.translatesAutoresizingMaskIntoConstraints = false

        let topAnchor = type.isScrollable || app == nil ? self.view.topAnchor : appInfoBackgroundView.bottomAnchor

        var constraints = [NSLayoutConstraint]()

        constraints.append(topAnchor.constraint(equalTo: view.topAnchor, constant: 0))
        constraints.append(self.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0))
        constraints.append(self.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0))
        constraints.append(self.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0))

        NSLayoutConstraint.activate(constraints)

        updateInsets()
    }

    private func initializeContent(of type: ReleaseNotesContent.ContentType) {
        switch type {
        case .loading:
            let controller = ReleaseNotesLoadingViewController.fromStoryboard()
            content = .loading(controller)
        case .error:
            let controller = ReleaseNotesErrorViewController.fromStoryboard()
            content = .error(controller)
        case .text:
            let controller = ReleaseNotesTextViewController.fromStoryboard()
            content = .text(controller)
        }
    }

    /// This method unwraps the data into a string, that is then formatted and displayed.
    ///
    /// - parameter data: The data to be displayed. It has to be some text or HTML, other types of data will result in an error message displayed to the user
    private func update(with string: NSAttributedString) {
        loadContent(.text)
        content?.textController?.set(string)
        updateInsets()
    }

    /// Updates the top inset of the release notes scrollView
    private func updateInsets() {
        let inset = appInfoBackgroundView.frame.size.height
        content?.textController?.updateInsets(with: inset)
    }

    /// Switches the content to error and displays the localized error
    private func show(_ error: Error) {
        loadContent(.error)
        content?.errorController?.show(error)
    }

    // MARK: - Navigation

    override func prepare(for segue: NSStoryboardSegue, sender _: Any?) {
        switch segue.identifier {
        case "presentSupportStateInfo":
            guard let controller = segue.destinationController as? SupportStatusInfoViewController else { fatalError("Unknown controller for segue \(String(describing: segue.identifier))") }
            controller.app = app
        default:
            break
        }
    }
}
