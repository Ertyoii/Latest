//
//  UpdateRepository.swift
//  Latest
//
//  Created by Max Langer on 01.10.23.
//  Copyright © 2023 Max Langer. All rights reserved.
//

import AppKit

extension UpdateRepository {

	/// Represents one application within the repository.
	struct Entry: Decodable {


		// MARK:  - Structure

		enum CodingKeys: String, CodingKey {
			case artifacts
			case desc
			case homepage
			case names = "name"
			case token
			case url
			case rawVersion = "version"
			case minimumOSVersion = "depends_on"
		}

		private struct MinimumOS: Decodable {
			let macos: Version?

			struct Version: Decodable {
				let version: [String]?

				enum CodingKeys: String, CodingKey {
					case version = ">="
				}
			}
		}


		// MARK: - Accessors

		/// Possible names of the app.
		///
		/// Used for matching app bundles with repository entries.
		let names: Set<String>

		/// Possible bundle identifiers of the app.
		///
		/// Used for matching app bundles with repository entries.
		let bundleIdentifiers: Set<String>

		/// Whether this entry was matched through broad cask metadata and must be verified with its bundle identifier.
		let requiresBundleIdentifierMatch: Bool

		/// The current version of the app.
		let version: Version

		/// The upstream download URL of the app.
		private let url: URL?

		/// The upstream homepage of the app.
		private let homepage: URL?

		/// A short description of the app.
		private let desc: String?

		/// The brew identifier for the app.
		let token: String

		/// The minimum os version required for the update.
		let minimumOSVersion: OperatingSystemVersion?

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)

			// Trivial keys
			let rawVersion = try container.decode(String.self, forKey: .rawVersion)
			version = VersionParser.parse(combinedVersionNumber: rawVersion)
			token = try container.decode(String.self, forKey: .token)
			url = try container.decodeIfPresent(URL.self, forKey: .url)
			homepage = try container.decodeIfPresent(URL.self, forKey: .homepage)
			desc = try container.decodeIfPresent(String.self, forKey: .desc)

			// Artifacts: Contains application names and bundle identifiers.
			let artifacts = try container.decode([FailableDecodable<Artifact>].self, forKey: .artifacts)
				.reduce(into: (names: [String](), identifiers: [String]())) { result, artifactWrapper in
					guard let artifact = artifactWrapper.base else {
						return
					}

					result.names.append(contentsOf: artifact.names)
					result.identifiers.append(contentsOf: artifact.identifiers)
				}
			bundleIdentifiers = Set(artifacts.identifiers)
			let artifactNames = Set(artifacts.names)

			if artifactNames.isEmpty, !bundleIdentifiers.isEmpty {
				let displayNames = try container.decodeIfPresent([String].self, forKey: .names) ?? []
				names = Set(displayNames.compactMap(\.homebrewAppBundleName))
				requiresBundleIdentifierMatch = !names.isEmpty
			} else {
				names = artifactNames
				requiresBundleIdentifierMatch = false
			}

			// OS Version
			if let osVersion = try container.decode(MinimumOS.self, forKey: .minimumOSVersion).macos?.version?.first {
				minimumOSVersion = try OperatingSystemVersion(string: osVersion)
			} else {
				minimumOSVersion = nil
			}
		}

		/// Whether the cask represents the default stable channel.
		var isStableRelease: Bool {
			return !token.contains("@")
		}

		/// Release notes derived from upstream metadata where possible.
		var releaseNotes: App.Update.ReleaseNotes? {
			if let githubReleaseURL {
				return .githubRelease(apiURL: githubReleaseURL, fallbackHTML: fallbackReleaseNotesHTML)
			}

			let changelogURLs = self.changelogURLs
			if !changelogURLs.isEmpty {
				return .changelog(urls: changelogURLs, versionPrefix: changelogVersionPrefix, allowsLatestFallback: allowsLatestChangelogFallback, fallbackHTML: fallbackReleaseNotesHTML)
			}

			return fallbackReleaseNotesHTML.map { .html(string: $0) }
		}

	}

}

private extension UpdateRepository.Entry {

	var githubReleaseURL: URL? {
		guard let url, url.host?.caseInsensitiveCompare("github.com") == .orderedSame else { return nil }

		let components = url.pathComponents
		guard components.count > 5, components[3] == "releases", components[4] == "download" else { return nil }

		let owner = components[1]
		let repository = components[2]
		let tag = components[5]

		return URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/tags/\(tag)")
	}

	var changelogURLs: [URL] {
		if token == "cursor" || homepage?.host?.contains("cursor.com") == true {
			return URL(string: "https://cursor.com/changelog").map { [$0] } ?? []
		}

		if let zedReleaseURL {
			return [zedReleaseURL]
		}

		guard let homepage else { return [] }

		let releasePaths = ["changelog", "release-notes", "releases", "whats-new"]
		return releasePaths.compactMap { path in
			URL(string: path, relativeTo: homepage)?.absoluteURL
		}
	}

	var allowsLatestChangelogFallback: Bool {
		token == "cursor" || homepage?.host?.contains("cursor.com") == true
	}

	var changelogVersionPrefix: String? {
		if zedReleaseURL != nil {
			return version.versionNumber
		}

		return version.versionNumber?.majorMinorVersionPrefix
	}

	var zedReleaseURL: URL? {
		guard token == "zed" || token == "zed@preview",
			  let versionNumber = version.versionNumber else {
			return nil
		}

		let channel = token == "zed@preview" ? "preview" : "stable"
		return URL(string: "https://zed.dev/releases/\(channel)/\(versionNumber)")
	}

