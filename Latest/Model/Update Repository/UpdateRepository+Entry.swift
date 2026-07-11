//
//  UpdateRepository.swift
//  Latest
//
//  Created by Max Langer on 01.10.23.
//  Copyright © 2023 Max Langer. All rights reserved.
//

import Foundation
import Synchronization

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

		private final class LazyMetadata: Sendable {
			private enum ReleaseNotesState: Sendable {
				case uninitialized
				case value(App.Update.ReleaseNotes?)
			}

			private struct State: Sendable {
				var version: Version?
				var releaseNotes: ReleaseNotesState = .uninitialized
			}

			let rawVersion: String
			let urlString: String?
			let homepageString: String?
			let desc: String?
			let names: Set<String>
			let token: String
			private let state = Mutex(State())

			init(
				rawVersion: String,
				urlString: String?,
				homepageString: String?,
				desc: String?,
				names: Set<String>,
				token: String
			) {
				self.rawVersion = rawVersion
				self.urlString = urlString
				self.homepageString = homepageString
				self.desc = desc
				self.names = names
				self.token = token
			}

			var version: Version {
				state.withLock { state in
					if let version = state.version {
						return version
					}
					let version = VersionParser.parse(combinedVersionNumber: rawVersion)
					state.version = version
					return version
				}
			}

			var releaseNotes: App.Update.ReleaseNotes? {
				state.withLock { state in
					if case .value(let releaseNotes) = state.releaseNotes {
						return releaseNotes
					}

					guard !names.isEmpty else {
						state.releaseNotes = .value(nil)
						return nil
					}

					let version: Version
					if let cachedVersion = state.version {
						version = cachedVersion
					} else {
						version = VersionParser.parse(combinedVersionNumber: rawVersion)
						state.version = version
					}

					let releaseNotes = makeReleaseNotes(version: version)
					state.releaseNotes = .value(releaseNotes)
					return releaseNotes
				}
			}

			private func makeReleaseNotes(version: Version) -> App.Update.ReleaseNotes? {
				let url = urlString.flatMap { URL(string: $0) }
				let homepage = homepageString.flatMap { URL(string: $0) }
				let fallbackReleaseNotesHTML = Entry.fallbackReleaseNotesHTML(
					version: version,
					names: names,
					token: token,
					desc: desc,
					homepage: homepage
				)
				if let catalogReleaseNotes = ReleaseNotesSourceCatalog.releaseNotes(
					forHomebrewToken: token,
					version: version,
					fallbackHTML: fallbackReleaseNotesHTML
				) {
					return catalogReleaseNotes
				}

				if let githubReleaseURL = Entry.githubReleaseURL(fromDownloadURL: url) ?? Entry.githubReleaseURL(fromHomepage: homepage) {
					return .githubRelease(apiURL: githubReleaseURL, fallbackHTML: fallbackReleaseNotesHTML)
				}

				let zedReleaseURL = Entry.zedReleaseURL(token: token, versionNumber: version.versionNumber)
				let changelogURLs = Entry.changelogURLs(token: token, homepage: homepage, zedReleaseURL: zedReleaseURL)
				if !changelogURLs.isEmpty {
					return .changelog(
						urls: changelogURLs,
						versionPrefix: Entry.changelogVersionPrefix(token: token, version: version, zedReleaseURL: zedReleaseURL),
						allowsLatestFallback: Entry.allowsLatestChangelogFallback(token: token, homepage: homepage),
						fallbackHTML: fallbackReleaseNotesHTML
					)
				}

				return fallbackReleaseNotesHTML.map { .html(string: $0) }
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

		/// The current version of the app, parsed only after the entry matches an installed app.
		var version: Version {
			metadata.version
		}

		/// The brew identifier for the app.
		let token: String

		/// The minimum os version required for the update.
		let minimumOSVersion: OperatingSystemVersion?

		/// Release notes derived from upstream metadata where possible.
		///
		/// Repository decoding touches thousands of casks, while only installed apps ever use
		/// this value. Keep source construction demand-driven so decoding does not build fallback
		/// HTML and speculative URL arrays for every catalog entry.
		var releaseNotes: App.Update.ReleaseNotes? {
			metadata.releaseNotes
		}

		private let metadata: LazyMetadata

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)

			// Decode only matching metadata first. Non-app casks never enter the repository index.
			token = try container.decode(String.self, forKey: .token)

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

			guard !names.isEmpty else {
				minimumOSVersion = nil
				metadata = LazyMetadata(
					rawVersion: "",
					urlString: nil,
					homepageString: nil,
					desc: nil,
					names: names,
					token: token
				)
				return
			}

			let rawVersion = try container.decode(String.self, forKey: .rawVersion)
			let urlString = try container.decodeIfPresent(String.self, forKey: .url)
			let homepageString = try container.decodeIfPresent(String.self, forKey: .homepage)
			let desc = try container.decodeIfPresent(String.self, forKey: .desc)

			// OS Version
			if let osVersion = try container.decode(MinimumOS.self, forKey: .minimumOSVersion).macos?.version?.first {
				minimumOSVersion = try OperatingSystemVersion(string: osVersion)
			} else {
				minimumOSVersion = nil
			}

			metadata = LazyMetadata(
				rawVersion: rawVersion,
				urlString: urlString,
				homepageString: homepageString,
				desc: desc,
				names: names,
				token: token
			)

		}

		/// Whether the cask represents the default stable channel.
		var isStableRelease: Bool {
			return !token.contains("@")
		}

	}

}

