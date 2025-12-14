//
//  MacAppStoreUpdateCheckerOperation.swift
//  Latest
//
//  Created by Max Langer on 03.10.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import Cocoa

let MalformedURLError = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: nil)

/// The operation for checking for updates for a Mac App Store app.
class MacAppStoreUpdateCheckerOperation: StatefulOperation, UpdateCheckerOperation, @unchecked Sendable {
	
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
		self.updateCheckerCompletionBlock = completionBlock
		
		super.init()

		self.completionBlock = { [weak self] in
			guard let self else { return }
			guard !self.isCancelled else { return }
			
			if let update = self.update {
				self.updateCheckerCompletionBlock(.success(update))
			} else {
				self.updateCheckerCompletionBlock(.failure(self.error ?? LatestError.updateInfoUnavailable))
			}
		}
	}

	/// The bundle to be checked for updates.
	fileprivate let app: App.Bundle

	/// The update fetched during this operation.
	fileprivate var update: App.Update?
	
	private let updateCheckerCompletionBlock: UpdateCheckerCompletionBlock

	
	// MARK: - Operation
	
	override func execute() {
		if self.app.bundleIdentifier.contains("com.apple.InstallAssistant") {
			self.finish()
			return
		}
		
		self.fetchAppInfo { result in
			switch result {
			// Process fetched info
			case .success(let entry):
				self.update = self.update(from: entry)
				self.finish()

			// Forward fetch error
			case .failure(let error):
				self.finish(with: error)

			}
		}
	}
	
	
	// MARK: - Bundle Operations
	
	/// Returns the app store receipt path for the app at the given URL, if available.
	static fileprivate func receiptPath(forAppAt url: URL) -> String? {
		return url.appendingPathComponent("Contents/_MASReceipt/receipt").path
	}
	
	/// Returns whether the app at the given URL is an iOS app wrapped to run on macOS.
	static fileprivate func isIOSAppBundle(at url: URL) -> Bool {
		// iOS apps are wrapped inside a macOS bundle
		let path = receiptPath(forAppAt: url)
		return path?.contains("WrappedBundle") ?? false
	}
	
}

extension MacAppStoreUpdateCheckerOperation {
	
	/// Returns a proper update object from the given app store entry.
	private func update(from entry: AppStoreEntry) -> App.Update {
		let version = Version(versionNumber: entry.versionNumber, buildNumber: nil)
		let action: App.Update.Action = if Self.isIOSAppBundle(at: app.fileURL) {
			// iOS Apps: Open App Store page where the user can update manually. The update operation does not work for them.
			.external(label: NSLocalizedString("AppStoreSource", comment: "The source name of apps loaded from the App Store."), block: { app in
				NSWorkspace.shared.open(entry.pageURL)
			})
		} else {
			// Perform the update in-app
			.builtIn(block: { app in
				UpdateQueue.shared.addOperation(MacAppStoreUpdateOperation(bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier, appStoreIdentifier: entry.appStoreIdentifier))
			})

		}
		
		return App.Update(app: self.app, remoteVersion: version, minimumOSVersion: entry.minimumOSVersion, source: .appStore, date: entry.date, releaseNotes: entry.releaseNotes, updateAction: action)
	}
	
	/// Fetches update info and returns the result in the given completion handler.
	private func fetchAppInfo(completion: @escaping @Sendable (_ result: Result<AppStoreEntry, Error>) -> ()) {
		AppStoreLookupBatcher.shared.lookup(bundleIdentifier: self.app.bundleIdentifier, completion: completion)
	}
		
}

// MARK: - Decoding

/// Object containing a list of App Store entries.
fileprivate struct EntryList: Decodable {
	
	/// The list of entries found while fetching information from the app store.
	let results: [FailableDecodable<AppStoreEntry>]
	
}

/// Object representing a single entry in fetched information from the app store.
fileprivate struct AppStoreEntry: Decodable {
	
	/// The bundle identifier of the app.
	let bundleIdentifier: String?
	
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
		case bundleIdentifier = "bundleId"
		case versionNumber = "version"
		case releaseNotes = "releaseNotes"
		case date = "currentVersionReleaseDate"
		case pageURL = "trackViewUrl"
		case appStoreIdentifier = "trackId"
		case minimumOSVersion = "minimumOsVersion"
	}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		
		self.bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
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
			throw MalformedURLError
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

// MARK: - Batched Lookup

