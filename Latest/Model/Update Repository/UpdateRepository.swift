//
//  UpdateRepository.swift
//  Latest
//
//  Created by Max Langer on 01.10.23.
//  Copyright © 2023 Max Langer. All rights reserved.
//

import AppKit

/// User defaults key for storing the last cache update date.
private let UpdateDateKey = "UpdateDateKey"

/// A storage that fetches update information from an online source.
///
/// Can be asked for update version information for a given application bundle.
class UpdateRepository: @unchecked Sendable {
	
	/// Duration after which the cache will be invalidated. (1 hour in seconds)
	private static let cacheInvalidationDuration: Double = 1 * 60 * 60
	
	/// Queue on which requests will be handled.
	private let queue = DispatchQueue(label: "repositoryQueue")
	
	/// Session used for fetching repository data.
	private lazy var session: URLSession = {
		let configuration = URLSessionConfiguration.default
		configuration.httpMaximumConnectionsPerHost = 4
		return URLSession(configuration: configuration)
	}()

	// MARK: - Init
	
	let fetchCompletedGroup = DispatchGroup()
	
	private init(testMode: Bool = false) {
		if testMode {
			// Mark repository as loaded; tests can inject entries directly.
			self.pendingRequests = nil
			return
		}
		
		fetchCompletedGroup.enter()
		fetchCompletedGroup.notify(queue: .main) { [weak self] in
			self?.finalize()
		}
	}
	
	/// Returns a new repository with up to date update information.
	static func newRepository() -> UpdateRepository {
		let repository = UpdateRepository()
		repository.load()
		repository.fetchCompletedGroup.leave()
		
		return repository
	}
	
	#if DEBUG
	static func makeForTesting(entries: [Entry], unsupportedBundleIdentifiers: Set<String> = []) -> UpdateRepository {
		let repository = UpdateRepository(testMode: true)
		repository.entries = entries
		repository.unsupportedBundleIdentifiers = unsupportedBundleIdentifiers
		repository.rebuildIndex()
		return repository
	}
	#endif
	
	
	// MARK: - Accessors
	
	/// Returns update information for the given bundle.
	func updateInfo(for bundle: App.Bundle, handler: @escaping @Sendable (_ bundle: App.Bundle, _ entry: Entry?) -> Void) {
		let checkApp: @Sendable () -> Void = {
			handler(bundle, self.entry(for: bundle))
		}
		
		/// Entries are still being fetched, add the request to the queue.
		queue.async { [weak self] in
			guard let self else { return }
			
			if self.pendingRequests != nil {
				self.pendingRequests?.append(checkApp)
			} else {
				checkApp()
			}
		}
	}
	
	/// List of entries stored within the repository.
	private var entries = [Entry]()
	
	/// Index of normalized application names to matching repository entries.
	private var nameIndex = [String: [Entry]]()
	
	/// Index of bundle identifiers to matching repository entries.
	private var bundleIdentifierIndex = [String: [Entry]]()
	
	/// A list of requests being performed while the repository was still fetching data.
	///
	/// It also acts as a flag for whether initialization finished. The array is initialized when the repository is created. It will be set to nil once `finalize()` is being called.
	private var pendingRequests: [ @Sendable () -> Void ]? = []
	
	/// A set of bundle identifiers for which update checking is currently not supported.
	private var unsupportedBundleIdentifiers: Set<String> = []
	
	/// Sets the given entries and performs pending requests.
	private func finalize() {
		queue.async { [weak self] in
			guard let self else { return }
			guard let pendingRequests else {
				fatalError("Finalize must only be called once!")
			}
			
			// Perform any pending requests
			pendingRequests.forEach { request in
				request()
			}
			
			// Mark repository as loaded.
			self.pendingRequests = nil
		}
	}
	