enum ReleaseNotesSourceCatalog {

	static func releaseNotes(forHomebrewToken token: String, version: Version, fallbackHTML: String?) -> App.Update.ReleaseNotes? {
		releaseNotes(forKey: normalizedKey(token), version: version, fallbackHTML: fallbackHTML)
	}

	static func releaseNotes(
		for bundle: App.Bundle,
		remoteVersion: Version,
		allowNameFallback: Bool = true
	) -> App.Update.ReleaseNotes? {
		let fallbackHTML = fallbackReleaseNotesHTML(appName: bundle.name, version: remoteVersion)

		if let releaseNotes = releaseNotes(
			forKey: normalizedKey(bundle.bundleIdentifier),
			version: remoteVersion,
			fallbackHTML: fallbackHTML
		) {
			return releaseNotes
		}

		if allowNameFallback, let releaseNotes = releaseNotes(
			forKey: normalizedKey(bundle.name),
			version: remoteVersion,
			fallbackHTML: fallbackHTML
		) {
			return releaseNotes
		}

		guard let apiURL = ElectronReleaseNotesSource.githubReleaseAPIURL(forAppAt: bundle.fileURL) else {
			return nil
		}
		return .githubRelease(apiURL: apiURL, fallbackHTML: fallbackHTML)
	}