/// Batches App Store lookups for multiple bundle identifiers to reduce network overhead during large update checks.
fileprivate final class AppStoreLookupBatcher: @unchecked Sendable {
	static let shared = AppStoreLookupBatcher()
	
	typealias Completion = @Sendable (Result<AppStoreEntry, Error>) -> Void
	
	private let queue = DispatchQueue(label: "appStoreLookupBatcherQueue")
	private let session: URLSession = {
		let configuration = URLSessionConfiguration.default
		configuration.httpMaximumConnectionsPerHost = 4
		return URLSession(configuration: configuration)
	}()
	
	/// Results cached for this process run, keyed by (country, bundleIdentifier).
	private var cache = [CacheKey: Result<AppStoreEntry, Error>]()
	
	/// Bundle identifiers currently waiting to be requested.
	private var pending = [CacheKey: [Completion]]()
	
	/// Bundle identifiers currently being requested.
	private var inFlight = Set<CacheKey>()
	
	private var scheduledFlush: DispatchWorkItem?
	
	private struct CacheKey: Hashable {
		let country: String
		let bundleIdentifier: String
	}
	
	func lookup(bundleIdentifier: String, completion: @escaping Completion) {
		let country = Locale.current.region?.identifier ?? "US"
		let key = CacheKey(country: country, bundleIdentifier: bundleIdentifier)
		
		queue.async {
			if let cached = self.cache[key] {
				DispatchQueue.global().async { completion(cached) }
				return
			}
			
			self.pending[key, default: []].append(completion)
			self.scheduleFlush()
		}
	}
	
	private func scheduleFlush() {
		if scheduledFlush != nil { return }
		
		let item = DispatchWorkItem { [weak self] in
			self?.flush()
		}
		scheduledFlush = item
		
		// Small delay to collect multiple requests from concurrently executing operations.
		queue.asyncAfter(deadline: .now() + 0.05, execute: item)
	}
	
	private func flush() {
		queue.async {
			self.scheduledFlush = nil
			
			let keysToRequest = self.pending.keys.filter { !self.inFlight.contains($0) }
			guard !keysToRequest.isEmpty else { return }
			
			keysToRequest.forEach { self.inFlight.insert($0) }
			
			// Group by country and split into chunks to avoid overly large requests.
			let groupedByCountry = Dictionary(grouping: keysToRequest, by: { $0.country })
			for (_, keys) in groupedByCountry {
				for chunk in keys.chunked(into: 50) {
					self.performLookup(for: chunk, entityType: "desktopSoftware") { [weak self] desktopResult in
						guard let self else { return }
						
						switch desktopResult {
						case .failure(let error):
							self.finish(chunk, with: .failure(error))
							
						case .success(let desktopResults):
							// Any missing results are retried with the broader entity type.
							let missing = chunk.filter { desktopResults[$0] == nil }
							if missing.isEmpty {
								self.finish(chunk, with: .success(desktopResults))
								return
							}
							
							self.performLookup(for: missing, entityType: "macSoftware") { [weak self] macResult in
								guard let self else { return }
								
								switch macResult {
								case .failure(let error):
									// Preserve successful desktop results, only fail missing keys.
									var combined = desktopResults
									self.finish(chunk, with: .success(combined), missingError: error, missingKeys: missing)
									
								case .success(let macResults):
									var combined = desktopResults
									macResults.forEach { combined[$0.key] = $0.value }
									self.finish(chunk, with: .success(combined))
								}
							}
						}
					}
				}
			}
		}
	}
	
	private func performLookup(for keys: [CacheKey], entityType: String, completion: @escaping @Sendable (Result<[CacheKey: AppStoreEntry], Error>) -> Void) {
		guard let endpoint = URL(string: "https://itunes.apple.com/lookup") else {
			completion(.failure(MalformedURLError))
			return
		}
		
		guard let country = keys.first?.country, keys.allSatisfy({ $0.country == country }) else {
			completion(.failure(MalformedURLError))
			return
		}
		
		let bundleIDs = keys.map { $0.bundleIdentifier }.joined(separator: ",")
		var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
		components?.queryItems = [
			URLQueryItem(name: "entity", value: entityType),
			URLQueryItem(name: "country", value: country),
			URLQueryItem(name: "bundleId", value: bundleIDs)
		]
		
		guard let url = components?.url else {
			completion(.failure(MalformedURLError))
			return
		}
		
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
		let dataTask = session.dataTask(with: request) { data, _, error in
			guard error == nil, let data else {
				completion(.failure(error ?? MalformedURLError))
				return
			}
			
			do {
				let list = try JSONDecoder().decode(EntryList.self, from: data)
				let decoded = list.results.compactMap { $0.base }
				var mapped = [CacheKey: AppStoreEntry]()
				for entry in decoded {
					guard let bundleIdentifier = entry.bundleIdentifier else { continue }
					let key = CacheKey(country: country, bundleIdentifier: bundleIdentifier)
					mapped[key] = entry
				}
				completion(.success(mapped))
			} catch {
				completion(.failure(error))
			}
		}
		
		dataTask.resume()
	}
	
	private func finish(_ requested: [CacheKey], with result: Result<[CacheKey: AppStoreEntry], Error>, missingError: Error? = nil, missingKeys: [CacheKey] = []) {
		queue.async {
			for key in requested {
				let resolved: Result<AppStoreEntry, Error> = switch result {
				case .failure(let error):
					.failure(error)
				case .success(let results):
					if let entry = results[key] {
						.success(entry)
					} else if missingError != nil, missingKeys.contains(key) {
						.failure(missingError!)
					} else {
						.failure(LatestError.updateInfoUnavailable)
					}
				}
				
				self.cache[key] = resolved
				self.inFlight.remove(key)
				
				let completions = self.pending.removeValue(forKey: key) ?? []
				if !completions.isEmpty {
					DispatchQueue.global().async {
						completions.forEach { $0(resolved) }
					}
				}
			}
		}
	}
}

fileprivate extension Array {
	func chunked(into size: Int) -> [[Element]] {
		guard size > 0 else { return [self] }
		var result: [[Element]] = []
		result.reserveCapacity((count + size - 1) / size)
		var index = startIndex
		while index < endIndex {
			let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
			result.append(Array(self[index..<end]))
			index = end
		}
		return result
	}
}
