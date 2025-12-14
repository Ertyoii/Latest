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
	
	private static let appExtension = UTType.applicationBundle.preferredFilenameExtension ?? "app"
	
	/// Returns a list of application bundles at the given URL.
	static func collectBundles(at url: URL) -> [App.Bundle] {
		let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
		
		var bundles = [App.Bundle]()
		while let bundleURL = enumerator?.nextObject() as? URL {
			guard !excludedSubfolders.contains(where: { bundleURL.path.contains($0) }) else {
				enumerator?.skipDescendants()
				continue
			}
			
			if bundleURL.pathExtension == appExtension, let bundle = bundle(forAppAt: bundleURL) {
				bundles.append(bundle)
			}
		}

		return bundles
	}
	
	
	// MARK: - Utilities
		
	/// Returns a bundle representation for the app at the given url, without Spotlight Metadata.
	static private func bundle(forAppAt url: URL) -> App.Bundle? {
		guard let info = appBundleInfo(at: url),
			  let buildNumber = info.buildNumber,
			  let identifier = info.bundleIdentifier,
			  let versionNumber = info.shortVersionString else { return nil }
		
		// Find update source
		guard let source = UpdateCheckCoordinator.source(forAppAt: url) else {
			return nil
		}
		
		// Skip bundles which are explicitly excluded
		guard !excludedBundleIdentifiers.contains(where: { identifier.contains($0) }) else {
			return nil
		}
		
		// Build version. Skip bundle if no version is provided.
		let version = Version(versionNumber: VersionParser.parse(versionNumber: versionNumber), buildNumber: VersionParser.parse(buildNumber: buildNumber))
		guard !version.isEmpty else {
			return nil
		}
		
		let appName = info.name ?? url.deletingPathExtension().lastPathComponent

		// Create bundle
		return App.Bundle(version: version, name: appName, bundleIdentifier: identifier, fileURL: url, source: source)
	}

}

private extension BundleCollector {
	struct AppBundleInfo {
		let bundleIdentifier: String?
		let buildNumber: String?
		let shortVersionString: String?
		let name: String?
	}

	static func appBundleInfo(at url: URL) -> AppBundleInfo? {
		if let plist = readInfoPlist(at: url) {
			return AppBundleInfo(
				bundleIdentifier: plist["CFBundleIdentifier"] as? String,
				buildNumber: plist["CFBundleVersion"] as? String,
				shortVersionString: plist["CFBundleShortVersionString"] as? String,
				name: (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String)
			)
		}

		guard let bundle = Bundle(url: url) else { return nil }
		return AppBundleInfo(
			bundleIdentifier: bundle.bundleIdentifier,
			buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String,
			shortVersionString: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
			name: bundle.infoDictionary?["CFBundleName"] as? String
		)
	}

	static func readInfoPlist(at appURL: URL) -> [String: Any]? {
		let infoURL = appURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
		guard let data = try? Data(contentsOf: infoURL) else { return nil }
		guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
		return plist
	}
}