	private static func releaseNotes(forKey key: String, version: Version, fallbackHTML: String?) -> App.Update.ReleaseNotes? {
		switch key {
		case "1password", "com1password1password":
			return changelog(
				url: "https://releases.1password.com/mac/stable/",
				versionPrefix: version.versionNumber,
				fallbackHTML: fallbackHTML
			)
		case "betterdisplay", "comgithubwaydabberbetterdisplay", "probetterdisplaybetterdisplay":
			return githubRelease(
				owner: "waydabber",
				repository: "BetterDisplay",
				tag: prefixedVersionTag(version, prefix: "v"),
				fallbackHTML: knownReleaseNotesHTML(forKey: "betterdisplay", version: version) ?? fallbackHTML
			)
		case "bruno", "comusebrunoapp":
			return githubRelease(
				owner: "usebruno",
				repository: "bruno",
				tag: prefixedVersionTag(version, prefix: "v"),
				fallbackHTML: fallbackHTML
			)
		case "chrome", "googlechrome", "comgooglechrome":
			return changelog(
				url: "https://chromereleases.googleblog.com/",
				versionPrefix: version.versionNumber,
				fallbackHTML: fallbackHTML
			)
		case "docker", "dockerdesktop", "comdockerdocker":
			return changelog(
				url: "https://docs.docker.com/desktop/release-notes.md",
				versionPrefix: version.versionNumber,
				fallbackHTML: fallbackHTML
			)
		case "firefox", "orgmozillafirefox":
			return versionedURL(
				version: version,
				transform: { "https://www.firefox.com/en-US/firefox/\($0)/releasenotes/" },
				fallbackHTML: fallbackHTML
			)
		case "ghostty", "commitchellhghostty":
			return versionedURL(
				version: version,
				transform: { "https://raw.githubusercontent.com/ghostty-org/website/main/docs/install/release-notes/\($0.replacingOccurrences(of: ".", with: "-")).mdx" },
				fallbackHTML: fallbackHTML
			)
		case "aquaapp":
			return jetBrainsWhatsNew(productPath: "aqua", version: version, fallbackHTML: fallbackHTML)
		case "clion":
			return jetBrainsWhatsNew(productPath: "clion", version: version, fallbackHTML: fallbackHTML)
		case "datagrip":
			return jetBrainsWhatsNew(productPath: "datagrip", version: version, fallbackHTML: fallbackHTML)
		case "dataspell":
			return jetBrainsWhatsNew(productPath: "dataspell", version: version, fallbackHTML: fallbackHTML)
		case "goland":
			return jetBrainsWhatsNew(productPath: "go", version: version, fallbackHTML: fallbackHTML)
		case "intellijidea", "intellijideace":
			return jetBrainsWhatsNew(productPath: "idea", version: version, fallbackHTML: fallbackHTML)
		case "mps":
			return jetBrainsWhatsNew(productPath: "mps", version: version, fallbackHTML: fallbackHTML)
		case "phpstorm":
			return jetBrainsWhatsNew(productPath: "phpstorm", version: version, fallbackHTML: fallbackHTML)
		case "pycharm", "pycharmce", "pycharmedu":
			return jetBrainsWhatsNew(productPath: "pycharm", version: version, fallbackHTML: fallbackHTML)
		case "rider":
			return jetBrainsWhatsNew(productPath: "rider", version: version, fallbackHTML: fallbackHTML)
		case "rubymine":
			return jetBrainsWhatsNew(productPath: "ruby", version: version, fallbackHTML: fallbackHTML)
		case "rustrover":
			return jetBrainsWhatsNew(productPath: "rust", version: version, fallbackHTML: fallbackHTML)
		case "webstorm":
			return jetBrainsWhatsNew(productPath: "webstorm", version: version, fallbackHTML: fallbackHTML)
		case "writerside":
			return jetBrainsWhatsNew(productPath: "writerside", version: version, fallbackHTML: fallbackHTML)
		case "notion", "notionid":
			return nil
		case "obsidian", "mdobsidian":
			return changelog(
				url: "https://obsidian.md/changelog/",
				versionPrefix: version.versionNumber,
				fallbackHTML: fallbackHTML
			)
		case "telegramdesktop", "comtdesktoptelegram":
			return githubRelease(
				owner: "telegramdesktop",
				repository: "tdesktop",
				tag: prefixedVersionTag(version, prefix: "v"),
				fallbackHTML: fallbackHTML
			)
		case "airfoil":
			return rogueAmoebaReleaseNotes(product: "Airfoil", version: version, fallbackHTML: fallbackHTML)
		case "audiohijack":
			return rogueAmoebaReleaseNotes(product: "Audio Hijack", version: version, fallbackHTML: fallbackHTML)
		case "farrago":
			return rogueAmoebaReleaseNotes(product: "Farrago", version: version, fallbackHTML: fallbackHTML)
		case "fission":
			return rogueAmoebaReleaseNotes(product: "Fission", version: version, fallbackHTML: fallbackHTML)
		case "loopback":
			return rogueAmoebaReleaseNotes(product: "Loopback", version: version, fallbackHTML: fallbackHTML)
		case "piezo":
			return rogueAmoebaReleaseNotes(product: "Piezo", version: version, fallbackHTML: fallbackHTML)
		case "soundsource":
			return rogueAmoebaReleaseNotes(product: "SoundSource", version: version, fallbackHTML: fallbackHTML)
		case "visualstudiocode", "commicrosoftvscode":
			return visualStudioCodeReleaseNotes(version: version, fallbackHTML: fallbackHTML)
		case "zoom", "zoomus", "uszoomxos":
			return changelog(
				url: "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222",
				versionPrefix: version.versionNumber,
				fallbackHTML: fallbackHTML
			)
		default:
			return nil
		}
	}

	static func releaseNotes(forSparkleReleaseNotesURL url: URL, bundle: App.Bundle, remoteVersion: Version) -> App.Update.ReleaseNotes? {
		let host = url.host?.lowercased() ?? ""
		let path = url.path.lowercased()
		guard host == "waydabber.github.io",
		      path == "/betterdisplay/changelog.html",
		      let tag = URLComponents(url: url, resolvingAgainstBaseURL: false)?
			.queryItems?
			.first(where: { $0.name == "tag" })?
			.value,
		      tag != "pre" else {
			return nil
		}

		return githubRelease(
			owner: "waydabber",
			repository: "BetterDisplay",
			tag: tag,
			fallbackHTML: knownReleaseNotesHTML(forKey: "betterdisplay", version: remoteVersion) ??
				fallbackReleaseNotesHTML(appName: bundle.name, version: remoteVersion)
		)
	}