	/// Returns a repository entry for the given name, if available.
	private func entry(for bundle: App.Bundle) -> Entry? {
		// Don't return an entry for unsupported apps
		guard !unsupportedBundleIdentifiers.contains(bundle.bundleIdentifier) else { return nil }
		
		let nameKeys = Self.normalizedNameKeys(for: bundle)
		var candidates: [Entry] = nameKeys.flatMap { nameIndex[$0] ?? [] }
		
		if candidates.isEmpty, let byBundleID = bundleIdentifierIndex[bundle.bundleIdentifier] {
			candidates = byBundleID
		}
		
		let uniqueCandidates = Self.unique(candidates)
		guard !uniqueCandidates.isEmpty else { return nil }
		if uniqueCandidates.count == 1 { return uniqueCandidates[0] }
		
		// Match bundle identifier
		let byBundleID = uniqueCandidates.filter { $0.bundleIdentifiers.contains(bundle.bundleIdentifier) }
		if byBundleID.count == 1 { return byBundleID[0] }
		
		// As a last resort, try to disambiguate by name matching strength.
		let fileName = Self.normalizeName(bundle.fileURL.lastPathComponent)
		let fileNameNoExtension = Self.normalizeName(bundle.fileURL.deletingPathExtension().lastPathComponent)
		let displayName = Self.normalizeName(bundle.name)
		
		var best: (entry: Entry, score: Int)?
		var ties = 0
		for entry in uniqueCandidates {
			var score = 0
			if entry.bundleIdentifiers.contains(bundle.bundleIdentifier) { score += 10 }
			
			let entryNames = entry.names.map(Self.normalizeName)
			if entryNames.contains(fileName) { score += 4 }
			if entryNames.contains(fileNameNoExtension) { score += 3 }
			if entryNames.contains(displayName) { score += 2 }
			
			if let currentBest = best {
				if score > currentBest.score {
					best = (entry, score)
					ties = 0
				} else if score == currentBest.score {
					ties += 1
				}
			} else {
				best = (entry, score)
			}
		}
		
		guard let best, best.score > 0, ties == 0 else { return nil }
		return best.entry
	}
	
	private static func normalizeName(_ name: String) -> String {
		return name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
	}
	
	private static func normalizedNameKeys(for bundle: App.Bundle) -> [String] {
		let fileWithExtension = normalizeName(bundle.fileURL.lastPathComponent)
		let fileNoExtension = normalizeName(bundle.fileURL.deletingPathExtension().lastPathComponent)
		let displayName = normalizeName(bundle.name)
		
		var keys = [fileWithExtension, fileNoExtension, displayName]
		
		// Some sources include the `.app` suffix while others don't; include both variants.
		if fileWithExtension.hasSuffix(".app") {
			keys.append(String(fileWithExtension.dropLast(4)))
		} else {
			keys.append(fileWithExtension + ".app")
		}
		
		if displayName.hasSuffix(".app") {
			keys.append(String(displayName.dropLast(4)))
		} else {
			keys.append(displayName + ".app")
		}
		
		return Array(Set(keys))
	}
	
	private static func normalizedNameKeys(for entryName: String) -> [String] {
		let raw = normalizeName(entryName)
		if raw.hasSuffix(".app") {
			return Array(Set([raw, String(raw.dropLast(4))]))
		}
		return Array(Set([raw, raw + ".app"]))
	}
	
	private static func unique(_ entries: [Entry]) -> [Entry] {
		var seenTokens = Set<String>()
		var uniqueEntries: [Entry] = []
		uniqueEntries.reserveCapacity(entries.count)
		for entry in entries where seenTokens.insert(entry.token).inserted {
			uniqueEntries.append(entry)
		}
		return uniqueEntries
	}
	
	
	// MARK: - Cache Handling
	