	var fallbackReleaseNotesHTML: String? {
		guard let versionNumber = version.versionNumber ?? version.buildNumber else {
			return nil
		}

		let title = names.min()?.homebrewDisplayName ?? token
		let description = desc?.trimmingCharacters(in: .whitespacesAndNewlines)

		var paragraphs = [
			"<p><strong>\(title.htmlEscaped) \(versionNumber.htmlEscaped)</strong> is available from Homebrew.</p>"
		]

		if let description, !description.isEmpty {
			paragraphs.append("<p>\(description.htmlEscaped)</p>")
		}

		if let homepage {
			let homepageString = homepage.absoluteString
			paragraphs.append("<p><a href=\"\(homepageString.htmlEscaped)\">\(homepageString.htmlEscaped)</a></p>")
		}

		return paragraphs.joined()
	}

}

private extension String {

	var homebrewDisplayName: String {
		if hasSuffix(".app") {
			return String(dropLast(4))
		}

		return self
	}

	var majorMinorVersionPrefix: String? {
		let parts = split(separator: ".", omittingEmptySubsequences: true)
		guard parts.count >= 2 else { return self.isEmpty ? nil : self }

		return parts.prefix(2).joined(separator: ".")
	}

}

private extension String {

	var htmlEscaped: String {
		replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
	}

}

fileprivate extension UpdateRepository.Entry {

	/// One entry datapoint containing possible application names and bundle identifiers.
	struct Artifact: Decodable {

		/// Possible application names.
		let names: Set<String>

		/// Possible bundle identifiers.
		let identifiers: Set<String>

		private enum CodingKeys: String, CodingKey {
			/// Contains application names
			case app

			/// Contains paths to files and folders that should be deleted upon deinstallation.
			///
			/// These paths usually contain the bundle identifier of an app so we extract those from the paths.
			case zap

			/// Contains file paths and identifiers.
			///
			/// Both app names and identifiers can be extracted from this data set.
			case uninstall
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)

			var names = [String]()
				var identifiers = [String]()
				var identifierPaths = [String]()

			// App names.
			if let appNames = try? Self.decodeAppNames(container) {
				names.append(contentsOf: appNames)
			}

			// Extract everything else.
				identifierPaths.append(contentsOf: (try? Self.decodeZap(container)) ?? [])
				if let uninstall = try? Self.decodeUninstall(container) {
					names.append(contentsOf: uninstall.names)
					identifiers.append(contentsOf: uninstall.identifiers)
				}

				self.names = Set(names)
				self.identifiers = Set(identifiers + identifierPaths.flatMap { path in
					let string = path as NSString
					guard !string.pathExtension.isEmpty else { return [String]() }
					let identifier = string.lastPathComponent
					return [identifier, (identifier as NSString).deletingPathExtension]
				})

		}


		// MARK: - Decoding

		private static func decodeAppNames(_ container: KeyedDecodingContainer<CodingKeys>) throws -> [String] {
			struct Target: Decodable {
				let target: String
			}

			var appContainer = try container.nestedUnkeyedContainer(forKey: .app)
			var names: [String] = []
			while !appContainer.isAtEnd {
				do {
					let target = try appContainer.decode(Target.self)
					names.append(target.target)
				} catch {
					let stringValue = try appContainer.decode(String.self)
					names.append(stringValue)
				}
			}

			return names
		}

		private static func decodeZap(_ container: KeyedDecodingContainer<CodingKeys>) throws -> [String] {
			enum ZapKeys: String, CodingKey {
				case trash
				case delete
			}

			var nestedContainer = try container.nestedUnkeyedContainer(forKey: .zap)
			let zapContainer = try nestedContainer.nestedContainer(keyedBy: ZapKeys.self)
			return ((try? zapContainer.decodeVariable(String.self, forKey: .trash)) ?? [])
				+ ((try? zapContainer.decodeVariable(String.self, forKey: .delete)) ?? [])
		}

		private static func decodeUninstall(_ container: KeyedDecodingContainer<CodingKeys>) throws -> (names: [String], identifiers: [String]) {
			enum UninstallKeys: String, CodingKey {
				/// List of bundle identifiers of binaries to be closed before uninstallation.
				case quit

				/// List of binary paths to be deleted separately.
				case delete

				/// List of bundle identifiers of binaries to be deleted separately..
				case pkgutil
			}

			guard var a = try? container.nestedUnkeyedContainer(forKey: .uninstall), let uninstallContainer = try? a.nestedContainer(keyedBy: UninstallKeys.self) else { return ([],[]) }

			// Try to get application names
			let names: [String] = (try? uninstallContainer.decodeVariable(String.self, forKey: .delete))?.compactMap { path in
				let url = URL(fileURLWithPath: path)
				guard url.pathExtension == "app" else { return nil }
				return url.lastPathComponent
			} ?? []

			// Try to get bundle identifiers
			let identifiers = [UninstallKeys.pkgutil, .quit].flatMap { key in
				(try? uninstallContainer.decodeVariable(String.self, forKey: key)) ?? []
			}

			return (names, identifiers)
		}

	}

}

fileprivate extension KeyedDecodingContainer {

	/// Returns an array with objects of the given type for the given key.
	///
	/// Can decode single objects and arrays.
	func decodeVariable<T>(_ type: T.Type, forKey key: KeyedDecodingContainer<K>.Key) throws -> [T] where T: Decodable {
		var value: [T] = []
		do {
			// Attempt to decode single object.
			let identifier = try decode(T.self, forKey: key)
			value.append(identifier)
		} catch {
			// Must be an array now.
			value = try decode([T].self, forKey: key)
		}
		return value
	}

}

fileprivate extension String {

	/// Returns the value as an application bundle name.
	var homebrewAppBundleName: String? {
		let name = trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { return nil }
		guard (name as NSString).pathExtension.caseInsensitiveCompare("app") != .orderedSame else {
			return name
		}

		return name + ".app"
	}

}