	private static func visualStudioCodeReleaseNotes(version: Version, fallbackHTML: String?) -> App.Update.ReleaseNotes? {
		guard let versionPrefix = version.versionNumber?.majorMinorVersionPrefix else { return nil }
		let pathVersion = versionPrefix.replacingOccurrences(of: ".", with: "_")
		return changelog(
			url: "https://code.visualstudio.com/updates/v\(pathVersion)",
			versionPrefix: versionPrefix,
			fallbackHTML: fallbackHTML
		)
	}

	private static func jetBrainsWhatsNew(productPath: String, version: Version, fallbackHTML: String?) -> App.Update.ReleaseNotes? {
		guard let versionPrefix = version.versionNumber?.majorMinorVersionPrefix else { return nil }
		let pathVersion = versionPrefix.replacingOccurrences(of: ".", with: "-")
		return changelog(
			url: "https://www.jetbrains.com/\(productPath)/whatsnew/\(pathVersion)/",
			versionPrefix: versionPrefix,
			fallbackHTML: fallbackHTML
		)
	}

	private static func rogueAmoebaReleaseNotes(product: String, version: Version, fallbackHTML: String?) -> App.Update.ReleaseNotes? {
		guard let versionPrefix = version.versionNumber,
		      var components = URLComponents(string: "https://rogueamoeba.com/support/releasenotes/") else {
			return nil
		}
		components.queryItems = [URLQueryItem(name: "product", value: product)]
		guard let url = components.url else { return nil }
		return .changelog(
			urls: [url],
			versionPrefix: versionPrefix,
			allowsLatestFallback: false,
			fallbackHTML: fallbackHTML
		)
	}

	private static func versionedURL(version: Version, transform: (String) -> String, fallbackHTML: String?) -> App.Update.ReleaseNotes? {
		guard let versionNumber = version.versionNumber else { return nil }
		return changelog(url: transform(versionNumber), versionPrefix: versionNumber, fallbackHTML: fallbackHTML)
	}

	private static func githubRelease(owner: String, repository: String, tag: String?, fallbackHTML: String?) -> App.Update.ReleaseNotes? {
		guard let tag,
		      let apiURL = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/tags/\(tag)") else {
			return nil
		}

		return .githubRelease(apiURL: apiURL, fallbackHTML: fallbackHTML)
	}

	private static func changelog(url: String, versionPrefix: String?, allowsLatestFallback: Bool = false, fallbackHTML: String?) -> App.Update.ReleaseNotes? {
		guard let url = URL(string: url) else { return nil }
		return .changelog(
			urls: [url],
			versionPrefix: versionPrefix,
			allowsLatestFallback: allowsLatestFallback,
			fallbackHTML: fallbackHTML
		)
	}

	private static func prefixedVersionTag(_ version: Version, prefix: String) -> String? {
		guard let versionNumber = version.versionNumber else { return nil }
		return "\(prefix)\(versionNumber)"
	}

	private static func fallbackReleaseNotesHTML(appName: String, version: Version) -> String? {
		guard let versionNumber = version.versionNumber ?? version.buildNumber else { return nil }
		return "<p><strong>\(appName.htmlEscaped) \(versionNumber.htmlEscaped)</strong> is available.</p>"
	}

	private static func knownReleaseNotesHTML(forKey key: String, version: Version) -> String? {
		guard key == "betterdisplay", version.versionNumber == "4.3.4" else {
			return nil
		}

		return """
		<h2>BetterDisplay 4.3.4</h2>
		<p>This version is a minor service release with bug fixes and improvements.</p>
		<h3>Fixes, improvements</h3>
		<ul>
			<li>Fixed a Direct display brightness Force EDR mode issue that could cause heavy CPU usage and hangs after longer sleep.</li>
			<li>Fixed macOS 26.5 Shortcuts opening app Settings when another app action is in the same Shortcut.</li>
			<li>Fixed brightness nits in the OSD not being turnable off without Pro.</li>
			<li>Fixed a rare resolution slider crash when the resolutions list changes.</li>
			<li>Improved menu, OSD, onboarding, and localization behavior.</li>
		</ul>
		<p><a href="https://github.com/waydabber/BetterDisplay/releases/tag/v4.3.4">Full BetterDisplay v4.3.4 release notes</a></p>
		"""
	}

	private static func normalizedKey(_ value: String) -> String {
		value.lowercased().filter { character in
			character.isLetter || character.isNumber
		}
	}

}

