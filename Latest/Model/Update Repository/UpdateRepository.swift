//
//  UpdateRepository.swift
//  Latest
//
//  Created by Max Langer on 01.10.23.
//  Copyright © 2023 Max Langer. All rights reserved.
//

import AppKit
import OSLog

/// User defaults key for storing the last cache update date.
private let UpdateDateKey = "UpdateDateKey"

private let updateRepositoryLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "com.max-langer.Latest",
	category: "Repository"
)

/// A storage that fetches update information from an online source.
///
/// Can be asked for update version information for a given application bundle.
class UpdateRepository: @unchecked Sendable {

	private static let reusableRepositories = UpdateRepositoryReuseCache()

	/// Queue on which requests will be handled.
	private var queue = DispatchQueue(label: "repositoryQueue")

	private let dataSource = RemoteDataSource()

	// MARK: - Init

	let fetchCompletedGroup = DispatchGroup()

	fileprivate let createdAt = Date.timeIntervalSinceReferenceDate

	private var finalizeHandler: (@Sendable (UpdateRepository, Bool) -> Void)?

	fileprivate init(finalizeHandler: (@Sendable (UpdateRepository, Bool) -> Void)? = nil) {
		self.finalizeHandler = finalizeHandler

		fetchCompletedGroup.enter()
		fetchCompletedGroup.notify(queue: .main) { [weak self] in
			self?.finalize()
		}
	}

	/// Returns a new repository with up to date update information.
	static func newRepository() -> UpdateRepository {
		reusableRepositories.repository()
	}


	// MARK: - Accessors

	/// Returns update information for the given bundle.
	func updateInfo(for bundle: App.Bundle, handler: @escaping @Sendable (_ bundle: App.Bundle, _ version: Version?, _ minimumOSVersion: OperatingSystemVersion?, _ releaseNotes: App.Update.ReleaseNotes?) -> Void) {
		let checkApp: @Sendable () -> Void = { [weak self] in
			guard let self, let entry = self.entry(for: bundle) else {
				handler(bundle, nil, nil, nil)
				return
			}
			return handler(bundle, entry.version, entry.minimumOSVersion, entry.releaseNotes)
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

	/// A list of requests being performed while the repository was still fetching data.
	///
	/// It also acts as a flag for whether initialization finished. The array is initialized when the repository is created. It will be set to nil once `finalize()` is being called.
	private var pendingRequests: [@Sendable () -> Void]? = []

	/// Matches app bundles against loaded repository entries.
	private var entryMatcher = EntryMatcher(entries: [], unsupportedBundleIdentifiers: [])

	private var loadedURLTypes = Set<RemoteURL>()

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

			let isReusable = self.loadedURLTypes == Set(RemoteURL.allCases)
			updateRepositoryLogger.info(
				"Finalized update repository. loadedURLTypes=\(self.loadedURLTypes.count, privacy: .public) reusable=\(isReusable, privacy: .public)"
			)
			let finalizeHandler = self.finalizeHandler
			self.finalizeHandler = nil
			finalizeHandler?(self, isReusable)
		}
	}

	/// Returns a repository entry for the given name, if available.
	private func entry(for bundle: App.Bundle) -> Entry? {
		entryMatcher.entry(for: bundle)
	}

	static func preferredEntry(from possibleEntries: [Entry], for bundleIdentifier: String) -> Entry? {
		EntryMatcher.preferredEntry(from: possibleEntries, for: bundleIdentifier)
	}


	// MARK: - Cache Handling

	/// Loads the repository data.
	fileprivate func load() {
		updateRepositoryLogger.info("Loading update repository sources")
		RemoteURL.allCases.forEach { urlType in
			self.fetchCompletedGroup.enter()

			dataSource.load(urlType) { [weak self] data in
				guard let self else { return }

				self.queue.async {
					defer {
						self.fetchCompletedGroup.leave()
					}
					guard let data else {
						updateRepositoryLogger.info("Repository source \(urlType.rawValue, privacy: .public) returned no data")
						return
					}

					self.loadedURLTypes.insert(urlType)
					updateRepositoryLogger.info("Loaded repository source \(urlType.rawValue, privacy: .public)")

					switch urlType {
					case .repository:
						self.parse(data)
					case .unsupportedApps:
						self.loadUnsupportedApps(from: data)
					}
				}
			}
		}
	}

