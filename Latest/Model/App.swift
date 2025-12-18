//
//  App.swift
//  Latest
//
//  Created by Max Langer on 05.01.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import Cocoa

/// The combined representation of an app bundle and its associated update information.
final class App: @unchecked Sendable {
    /// The bundle of the locally available app.
    let bundle: App.Bundle

    /// The result of an attempted update fetch operation.
    private let updateResult: Result<Update, Error>?

    /// Whether the app is ignored.
    let isIgnored: Bool

    /// Whether the app is currently pending an update check (used to stabilize list on startup).
    let isPendingCheck: Bool

    // MARK: - Initialization

    /// Initializes the app with the given parameters.

    /// Initializes the app with the given parameters.
    init(bundle: App.Bundle, update: Result<Update, Error>?, isIgnored: Bool, isPendingCheck: Bool = false) {
        self.bundle = bundle
        updateResult = Self.sanitize(update: update, for: bundle)
        self.isIgnored = isIgnored
        self.isPendingCheck = isPendingCheck
    }

    /// Returns a new app object with an updated bundle.
    func with(bundle: Bundle) -> App {
        App(bundle: bundle, update: updateResult, isIgnored: isIgnored, isPendingCheck: isPendingCheck)
    }

    /// Returns a new app object with an updated ignored state.
    func with(ignoredState: Bool) -> App {
        App(bundle: bundle, update: updateResult, isIgnored: ignoredState, isPendingCheck: isPendingCheck)
    }

    // MARK: - Sanitization

    /// Sanitizes the update result for the given app bundle.
    ///
    /// Used to clean up version information based on information provided by the app bundle.
    private static func sanitize(update: Result<Update, Error>?, for bundle: App.Bundle) -> Result<Update, Error>? {
        guard let update = try? update?.get() else {
            return update
        }

        return .success(update.sanitized(for: bundle))
    }
}

/// Convenience access to underlying properties.
extension App {
    private var update: Update? {
        switch updateResult {
        case let .success(update):
            update
        default:
            nil
        }
    }

    var error: Error? {
        switch updateResult {
        case let .failure(error):
            error
        default:
            nil
        }
    }

    // MARK: - Bundle Properties

    // The version currently present on the users computer
    var version: Version {
        bundle.version
    }

    /// The display name of the app
    var name: String {
        bundle.name
    }

    /// The bundle identifier of the app
    var identifier: Bundle.Identifier {
        bundle.identifier
    }

    var bundleIdentifier: String {
        bundle.bundleIdentifier
    }

    /// The url of the app on the users computer
    var fileURL: URL {
        bundle.fileURL
    }

    /// The overall source the update is being fetched from.
    var source: Source {
        update?.source ?? bundle.source
    }

    /// Whether the app can be updated within Latest.
    var supported: Bool {
        source != .none
    }

    /// The date of the app when it was last updated.
    var updateDate: Date {
        update?.date ?? bundle.modificationDate
    }

    // MARK: - Update Properties

    /// The newest version of the app available for download.
    var remoteVersion: Version? {
        update?.remoteVersion
    }

    /// The release date of the update
    var latestUpdateDate: Date? {
        update?.date
    }

    /// The release notes of the update
    var releaseNotes: Update.ReleaseNotes? {
        update?.releaseNotes
    }

    /// Whether an update is available for the given app.
    var updateAvailable: Bool {
        update?.updateAvailable ?? false
    }

    /// Whether the app is currently being updated.
    var isUpdating: Bool {
        update?.isUpdating ?? false
    }

    /// Whether the update is performed using a built in updater.
    var usesBuiltInUpdater: Bool {
        update?.usesBuiltInUpdater ?? false
    }

    /// The name of the external updater used to update this app.
    ///
    /// Returns `nil` if `usesBuiltInUpdater` is `true`.
    var externalUpdaterName: String? {
        update?.externalUpdaterName
    }