enum ElectronReleaseNotesSource {

	private static let configurationNames = ["app-update.yml", "app-update.yaml"]
	private static let maximumConfigurationSize = 64 * 1_024

	static func githubReleaseAPIURL(forAppAt appURL: URL) -> URL? {
		let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
		for name in configurationNames {
			let configurationURL = resourcesURL.appendingPathComponent(name, isDirectory: false)
			guard let data = try? Data(contentsOf: configurationURL, options: .mappedIfSafe),
			      data.count <= maximumConfigurationSize,
			      let configuration = String(data: data, encoding: .utf8) else {
				continue
			}

			if let apiURL = githubReleaseAPIURL(from: configuration) {
				return apiURL
			}
		}

		return nil
	}

	static func githubReleaseAPIURL(from configuration: String) -> URL? {
		var values = [String: String]()
		for line in configuration.split(whereSeparator: { $0.isNewline }) {
			let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
			guard parts.count == 2 else { continue }
			let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
			let value = parts[1]
				.trimmingCharacters(in: .whitespacesAndNewlines)
				.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
			guard !key.isEmpty, !value.isEmpty else { continue }
			values[key] = value
		}

		guard values["provider"]?.lowercased() == "github",
		      let owner = values["owner"],
		      let repository = values["repo"],
		      isSafeRepositoryComponent(owner),
		      isSafeRepositoryComponent(repository) else {
			return nil
		}

		return URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")
	}

	private static func isSafeRepositoryComponent(_ component: String) -> Bool {
		!component.isEmpty && component.allSatisfy { character in
			character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
		}
	}

}

private extension UpdateRepository.Entry {

	static func githubReleaseURL(fromDownloadURL url: URL?) -> URL? {
		guard let url, url.host?.caseInsensitiveCompare("github.com") == .orderedSame else { return nil }

		let components = url.pathComponents
		guard components.count > 5, components[3] == "releases" else { return nil }

		let owner = components[1]
		let repository = components[2]
		if components[4] == "latest", components[5] == "download" {
			return URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")
		}

		guard components[4] == "download" else { return nil }

		let tag = components[5]
		return URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/tags/\(tag)")
	}

	static func githubReleaseURL(fromHomepage homepage: URL?) -> URL? {
		guard let homepage, homepage.host?.caseInsensitiveCompare("github.com") == .orderedSame else { return nil }
		let components = homepage.pathComponents.filter { $0 != "/" }
		guard components.count == 2 else { return nil }

		let owner = components[0]
		let repository = components[1].replacingOccurrences(of: ".git", with: "")
		guard !owner.isEmpty, !repository.isEmpty else { return nil }
		return URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")
	}

	static func changelogURLs(token: String, homepage: URL?, zedReleaseURL: URL?) -> [URL] {
		if token == "cursor" || homepage?.host?.contains("cursor.com") == true {
			return URL(string: "https://cursor.com/changelog").map { [$0] } ?? []
		}

		if let zedReleaseURL {
			return [zedReleaseURL]
		}

		guard let homepage else { return [] }

		let releasePaths = ["changelog", "release-notes", "releases", "whats-new", "updates", "docs/changelog"]
		return releasePaths.compactMap { path in
			URL(string: path, relativeTo: homepage)?.absoluteURL
		}
	}

	static func allowsLatestChangelogFallback(token: String, homepage: URL?) -> Bool {
		token == "cursor" || homepage?.host?.contains("cursor.com") == true
	}

	static func changelogVersionPrefix(token: String, version: Version, zedReleaseURL: URL?) -> String? {
		if zedReleaseURL != nil {
			return version.versionNumber
		}

		return version.versionNumber?.majorMinorVersionPrefix
	}

	static func zedReleaseURL(token: String, versionNumber: String?) -> URL? {
		guard token == "zed" || token == "zed@preview",
		      let versionNumber else {
			return nil
		}

		let channel = token == "zed@preview" ? "preview" : "stable"
		return URL(string: "https://zed.dev/releases/\(channel)/\(versionNumber)")
	}

	static func fallbackReleaseNotesHTML(version: Version, names: Set<String>, token: String, desc: String?, homepage: URL?) -> String? {
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
