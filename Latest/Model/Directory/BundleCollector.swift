//
//  BundleCollector.swift
//  Latest
//
//  Created by Max Langer on 07.03.24.
//  Copyright © 2024 Max Langer. All rights reserved.
//

import Foundation
import Darwin
import Synchronization
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

	private static let packageExtensionsToSkip = Set([
		"app", "appex", "bundle", "framework", "kext", "mdimporter", "plugin", "prefpane", "qlgenerator", "xpc"
	])

	private static let metadataCache = BundleMetadataCache()
	private static let collectionCountCache = BundleCollectionCountCache()

	/// Returns a list of application bundles at the given URL.
	static func collectBundles(at url: URL) -> [App.Bundle] {
		guard !isInExcludedSubfolder(url) else { return [] }

		let enumerator = FileManager.default.enumerator(
			at: url,
			includingPropertiesForKeys: nil,
			options: [.skipsHiddenFiles]
		)

		var bundles = [App.Bundle]()
		while let bundleURL = enumerator?.nextObject() as? URL {
			guard !isExcludedSubfolder(bundleURL) else {
				enumerator?.skipDescendants()
				continue
			}

			let pathExtension = bundleURL.pathExtension.lowercased()
			if pathExtension == appExtension {
				if let bundle = cachedBundle(forAppAt: bundleURL) {
					bundles.append(bundle)
				}
				enumerator?.skipDescendants()
				continue
			}

			if packageExtensionsToSkip.contains(pathExtension) {
				enumerator?.skipDescendants()
			}
		}

		metadataCache.pruneEntries(below: url, keeping: Set(bundles.map(\.fileURL)))
		collectionCountCache.store(bundles.count, for: url)
		return bundles
	}

	/// Returns a recently collected app count without walking the directory again.
	static func cachedBundleCount(at url: URL) -> Int? {
		collectionCountCache.count(for: url)
	}

	/// Returns a single application bundle at the given URL.
	static func collectBundle(at url: URL) -> App.Bundle? {
		guard url.pathExtension == appExtension else { return nil }
		return cachedBundle(forAppAt: url)
	}


	// MARK: - Utilities

	private static func isExcludedSubfolder(_ url: URL) -> Bool {
		return excludedSubfolders.contains(url.lastPathComponent)
	}

	private static func isInExcludedSubfolder(_ url: URL) -> Bool {
		return url.pathComponents.contains { excludedSubfolders.contains($0) }
	}

	private static func cachedBundle(forAppAt url: URL) -> App.Bundle? {
		guard let signature = BundleFileSignature(appURL: url) else {
			metadataCache.removeBundle(forAppAt: url)
			return nil
		}

		return metadataCache.bundle(forAppAt: url, signature: signature) {
			bundle(forAppAt: url)
		}
	}

	/// Returns a bundle representation for the app at the given url, without Spotlight Metadata.
	static private func bundle(forAppAt url: URL) -> App.Bundle? {
		guard let infoDictionary = Bundle.infoDictionary(forAppAt: url),
			  let identifier = infoDictionary.bundleIdentifier,
			  let appName = infoDictionary.bundleName else {
			return nil
		}

		// Skip bundles which are explicitly excluded
		guard !isExcludedBundleIdentifier(identifier) else {
			return nil
		}

		// Find update source
		let source = source(forAppAt: url, information: infoDictionary, bundleIdentifier: identifier)

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

	private static func isExcludedBundleIdentifier(_ identifier: String) -> Bool {
		excludedBundleIdentifiers.contains { identifier.contains($0) }
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

private final class BundleMetadataCache: Sendable {
	private struct Entry: Sendable {
		let signature: BundleFileSignature
		let bundle: App.Bundle
	}

	private let entries = Mutex([URL: Entry]())

	func bundle(forAppAt url: URL, signature: BundleFileSignature, loader: () -> App.Bundle?) -> App.Bundle? {
		let key = url.standardizedFileURL

		if let cachedBundle = entries.withLock({ $0[key] }) {
			if cachedBundle.signature == signature {
				return cachedBundle.bundle
			}
		}

		guard let bundle = loader() else {
			removeBundle(forAppAt: url)
			return nil
		}

		entries.withLock { entries in
			entries[key] = Entry(signature: signature, bundle: bundle)
		}
		return bundle
	}

	func removeBundle(forAppAt url: URL) {
		let key = url.standardizedFileURL
		entries.withLock { entries in
			_ = entries.removeValue(forKey: key)
		}
	}

	func pruneEntries(below rootURL: URL, keeping retainedURLs: Set<URL>) {
		let rootPath = rootURL.standardizedFileURL.path
		let descendantPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
		let retainedURLs = Set(retainedURLs.map(\.standardizedFileURL))

		entries.withLock { entries in
			entries = entries.filter { url, _ in
				let path = url.path
				guard path == rootPath || path.hasPrefix(descendantPrefix) else { return true }
				return retainedURLs.contains(url)
			}
		}
	}
}

private final class BundleCollectionCountCache: Sendable {
	private struct Entry: Sendable {
		let count: Int
		let collectedAt: Date
		var lastAccessedAt: Date
	}

	private let entries = Mutex([URL: Entry]())
	private let lifetime: TimeInterval = 60
	private let maximumEntryCount = 64

	func count(for url: URL) -> Int? {
		let key = url.standardizedFileURL
		let now = Date()
		return entries.withLock { entries in
			guard var entry = entries[key], now.timeIntervalSince(entry.collectedAt) < lifetime else {
				entries[key] = nil
				return nil
			}
			entry.lastAccessedAt = now
			entries[key] = entry
			return entry.count
		}
	}

	func store(_ count: Int, for url: URL) {
		let key = url.standardizedFileURL
		let now = Date()
		entries.withLock { entries in
			entries[key] = Entry(count: count, collectedAt: now, lastAccessedAt: now)
			while entries.count > maximumEntryCount {
				guard let leastRecentlyUsedKey = entries.min(by: {
					$0.value.lastAccessedAt < $1.value.lastAccessedAt
				})?.key else { return }
				entries[leastRecentlyUsedKey] = nil
			}
		}
	}
}

private struct BundleFileSignature: Equatable, Sendable {
	let app: FileSystemItemSignature?
	let contents: FileSystemItemSignature?
	let infoPlist: FileSystemItemSignature
	let pkgInfo: FileSystemItemSignature?
	let executableDirectory: FileSystemItemSignature?
	let resources: FileSystemItemSignature?
	let standardReceipt: FileSystemItemSignature?
	let wrapper: FileSystemItemSignature?
	let frameworks: FileSystemItemSignature?
	let codeSignature: FileSystemItemSignature?

	init?(appURL: URL) {
		let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
		let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
		guard let infoPlist = FileSystemItemSignature(url: infoPlistURL) else {
			return nil
		}

		let standardReceiptURL = contentsURL.appendingPathComponent("_MASReceipt/receipt", isDirectory: false)

		self.app = FileSystemItemSignature(url: appURL)
		self.contents = FileSystemItemSignature(url: contentsURL)
		self.infoPlist = infoPlist
		self.pkgInfo = FileSystemItemSignature(url: contentsURL.appendingPathComponent("PkgInfo", isDirectory: false))
		self.executableDirectory = FileSystemItemSignature(url: contentsURL.appendingPathComponent("MacOS", isDirectory: true))
		self.resources = FileSystemItemSignature(url: contentsURL.appendingPathComponent("Resources", isDirectory: true))
		self.standardReceipt = FileSystemItemSignature(url: standardReceiptURL)
		self.wrapper = FileSystemItemSignature(url: contentsURL.appendingPathComponent("Wrapper", isDirectory: true))
		self.frameworks = FileSystemItemSignature(url: contentsURL.appendingPathComponent("Frameworks", isDirectory: true))
		self.codeSignature = FileSystemItemSignature(url: contentsURL.appendingPathComponent("_CodeSignature/CodeResources", isDirectory: false))
	}
}

private struct FileSystemItemSignature: Equatable, Sendable {
	let modificationSeconds: Int
	let modificationNanoseconds: Int
	let size: Int64

	init?(url: URL) {
		var fileInfo = stat()
		let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
			guard let path else { return -1 }
			return stat(path, &fileInfo)
		}
		guard result == 0 else { return nil }

		self.modificationSeconds = Int(fileInfo.st_mtimespec.tv_sec)
		self.modificationNanoseconds = Int(fileInfo.st_mtimespec.tv_nsec)
		self.size = fileInfo.st_size
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