    /// Updates the app. This is a sub-classing hook. The default implementation opens the app.
    final func performUpdate() {
        update?.perform()
    }

    /// Cancels the ongoing app update.
    func cancelUpdate() {
        update?.cancelUpdate()
    }

    // MARK: - Actions

    /// Opens the app
    func open() {
        bundle.open()
    }

    /// Reveals the app at a given index in Finder
    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // MARK: - Display Utilities

    /// Returns an attributed string that highlights a given search query within this app's name.
    func highlightedName(for query: String?) -> NSAttributedString {
        let name = bundle.name
        let attributedName = NSMutableAttributedString(string: name)

        if let queryString = query, let selectedRange = name.range(of: queryString, options: .caseInsensitive) {
            attributedName.addAttribute(.foregroundColor, value: NSColor(resource: .fadedSearchText), range: NSMakeRange(0, name.count))
            attributedName.removeAttribute(.foregroundColor, range: NSRange(selectedRange, in: name))
        }

        return attributedName
    }
}

// MARK: -  Version String Handling

extension App {
    /// A container holding the current and new version information
    struct DisplayableVersionInformation {
        /// The localized version of the app present on the computer
        var current: String {
            String(format: NSLocalizedString("LocalVersionFormat", comment: "The current version of an localy installed app. The placeholder %@ will be filled with the version number."), "\(rawCurrent)")
        }

        /// The new available version of the app
        var new: String? {
            if let new = rawNew {
                return String(format: NSLocalizedString("RemoteVersionFormat", comment: "The most recent version available for an app. The placeholder %@ will be filled with the version number."), "\(new)")
            }

            return nil
        }

        /// Returns version string by optionally combining the current and new version.
        func combined(includeNew: Bool) -> String {
            if let rawNew, includeNew, rawCurrent != rawNew {
                String(format: NSLocalizedString("CombinedVersionFormat", comment: "Text for the current version number with option to update to a newer one, e.g. 'Version: 1.2.2 -> 1.2.3'. Has two parameters, the first being the current version, the second being the next version."), rawCurrent, rawNew)
            } else {
                String(format: NSLocalizedString("SingleCombinedVersionFormat", comment: "Text for the given version number, e.g. 'Version: 1.2.3'"), rawCurrent)
            }
        }

        fileprivate var rawCurrent: String
        fileprivate var rawNew: String?
    }

    /// Returns localized version information.
    var localizedVersionInformation: DisplayableVersionInformation? {
        let newVersion = update?.remoteVersion
        let currentVersion = bundle.version
        var versionInformation: DisplayableVersionInformation?

        if let v = currentVersion.versionNumber, let nv = newVersion?.versionNumber {
            versionInformation = DisplayableVersionInformation(rawCurrent: v, rawNew: nv)

            // If the shortVersion string is identical, but the bundle version is different
            // Show the Bundle version in brackets like: "1.3 (21)"
            if update?.updateAvailable ?? false, v == nv, let v = currentVersion.buildNumber, let nv = newVersion?.buildNumber {
                versionInformation?.rawCurrent += " (\(v))"
                versionInformation?.rawNew! += " (\(nv))"
            }
        } else if let v = currentVersion.buildNumber, let nv = newVersion?.buildNumber {
            versionInformation = DisplayableVersionInformation(rawCurrent: v, rawNew: nv)
        } else if let v = currentVersion.versionNumber ?? currentVersion.buildNumber {
            versionInformation = DisplayableVersionInformation(rawCurrent: v, rawNew: nil)
        }

        return versionInformation
    }
}

extension App: Hashable {
    static func == (lhs: App, rhs: App) -> Bool {
        lhs.identifier == rhs.identifier && lhs.version == rhs.version
    }

    /// Exclude the number of apps from the function
    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

extension App: CustomDebugStringConvertible {
    var debugDescription: String {
        "App:\n\t- Bundle: \(bundle)\n\t- Update: \(update?.debugDescription ?? "None"))"
    }
}