	/// Parses the given repository data and finishes loading.
	private func parse(_ repositoryData: Data) {
		do {
			let entries = try JSONDecoder().decode([Entry].self, from: repositoryData)

			entryMatcher.update(entries: entries.filter { !$0.names.isEmpty })
		} catch {
			entryMatcher.update(entries: [])
		}
	}

	private func loadUnsupportedApps(from data: Data) {
		guard let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] else {
			entryMatcher.update(unsupportedBundleIdentifiers: [])
			return
		}

		entryMatcher.update(unsupportedBundleIdentifiers: Set(propertyList))
	}


	// MARK: - Repository URL

	fileprivate enum RemoteURL: String, CaseIterable {

		/// The URL update information is being fetched from.
		case repository = "RepositoryCache"

		/// Duration after which the cache will be invalidated. (1 hour in seconds)
		case unsupportedApps = "UnsupportedApps"

		/// The actual remote URL the information can be fetched from.
		var url: URL? {
			let urlString = switch self {
			case .repository:
				"https://formulae.brew.sh/api/cask.json"
			case .unsupportedApps:
				"https://raw.githubusercontent.com/mangerlahn/Latest/main/Latest/Resources/ExcludedAppIdentifiers.plist"
			}

			return URL(string: urlString)
		}

		/// The URL where the cached data will be stored.
		var cacheURL: URL? {
			let name = rawValue
			let pathExtension = switch self {
			case .repository:
				"json"
			case .unsupportedApps:
				"plist"
			}

			return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
				.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.max-langer.Latest")
				.appendingPathComponent(name).appendingPathExtension(pathExtension)
		}

		/// Possible fallback data within the binary if the remote content could not be fetched.
		var fallbackData: Data? {
			switch self {
			case .repository:
				return nil
			case .unsupportedApps:
				guard let fallbackURL = Bundle.main.url(forResource: "ExcludedAppIdentifiers", withExtension: "plist") else {
					return nil
				}

				return try? Data(contentsOf: fallbackURL)
			}
		}

		/// The user defaults key used for storing the cache access information.
		var userDefaultsKey: String {
			rawValue + UpdateDateKey
		}

	}

}

private final class UpdateRepositoryReuseCache: @unchecked Sendable {

	private static let reuseDuration: TimeInterval = 60 * 60

	private let lock = NSLock()

	private var reusableRepository: UpdateRepository?

	private var repositoryCreatedAt: TimeInterval = 0

	func repository() -> UpdateRepository {
		if let repository = cachedRepository() {
			return repository
		}

		let repository = UpdateRepository { [weak self] repository, isReusable in
			self?.store(repository, isReusable: isReusable)
		}
		repository.load()
		repository.fetchCompletedGroup.leave()

		return repository
	}

	private func cachedRepository() -> UpdateRepository? {
		lock.withCriticalScope {
			guard let reusableRepository else { return nil }

			let age = repositoryCreatedAt.distance(to: Date.timeIntervalSinceReferenceDate)
			return age < Self.reuseDuration ? reusableRepository : nil
		}
	}

	private func store(_ repository: UpdateRepository, isReusable: Bool) {
		guard isReusable else { return }

		lock.withCriticalScope {
			guard repository.createdAt >= repositoryCreatedAt else { return }

			self.reusableRepository = repository
			self.repositoryCreatedAt = repository.createdAt
		}
	}

}

private struct EntryMatcher {

	private var entriesByName: [String: [UpdateRepository.Entry]]
	private var unsupportedBundleIdentifiers: Set<String>

	init(entries: [UpdateRepository.Entry], unsupportedBundleIdentifiers: Set<String>) {
		self.entriesByName = Self.entriesByName(entries)
		self.unsupportedBundleIdentifiers = unsupportedBundleIdentifiers
	}

	mutating func update(entries: [UpdateRepository.Entry]) {
		self.entriesByName = Self.entriesByName(entries)
	}

	mutating func update(unsupportedBundleIdentifiers: Set<String>) {
		self.unsupportedBundleIdentifiers = unsupportedBundleIdentifiers
	}