	/// Loads the repository data.
	private func load() {
		RemoteURL.allCases.forEach { urlType in
			self.fetchCompletedGroup.enter()
			
			@Sendable func handle(_ data: Data) {
				switch urlType {
				case .repository:
					parse(data)
				case .unsupportedApps:
					loadUnsupportedApps(from: data)
				}
				
				self.fetchCompletedGroup.leave()
			}
			
			// Check for valid cache file
			let timeInterval = UserDefaults.standard.double(forKey: urlType.userDefaultsKey) as TimeInterval
			if timeInterval > 0, timeInterval.distance(to: Date.timeIntervalSinceReferenceDate) < Self.cacheInvalidationDuration,
			   let cacheURL = urlType.cacheURL, let data = try? Data(contentsOf: cacheURL)  {
				handle(data)
				return
			}
			
			// Fetch data from server
			let task = session.dataTask(with: urlType.url) { [weak self] data, _, _ in
				guard let self else { return }
				guard let data = data ?? urlType.fallbackData else {
					self.fetchCompletedGroup.leave()
					return
				}
				
				handle(data)
				
				// Store in cache
				if let cacheURL = urlType.cacheURL {
					try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
					try? data.write(to: cacheURL)
					UserDefaults.standard.setValue(Date.timeIntervalSinceReferenceDate, forKey: urlType.userDefaultsKey)
				}
			}
			task.resume()

		}
	}
	
	/// Parses the given repository data and finishes loading.
	private func parse(_ repositoryData: Data) {
		do {
			let entries = try JSONDecoder().decode([Entry].self, from: repositoryData)
		
			// Filter out any entries without application name
			self.entries = entries.filter { !$0.names.isEmpty }
			self.rebuildIndex()
		} catch {
			self.entries = []
			self.nameIndex = [:]
			self.bundleIdentifierIndex = [:]
		}
	}
	
	private func loadUnsupportedApps(from data: Data) {
		guard let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] else {
			unsupportedBundleIdentifiers = []
			return
		}
		unsupportedBundleIdentifiers = Set(propertyList)
	}
	
	private func rebuildIndex() {
		var nameIndex = [String: [Entry]]()
		var bundleIdentifierIndex = [String: [Entry]]()
		
		for entry in entries {
			for name in entry.names {
				for key in Self.normalizedNameKeys(for: name) {
					nameIndex[key, default: []].append(entry)
				}
			}
			
			for bundleIdentifier in entry.bundleIdentifiers {
				bundleIdentifierIndex[bundleIdentifier, default: []].append(entry)
			}
		}
		
		self.nameIndex = nameIndex
		self.bundleIdentifierIndex = bundleIdentifierIndex
	}

	
	// MARK: - Repository URL
	
	private enum RemoteURL: String, CaseIterable {
		
		/// The URL update information is being fetched from.
		case repository = "RepositoryCache"
		
		/// Duration after which the cache will be invalidated. (1 hour in seconds)
		case unsupportedApps = "UnsupportedApps"
		
		/// The actual remote URL the information can be fetched from.
		var url: URL {
			let urlString = switch self {
			case .repository:
				"https://formulae.brew.sh/api/cask.json"
			case .unsupportedApps:
				"https://raw.githubusercontent.com/mangerlahn/Latest/main/Latest/Resources/ExcludedAppIdentifiers.plist"
			}
			
			return URL(string: urlString)!
		}
		
		/// The URL where the cached data will be stored.
		var cacheURL: URL? {
			guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
			let name = rawValue
			let pathExtension = switch self {
			case .repository:
				"json"
			case .unsupportedApps:
				"plist"
			}
			
			return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
				.appendingPathComponent(bundleIdentifier)
				.appendingPathComponent(name).appendingPathExtension(pathExtension)
		}
		
		/// Possible fallback data within the binary if the remote content could not be fetched.
		var fallbackData: Data? {
			switch self {
			case .repository:
				return nil
			case .unsupportedApps:
				return try! Data(contentsOf: Bundle.main.url(forResource: "ExcludedAppIdentifiers", withExtension: "plist")!)
			}
		}
		
		/// The user defaults key used for storing the cache access information.
		var userDefaultsKey: String {
			rawValue + UpdateDateKey
		}
		
	}

}
