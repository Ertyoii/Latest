//
//  Bundle.swift
//  Latest
//
//  Created by Max Langer on 15.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

extension App {
    /// An object representing a single application that is available on the computer.
    class Bundle: @unchecked Sendable {
        typealias Identifier = URL

        /// The version currently present on the users computer
        let version: Version

        /// The display name of the app
        let name: String

        /// The unique identifier of the bundle, equal to the URL of the bundle.
        let identifier: Identifier

        /// The bundle identifier of the app.
        let bundleIdentifier: String

        /// The url of the app on the users computer
        let fileURL: URL

        /// The date the bundle was last modified.
        let modificationDate: Date

        /// The source of the bundle (App Store, Sparkle...)
        let source: Source

        init(version: Version, name: String, bundleIdentifier: String, fileURL: URL, source: Source) {
            self.version = version
            self.name = name
            identifier = fileURL
            self.bundleIdentifier = bundleIdentifier
            self.fileURL = fileURL
            self.source = source

            let date = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            modificationDate = date ?? Date.distantPast
        }

        // MARK: - Actions

        /// Opens the app and a given index
        func open() {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(fileURL, configuration: configuration, completionHandler: nil)
        }

        // MARK: - Secure Coding

        static var supportsSecureCoding: Bool {
            true
        }

        required convenience init?(coder: NSCoder) {
            let versionNumber = coder.decodeObject(of: NSString.self, forKey: "versionNumber") as String?
            let buildNumber = coder.decodeObject(of: NSString.self, forKey: "buildNumber") as String?

            guard let name = coder.decodeObject(of: NSString.self, forKey: "name") as String?,
                  let bundleIdentifier = coder.decodeObject(of: NSString.self, forKey: "bundleIdentifier") as String?,
                  let fileURL = coder.decodeObject(of: NSURL.self, forKey: "fileURL") as URL?,
                  let rawSource = coder.decodeObject(of: NSString.self, forKey: "source") as String?, let source = Source(rawValue: rawSource) else { return nil }

            self.init(version: Version(versionNumber: versionNumber, buildNumber: buildNumber), name: name, bundleIdentifier: bundleIdentifier, fileURL: fileURL, source: source)
        }

        func encode(with coder: NSCoder) {
            coder.encode(version.versionNumber, forKey: "versionNumber")
            coder.encode(version.buildNumber, forKey: "buildNumber")
            coder.encode(name, forKey: "name")
            coder.encode(identifier, forKey: "bundleIdentifier")
            coder.encode(fileURL, forKey: "fileURL")
            coder.encode(source.rawValue, forKey: "source")
        }
    }
}

extension App.Bundle: Equatable {
    /// Compares two apps on equality
    static func == (lhs: App.Bundle, rhs: App.Bundle) -> Bool {
        lhs.fileURL == rhs.fileURL
    }
}

extension App.Bundle: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
        hasher.combine(version)
    }
}

extension App.Bundle: CustomDebugStringConvertible {
    var debugDescription: String {
        "\(name), \(version)"
    }
}
