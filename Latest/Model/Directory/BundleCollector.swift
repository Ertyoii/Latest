//
//  BundleCollector.swift
//  Latest
//
//  Created by Max Langer on 07.03.24.
//  Copyright © 2024 Max Langer. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers

/// Gathers apps at a given URL.
enum BundleCollector {

	/// Excluded subfolders that won't be checked.
	private static let excludedSubfolders = Set(["Setapp"])

	/// Set of bundles that should not be included in Latest.
	private static let excludedBundleIdentifiers = Set([
		// Safari Web Apps
		"com.apple.Safari.WebApp"
	])

	private static let appExtension = UTType.applicationBundle.preferredFilenameExtension

	/// Returns a list of application bundles at the given URL.
	static func collectBundles(at url: URL) -> [App.Bundle] {
		guard !isInExcludedSubfolder(url) else { return [] }

		let enumerator = FileManager.default.enumerator(
			at: url,
			includingPropertiesForKeys: [.isApplicationKey, .isPackageKey, .contentModificationDateKey],
			options: [.skipsHiddenFiles, .skipsPackageDescendants]
		)

		var bundles = [App.Bundle]()
		while let bundleURL = enumerator?.nextObject() as? URL {
			guard !isExcludedSubfolder(bundleURL) else {
				enumerator?.skipDescendants()
				continue
			}

			if bundleURL.pathExtension == appExtension, let bundle = bundle(forAppAt: bundleURL) {
				bundles.append(bundle)
			}
		}

		return bundles
	}

	/// Returns a single application bundle at the given URL.
	static func collectBundle(at url: URL) -> App.Bundle? {
		guard url.pathExtension == appExtension else { return nil }
		return bundle(forAppAt: url)
	}


	// MARK: - Utilities

	private static func isExcludedSubfolder(_ url: URL) -> Bool {
		return excludedSubfolders.contains(url.lastPathComponent)
	}

	private static func isInExcludedSubfolder(_ url: URL) -> Bool {
		return url.pathComponents.contains { excludedSubfolders.contains($0) }
	}

	/// Returns a bundle representation for the app at the given url, without Spotlight Metadata.
	static private func bundle(forAppAt url: URL) -> App.Bundle? {
		guard let infoDictionary = Bundle.infoDictionary(forAppAt: url),
			  let identifier = infoDictionary.bundleIdentifier,
			  let appName = infoDictionary.bundleName else {
			return nil
		}

		// Find update source
		let source = source(forAppAt: url, information: infoDictionary, bundleIdentifier: identifier)

		// Skip bundles which are explicitly excluded
		guard !excludedBundleIdentifiers.contains(where: { identifier.contains($0) }) else {
			return nil
		}

		// Build version. Skip bundle if no version is provided.
		let version = Version(
			versionNumber: infoDictionary.versionNumber.flatMap { VersionParser.parse(versionNumber: $0) },
			buildNumber: infoDictionary.bundleVersion.flatMap { VersionParser.parse(buildNumber: $0) }
		)
		guard !version.isEmpty else {
			return nil
		}

		// Create bundle
		return App.Bundle(version: version, name: appName, bundleIdentifier: identifier, fileURL: url, source: source)
	}

	private static func source(forAppAt url: URL, information: [String: Any], bundleIdentifier: String) -> App.Source {
		if AppStoreUpdateCheckerOperation.canPerformUpdateCheck(forAppAt: url) {
			return .appStore
		}

		if Sparke.feedURL(from: information, bundleIdentifier: bundleIdentifier, bundleURL: url) != nil {
			return .sparkle
		}

		return .none
	}

}

fileprivate extension Bundle {

	/// Returns the bundle info dictionary which is guaranteed to be current.
	static func infoDictionary(forAppAt url: URL) -> [String: Any]? {
		let infoPlistURL = url.appendingPathComponent("Contents/Info.plist", isDirectory: false)
		guard let data = try? Data(contentsOf: infoPlistURL) else {
			return nil
		}

		return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
	}

}

fileprivate extension Dictionary where Key == String, Value == Any {

	/// Returns the bundle identifier when working without Spotlight.
	var bundleIdentifier: String? {
		return self["CFBundleIdentifier"] as? String
	}

	/// Returns the bundle name when working without Spotlight.
	var bundleName: String? {
		return self["CFBundleName"] as? String
			?? self["CFBundleDisplayName"] as? String
			?? self["CFBundleExecutable"] as? String
	}

	/// Returns the short version string when working without Spotlight.
	var versionNumber: String? {
		return self["CFBundleShortVersionString"] as? String
	}

	/// Returns the bundle version when working without Spotlight.
	var bundleVersion: String? {
		return self["CFBundleVersion"] as? String
	}
}
