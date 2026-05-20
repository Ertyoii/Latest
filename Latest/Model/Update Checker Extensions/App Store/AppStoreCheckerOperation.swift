//
//  AppStoreUpdateCheckerOperation.swift
//  Latest
//
//  Created by Max Langer on 03.10.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import Cocoa
import ServiceManagement

private let malformedURLError = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL)

private struct AppStoreLookupCacheKey: Hashable {
	let bundleIdentifier: String
	let countryCode: String
	let entityType: String
}

private enum AppStoreLookupCacheValue {
	case entry(AppStoreEntry)
	case unavailable

	var result: Result<AppStoreEntry, Error> {
		switch self {
		case .entry(let entry):
			return .success(entry)
		case .unavailable:
			return .failure(LatestError.updateInfoUnavailable)
		}
	}
}

private actor AppStoreLookupCache {
	static let shared = AppStoreLookupCache()

	private var values = [AppStoreLookupCacheKey: AppStoreLookupCacheValue]()

	func value(for key: AppStoreLookupCacheKey) -> AppStoreLookupCacheValue? {
		values[key]
	}

	func set(_ value: AppStoreLookupCacheValue, for key: AppStoreLookupCacheKey) {
		values[key] = value
	}
}

private final class AppStoreLookupClient: @unchecked Sendable {
	static let shared = AppStoreLookupClient()

	private let endpoint = URL(string: "https://itunes.apple.com/lookup")
	private let cache = AppStoreLookupCache.shared
	private let session: URLSession

	init(session: URLSession = .shared) {
		self.session = session
	}

	func lookup(bundleIdentifier: String, entityTypes: [String]) async throws -> AppStoreEntry {
		var lastError: Error = LatestError.updateInfoUnavailable
		for entityType in entityTypes {
			do {
				return try await lookup(bundleIdentifier: bundleIdentifier, entityType: entityType)
			} catch {
				lastError = error
			}
		}

		throw lastError
	}

	private func lookup(bundleIdentifier: String, entityType: String) async throws -> AppStoreEntry {
		let countryCode = Locale.current.region?.identifier ?? "US"
		let cacheKey = AppStoreLookupCacheKey(bundleIdentifier: bundleIdentifier, countryCode: countryCode, entityType: entityType)
		if let cachedValue = await cache.value(for: cacheKey) {
			return try cachedValue.result.get()
		}

		guard let endpoint else {
			throw malformedURLError
		}

		var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
		components?.queryItems = [
			URLQueryItem(name: "limit", value: "1"),
			URLQueryItem(name: "entity", value: entityType),
			URLQueryItem(name: "country", value: countryCode),
			URLQueryItem(name: "bundleId", value: bundleIdentifier)
		]
		guard let url = components?.url else {
			throw malformedURLError
		}

		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
		let (data, _) = try await session.data(for: request)
		guard let entry = try JSONDecoder().decode(EntryList.self, from: data).results.first else {
			await cache.set(.unavailable, for: cacheKey)
			throw LatestError.updateInfoUnavailable
		}

		await cache.set(.entry(entry), for: cacheKey)
		return entry
	}
}

/// The operation for checking for updates for a Mac App Store app.
class AppStoreUpdateCheckerOperation: StatefulOperation, UpdateCheckerOperation, @unchecked Sendable {
	
	// MARK: - Update Check
	
	static var sourceType: App.Source {
		return .appStore
	}
	
	static func canPerformUpdateCheck(forAppAt url: URL) -> Bool {
		let fileManager = FileManager.default
		
		// Mac Apps contain a receipt, iOS apps are only available via the Mac App Store
		guard let receiptPath = receiptPath(forAppAt: url), fileManager.fileExists(atPath: receiptPath) || isIOSAppBundle(at: url) else { return false }
		
		return true
	}
	
