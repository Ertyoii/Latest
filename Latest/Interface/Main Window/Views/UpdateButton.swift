//
//  UpdateButton.swift
//  Latest
//
//  Created by Max Langer on 1.12.20.
//  Copyright © 2020 Max Langer. All rights reserved.
//

import Cocoa

/// The button controlling and displaying the entire update procedure.
class UpdateButton: NSButton {
    /// Internal state that represents the current display mode
    private enum InterfaceState {
        /// No update progress should be shown.
        case none

        /// A state where the update button should be shown.
        case update

        /// A state where the open button should be shown.
        case open

        /// A progress bar should be shown.
        case progress

        /// An indeterminate progress should be shown.
        case indeterminate

        /// An error should be shown.
        case error

        var contentType: UpdateButtonCell.ContentType {
            switch self {
            case .none:
                .none
            case .update, .open, .error:
                .button
            case .progress:
                .progress
            case .indeterminate:
                .indeterminate
            }
        }
    }

    /// Whether an action button such as "Open" or "Update" should be displayed
    @IBInspectable var showActionButton: Bool = true

    /// The app for which update progress should be displayed.
    var app: App? {
        willSet {
            // Remove observer from existing app
            if let app {
                UpdateQueue.shared.removeObserver(self, for: app.identifier)
            }
        }

        didSet {
            if let app {
                observedAppIdentifier = app.identifier
                UpdateQueue.shared.addObserver(self, to: app.identifier) { [weak self] progress in
                    self?.updateInterface(with: progress)
                }
            } else {
                observedAppIdentifier = nil
                isHidden = true
            }
        }
    }

    /// Tracks the identifier currently observed in `UpdateQueue`.
    private var observedAppIdentifier: App.Bundle.Identifier?

    /// The cell handling the drawing for this button.
    var contentCell: UpdateButtonCell {
        cell as! UpdateButtonCell
    }

    /// The background color for this button. Animatable.
    @objc dynamic var backgroundColor: NSColor = #colorLiteral(red: 0.9488552213, green: 0.9487094283, blue: 0.9693081975, alpha: 1) {
        didSet {
            needsDisplay = true
        }
    }

    /// Temporary reference to the last occurred error.
    private var error: Error?

    // MARK: - Initialization

    override func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            self.target = self
            self.action = #selector(performAction(_:))

            self.isBordered = false
            self.contentTintColor = .controlAccentColor
        }
    }

    deinit {
        if let identifier = self.observedAppIdentifier {
            UpdateQueue.shared.removeObserver(self, for: identifier)
        }
    }

    // MARK: - Interface Updates

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize

        if title.count > 0 {
            size.height = 21
            size.width += 12
        } else {
            size.height = 31
            size.width = size.height
        }

        return size
    }

    /// Updates the UI state with the given progress definition.
    private func updateInterface(with state: UpdateOperation.ProgressState) {
        switch state {
        case .none:
            if let app, showActionButton {
                updateInterfaceVisibility(with: app.updateAvailable ? .update : .open)
            } else {
                updateInterfaceVisibility(with: .none)
            }

        case .pending:
            updateInterfaceVisibility(with: .indeterminate)
            toolTip = NSLocalizedString("WaitingUpdateStatus", comment: "Update progress state of waiting to start an update")

        case .initializing:
            updateInterfaceVisibility(with: .indeterminate)
            toolTip = NSLocalizedString("InitializingUpdateStatus", comment: "Update progress state of initializing an update")

        case let .downloading(loadedSize, totalSize):
            updateInterfaceVisibility(with: .progress)

            // Downloading goes to 75% of the progress
            contentCell.updateProgress = (Double(loadedSize) / Double(totalSize)) * 0.75

            let byteFormatter = ByteCountFormatter()
            byteFormatter.countStyle = .file

            let formatString = NSLocalizedString("DownloadingUpdateStatus", comment: "Update progress state of downloading an update. The first %@ stands for the already downloaded bytes, the second one for the total amount of bytes. One expected output would be 'Downloading 3 MB of 21 MB'")
            toolTip = String.localizedStringWithFormat(formatString, byteFormatter.string(fromByteCount: loadedSize), byteFormatter.string(fromByteCount: totalSize))

        case let .extracting(progress):
            updateInterfaceVisibility(with: .progress)

            // Extracting goes to 95%
            contentCell.updateProgress = 0.75 + (progress * 0.25)
            toolTip = NSLocalizedString("ExtractingUpdateStatus", comment: "Update progress state of extracting the downloaded update")

        case .installing:
            updateInterfaceVisibility(with: .indeterminate)
            toolTip = NSLocalizedString("InstallingUpdateStatus", comment: "Update progress state of installing an update")

        case let .error(error):
            updateInterfaceVisibility(with: showActionButton ? .error : .none)
            self.error = error

        case .cancelling:
            updateInterfaceVisibility(with: .indeterminate)
            toolTip = NSLocalizedString("CancellingUpdateStatus", comment: "Update progress state of cancelling an update")
        }
    }

    /// Updates the visibility of single views with the given state.
    private var interfaceState: InterfaceState = .none
    private func updateInterfaceVisibility(with state: InterfaceState) {
        isHidden = (state == .none)

        // Nothing to update
        guard interfaceState != state || contentCell.contentType != state.contentType else {
            return
        }

        interfaceState = state
        contentCell.contentType = state.contentType

        var title: String?
        var image: NSImage?
        switch state {
        case .update:
            title = NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
        case .open:
            title = NSLocalizedString("OpenAction", comment: "Action to open a given app.")
        case .error:
            image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: NSLocalizedString("ErrorButtonAccessibilityTitle", comment: "Description of button that opens an error dialogue.")) ?? NSImage(named: "warning")!
        default:
            ()
        }

        self.title = title ?? ""
        self.image = image
    }

    // MARK: - Actions

    @objc func performAction(_: UpdateButton) {
        switch interfaceState {
        case .update:
            app?.performUpdate()
        case .open:
            app?.open()
        case .progress:
            app?.cancelUpdate()
        case .error:
            presentErrorModally()
        // Do nothing in the other states
        default:
            ()
        }
    }
}

// MARK: - Error Handling

private extension UpdateButton {
    /// Responses to error alerts shown to the user.
    enum ErrorAlertResponse: Int {
        /// The update operation should be rescheduled.
        case retry = 1000

        /// No further action is required.
        case cancel = 1001
    }

    /// Presents the stored error as modal alert.
    private func presentErrorModally() {
        if let error, let window {
            alert(for: error).beginSheetModal(for: window) { response in
                switch ErrorAlertResponse(rawValue: response.rawValue) {
                case .retry:
                    self.app?.performUpdate()
                case .cancel, .none:
                    ()
                }
            }
        }
    }

    /// Configures and returns an alert for the given error.
    private func alert(for error: Error) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational

        let message = NSLocalizedString("UpdateErrorAlertTitle", comment: "Title of alert stating that an error occurred during an app update. The placeholder %@ will be replaced with the name of the app.")
        alert.messageText = String.localizedStringWithFormat(message, app!.name)

        alert.informativeText = error.localizedDescription

        alert.addButton(withTitle: NSLocalizedString("RetryAction", comment: "Button to retry an update in an error dialogue"))
        alert.addButton(withTitle: NSLocalizedString("CancelAction", comment: "Cancel button in an update dialogue"))

        return alert
    }
}

// MARK: - Animator Proxy

extension UpdateButton {
    override func animation(forKey key: NSAnimatablePropertyKey) -> Any? {
        switch key {
        case "backgroundColor":
            CABasicAnimation()

        default:
            super.animation(forKey: key)
        }
    }
}
