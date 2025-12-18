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

    private var loadingTask: Task<Void, Never>?

    private init(testMode: Bool = false) {
        if testMode {
            return
        }

        loadingTask = Task {
            await self.load()
        }
    }

    /// Returns a new repository with up to date update information.
    static func newRepository() -> UpdateRepository {
        UpdateRepository()
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
        Task {
            _ = await self.loadingTask?.value
            handler(bundle, self.entry(for: bundle))
        }
    }

    /// Checks for local changelog files in the app bundle.
    func localChangelog(for bundle: App.Bundle) -> App.Update.ReleaseNotes? {
        let candidates = ["CHANGELOG", "Changelog", "changelog", "HISTORY", "History", "history", "Changes"]
        let extensions = ["md", "txt", "rtf", "html"]

        for name in candidates {
            for ext in extensions {
                if let nsBundle = Bundle(url: bundle.fileURL),
                   let url = nsBundle.url(forResource: name, withExtension: ext)
                {
                    return .url(url: url)
                }
            }
        }

        return nil
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
    /// A set of bundle identifiers for which update checking is currently not supported.
    private var unsupportedBundleIdentifiers: Set<String> = []

    // MARK: - Cache Handling

    /// Loads the repository data asynchronously.
    private func load() async {
        await withTaskGroup(of: Void.self) { group in
            for urlType in RemoteURL.allCases {
                group.addTask {
                    await self.fetch(urlType)
                }
            }
        }
    }

    private func fetch(_ urlType: RemoteURL) async {
        // Check for valid cache file
        let timeInterval = UserDefaults.standard.double(forKey: urlType.userDefaultsKey) as TimeInterval
        if timeInterval > 0, timeInterval.distance(to: Date.timeIntervalSinceReferenceDate) < Self.cacheInvalidationDuration,
           let cacheURL = urlType.cacheURL, let data = try? Data(contentsOf: cacheURL)
        {
            handle(data, for: urlType)
            return
        }

        // Fetch data from server
        do {
            let (data, _) = try await session.data(from: urlType.url)
            handle(data, for: urlType)

            // Store in cache
            if let cacheURL = urlType.cacheURL {
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheURL)
                UserDefaults.standard.setValue(Date.timeIntervalSinceReferenceDate, forKey: urlType.userDefaultsKey)
            }
        } catch {
            if let data = urlType.fallbackData {
                handle(data, for: urlType)
            }
        }
    }

    private func handle(_ data: Data, for urlType: RemoteURL) {
        switch urlType {
        case .repository:
            parse(data)
        case .unsupportedApps:
            loadUnsupportedApps(from: data)
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
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    /// Parses the given repository data and finishes loading.
    private func parse(_ repositoryData: Data) {
        do {
            let entries = try JSONDecoder().decode([Entry].self, from: repositoryData)

            // Filter out any entries without application name
            self.entries = entries.filter { !$0.names.isEmpty }
            rebuildIndex()
        } catch {
            entries = []
            nameIndex = [:]
            bundleIdentifierIndex = [:]
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
                nil
            case .unsupportedApps:
                try! Data(contentsOf: Bundle.main.url(forResource: "ExcludedAppIdentifiers", withExtension: "plist")!)
            }
        }

        /// The user defaults key used for storing the cache access information.
        var userDefaultsKey: String {
            rawValue + UpdateDateKey
        }
    }
}