	required init(with app: App.Bundle, repository: UpdateRepository?, completionBlock: @escaping UpdateCheckerCompletionBlock) {
		self.app = app
		
		super.init()

		self.completionBlock = {
			guard !self.isCancelled else { return }
			
			if let update = self.update {
				completionBlock(.success(update))
			} else {
				completionBlock(.failure(self.error ?? LatestError.updateInfoUnavailable))
			}
		}
	}

	/// The bundle to be checked for updates.
	fileprivate let app: App.Bundle

	/// The update fetched during this operation.
	fileprivate var update: App.Update?

	private var lookupTask: Task<Void, Never>?

	
	// MARK: - Operation
	
	override func execute() {
		if self.app.bundleIdentifier.contains("com.apple.InstallAssistant") {
			self.finish()
			return
		}

		self.lookupTask = Task {
			do {
				let entry = try await self.fetchAppInfo()
				guard !self.isCancelled else {
					self.finish()
					return
				}

				self.update = self.update(from: entry)
				self.finish()
			} catch {
				self.finish(with: error)
			}
		}
	}

	override func cancel() {
		self.lookupTask?.cancel()
		super.cancel()
	}
	
	
	// MARK: - Bundle Operations
	
	/// Returns the app store receipt path for the app at the given URL, if available.
	static func receiptPath(forAppAt url: URL) -> String? {
		AppStoreReceipt.url(forAppAt: url)?.path
	}
	
	/// Returns whether the app at the given URL is an iOS app wrapped to run on macOS.
	static func isIOSAppBundle(at url: URL) -> Bool {
		// iOS apps are wrapped inside a macOS bundle
		let path = receiptPath(forAppAt: url)
		return path?.contains("WrappedBundle") ?? false
	}

	/// Returns the App Store lookup entities to try, in priority order.
	static func lookupEntityTypes(forAppAt url: URL) -> [String] {
		return lookupEntityTypes(isIOSAppBundle: isIOSAppBundle(at: url))
	}

	static func lookupEntityTypes(isIOSAppBundle: Bool) -> [String] {
		// Wrapped iOS apps never resolve as native desktop software, so skip the guaranteed miss.
		if isIOSAppBundle {
			return ["macSoftware"]
		}

		return ["desktopSoftware", "macSoftware"]
	}
	
}

enum AppStoreReceipt {
	static func url(forAppAt appURL: URL) -> URL? {
		if let existingReceiptURL = existingReceiptURL(forAppAt: appURL) {
			return existingReceiptURL
		}

		guard appURL.pathExtension == "app" else { return nil }
		return standardReceiptURL(forAppAt: appURL)
	}

	static func standardReceiptURL(forAppAt appURL: URL) -> URL {
		appURL.appendingPathComponent("Contents/_MASReceipt/receipt", isDirectory: false)
	}

	private static func existingReceiptURL(forAppAt appURL: URL) -> URL? {
		let fileManager = FileManager.default
		guard let enumerator = fileManager.enumerator(
			at: appURL,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles]
		) else {
			return nil
		}

		for case let url as URL in enumerator {
			guard url.lastPathComponent == "receipt", url.deletingLastPathComponent().lastPathComponent == "_MASReceipt" else {
				continue
			}

			return url
		}

		return nil
	}
}

extension AppStoreUpdateCheckerOperation {
	
	/// Returns a proper update object from the given app store entry.
	private func update(from entry: AppStoreEntry) -> App.Update {
		let version = Version(versionNumber: entry.versionNumber, buildNumber: nil)
		let action: App.Update.Action = if Self.isIOSAppBundle(at: app.fileURL) || AppStoreUpdateSettings.alwaysPerformManualUpdates.active {
			// iOS Apps: Open App Store page where the user can update manually. The update operation does not work for them.
			.external(label: NSLocalizedString("AppStoreSource", comment: "The source name of apps loaded from the App Store."), block: { app in
				Self.openAppStorePage(for: entry)
			})
		} else {
			// Perform the update in-app
			.builtIn(block: { app in
				Self.updateApp(app, entry: entry)
			})

		}
		
		return App.Update(app: self.app, remoteVersion: version, minimumOSVersion: entry.minimumOSVersion, source: .appStore, date: entry.date, releaseNotes: entry.releaseNotes, updateAction: action)
	}
	