	func entry(for bundle: App.Bundle) -> UpdateRepository.Entry? {
		// Don't return an entry for unsupported apps.
		guard !unsupportedBundleIdentifiers.contains(bundle.bundleIdentifier) else { return nil }

		// Finding the correct entry is not trivial as there is no bundle identifier stored in an entry. We have a list of app names (could be ambiguous) and a list of bundle identifier guesses.
		// However, both app names and bundle identifiers may occur in more than one entry:
		// - App Names: Might occur multiple times for similar apps (Telegram.app for Desktop vs. Telegram.app for Mac)
		// - Bundle Identifiers: Might occur multiple times for apps in bundles (com.microsoft.word in Word.app and Office bundle)
		//
		// Strategy: Find all entries that point to the given app name. If only one entry comes up, return that. Otherwise, try to match bundle identifiers to narrow it down.
		let name = bundle.fileURL.lastPathComponent.lowercased()
		let possibleEntries = (entriesByName[name] ?? []).filter {
			!$0.requiresBundleIdentifierMatch || $0.bundleIdentifiers.contains(bundle.bundleIdentifier)
		}

		return Self.preferredEntry(from: possibleEntries, for: bundle.bundleIdentifier)
	}

	static func preferredEntry(from possibleEntries: [UpdateRepository.Entry], for bundleIdentifier: String) -> UpdateRepository.Entry? {
		guard !possibleEntries.isEmpty else { return nil }
		if possibleEntries.count == 1 {
			return possibleEntries.first
		}

		var matchingIdentifierEntries = [UpdateRepository.Entry]()
		matchingIdentifierEntries.reserveCapacity(possibleEntries.count)
		for entry in possibleEntries where entry.bundleIdentifiers.contains(bundleIdentifier) {
			matchingIdentifierEntries.append(entry)
		}
		if matchingIdentifierEntries.count == 1 {
			return matchingIdentifierEntries.first
		}

		let narrowedEntries = matchingIdentifierEntries.isEmpty ? possibleEntries : matchingIdentifierEntries
		var stableEntries = [UpdateRepository.Entry]()
		stableEntries.reserveCapacity(narrowedEntries.count)
		for entry in narrowedEntries where entry.isStableRelease {
			stableEntries.append(entry)
		}
		if stableEntries.count == 1 {
			return stableEntries.first
		}

		return uniqueShortestTokenEntry(in: stableEntries)
	}

	private static func entriesByName(_ entries: [UpdateRepository.Entry]) -> [String: [UpdateRepository.Entry]] {
		entries.reduce(into: [String: [UpdateRepository.Entry]]()) { entriesByName, entry in
			for name in entry.names {
				entriesByName[name.lowercased(), default: []].append(entry)
			}
		}
	}

	private static func uniqueShortestTokenEntry(in entries: [UpdateRepository.Entry]) -> UpdateRepository.Entry? {
		var shortestEntry: UpdateRepository.Entry?
		var shortestTokenLength: Int?
		var shortestTokenLengthHasTie = false

		for entry in entries {
			let tokenLength = entry.token.count
			guard let currentShortestTokenLength = shortestTokenLength else {
				shortestEntry = entry
				shortestTokenLength = tokenLength
				continue
			}

			if tokenLength == currentShortestTokenLength {
				shortestTokenLengthHasTie = true
			} else if tokenLength < currentShortestTokenLength {
				shortestEntry = entry
				shortestTokenLength = tokenLength
				shortestTokenLengthHasTie = false
			}
		}

		return shortestTokenLengthHasTie ? nil : shortestEntry
	}

}

private final class RemoteDataSource: @unchecked Sendable {

	func load(_ urlType: UpdateRepository.RemoteURL, completion: @escaping @Sendable (Data?) -> Void) {
		let cache = UpdateRepositoryCache(cacheURL: urlType.cacheURL, userDefaultsKey: urlType.userDefaultsKey)
		if let data = cache.cachedData() {
			completion(data)
			return
		}

		guard let url = urlType.url else {
			completion(nil)
			return
		}

		let task = URLSession(configuration: .default).dataTask(with: url) { data, _, _ in
			guard let data = data ?? urlType.fallbackData else {
				completion(nil)
				return
			}

			cache.store(data)
			completion(data)
		}
		task.resume()
	}

}