	private static func updateApp(_ app: App.Bundle, entry: AppStoreEntry) {
			do {
				try AppStoreUpdater.prepareForUpdates()
				AppStoreUpdater.enqueueUpdate(for: app, appStoreIdentifier: entry.appStoreIdentifier)
			} catch {
				Task { @MainActor in
					UpdateInstallHelperAlert.present(with: error, fallbackURL: entry.pageURL)
				}
			}
		}
	
	private static func openAppStorePage(for entry: AppStoreEntry) {
		NSWorkspace.shared.open(entry.pageURL)
	}
	
	/// Fetches update info using the App Store lookup entities in priority order.
	private func fetchAppInfo() async throws -> AppStoreEntry {
		// For native Mac apps, prefer `desktopSoftware` because `macSoftware` can return broader Catalyst or iOS metadata. Wrapped iOS apps skip the desktop request above.
		try await AppStoreLookupClient.shared.lookup(
			bundleIdentifier: app.bundleIdentifier,
			entityTypes: Self.lookupEntityTypes(forAppAt: app.fileURL)
		)
	}
		
}

// MARK: - Decoding

/// Object containing a list of App Store entries.
fileprivate struct EntryList: Decodable {
	
	/// The list of entries found while fetching information from the app store.
	let results: [AppStoreEntry]
	
}

/// Object representing a single entry in fetched information from the app store.
fileprivate struct AppStoreEntry: Decodable {
	
	/// The version number of the entry.
	let versionNumber: String
	
	/// The release notes associated with the entry.
	let releaseNotesContent: String?
	
	/// The release date of the entry.
	let date: Date?
	
	/// The link to the app store page.
	let pageURL: URL
	
	/// The identifier for this app in the App Store context.
	let appStoreIdentifier: UInt64
	
	/// The minimum OS version required to run this update.
	let minimumOSVersion: OperatingSystemVersion
	
	
	// MARK: - Decoding
	
	enum CodingKeys: String, CodingKey {
		case versionNumber = "version"
		case releaseNotes = "releaseNotes"
		case date = "currentVersionReleaseDate"
		case pageURL = "trackViewUrl"
		case appStoreIdentifier = "trackId"
		case minimumOSVersion = "minimumOsVersion"
	}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		
		self.versionNumber = try container.decode(String.self, forKey: .versionNumber)
		
		let releaseNotes = try container.decodeIfPresent(String.self, forKey: .releaseNotes)
		self.releaseNotesContent = releaseNotes?.replacingOccurrences(of: "\n", with: "<br>")
		
		if let date = try container.decodeIfPresent(String.self, forKey: .date) {
			self.date = Self.dateFormatter.date(from: date)
		} else {
			self.date = nil
		}
		
		let pageURL = try container.decode(String.self, forKey: .pageURL)
		guard let url = URL(string: pageURL.replacingOccurrences(of: "https", with: "macappstore")) else {
			throw malformedURLError
		}
		self.pageURL = url
		
		self.appStoreIdentifier = try container.decode(UInt64.self, forKey: .appStoreIdentifier)
		
		let osVersionString = try container.decode(String.self, forKey: .minimumOSVersion)
		self.minimumOSVersion = try OperatingSystemVersion(string: osVersionString)
	}
	
	
	// MARK: - Utilities
	
	// The release notes object derived from fetched texts.
	var releaseNotes: App.Update.ReleaseNotes? {
		if let releaseNotesContent = releaseNotesContent {
			return .html(string: releaseNotesContent)
		}
		
		return nil
	}
	
	private static let dateFormatter: DateFormatter = {
		// Setup date formatter
		let dateFormatter = DateFormatter()
		dateFormatter.locale = Locale(identifier: "en_US")
		
		// Example of the date format: Mon, 28 Nov 2016 14:00:00 +0100
		// This is problematic, because some developers use other date formats
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
		
		return dateFormatter
	}()
	
}
