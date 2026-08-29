//
//  ReleaseNotesMemoryCache.swift
//  Latest
//
//  Structural split from the original implementation.
//

import Foundation

actor ReleaseNotesGitHubCache {
	private struct Entry {
		let data: Data
		let expiresAt: Date
		var lastAccessedAt: Date
	}

	private var entries = [URL: Entry]()
	private var inFlightTasks = [URL: Task<Data, Error>]()
	private var storedBytes = 0
	private let lifetime: TimeInterval = 15 * 60
	private let maximumEntryCount = 128
	private let maximumStoredBytes = 8 * 1_024 * 1_024

	func data(for url: URL, loader: @escaping @Sendable () async throws -> Data) async throws -> Data {
		let now = Date()
		if var entry = entries[url], entry.expiresAt > now {
			entry.lastAccessedAt = now
			entries[url] = entry
			return entry.data
		}
		if let entry = entries.removeValue(forKey: url) {
			storedBytes -= entry.data.count
		}
		if let task = inFlightTasks[url] {
			return try await task.value
		}

		let task = Task { try await loader() }
		inFlightTasks[url] = task
		defer { inFlightTasks[url] = nil }
		let data = try await task.value
		entries[url] = Entry(data: data, expiresAt: now.addingTimeInterval(lifetime), lastAccessedAt: now)
		storedBytes += data.count
		evictIfNeeded()
		return data
	}

	private func evictIfNeeded() {
		while entries.count > maximumEntryCount || storedBytes > maximumStoredBytes {
			guard let oldest = entries.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt }) else {
				return
			}
			storedBytes -= oldest.value.data.count
			entries[oldest.key] = nil
		}
	}
}

actor ReleaseNotesHTMLCache {

	private struct Entry {
		let value: Value
		let expiresAt: Date
		var lastAccessedAt: Date
		let cost: Int
	}

	private enum Value {
		case success(String)
		case failure(FetchHTMLError)

		func get() throws -> String {
			switch self {
			case .success(let html):
				return html
			case .failure(let error):
				throw error
			}
		}

		var cost: Int {
			switch self {
			case .success(let html):
				return html.utf8.count
			case .failure:
				return 0
			}
		}
	}

	private var entries = [URL: Entry]()
	private var inFlightTasks = [URL: Task<String, Error>]()
	private var storedHTMLBytes = 0
	private let successfulResponseLifetime: TimeInterval = 30 * 60
	private let failedResponseLifetime: TimeInterval = 5 * 60
	private let maximumEntryCount = 128
	private let maximumStoredHTMLBytes = 8 * 1_024 * 1_024

	func html(for url: URL, loader: @escaping @Sendable () async throws -> String) async throws -> String {
		let now = Date()
		pruneExpiredEntries(at: now)
		if var entry = entries[url] {
			entry.lastAccessedAt = now
			entries[url] = entry
			return try entry.value.get()
		}

		if let task = inFlightTasks[url] {
			return try await task.value
		}

		let task = Task {
			try await loader()
		}
		inFlightTasks[url] = task

		do {
			let html = try await task.value
			store(.success(html), for: url, lifetime: successfulResponseLifetime)
			inFlightTasks[url] = nil
			return html
		} catch FetchHTMLError.unusableText {
			store(.failure(.unusableText), for: url, lifetime: failedResponseLifetime)
			inFlightTasks[url] = nil
			throw FetchHTMLError.unusableText
		} catch {
			store(.failure(.fetchFailed), for: url, lifetime: failedResponseLifetime)
			inFlightTasks[url] = nil
			throw error
		}
	}

	private func store(_ value: Value, for url: URL, lifetime: TimeInterval) {
		let now = Date()
		pruneExpiredEntries(at: now)
		removeEntry(for: url)

		let cost = value.cost
		guard cost <= maximumStoredHTMLBytes else { return }
		entries[url] = Entry(
			value: value,
			expiresAt: now.addingTimeInterval(lifetime),
			lastAccessedAt: now,
			cost: cost
		)
		storedHTMLBytes += cost
		trimToLimits()
	}

	private func pruneExpiredEntries(at date: Date) {
		let expiredURLs = entries.compactMap { url, entry in
			entry.expiresAt <= date ? url : nil
		}
		for url in expiredURLs {
			removeEntry(for: url)
		}
	}

	private func trimToLimits() {
		while entries.count > maximumEntryCount || storedHTMLBytes > maximumStoredHTMLBytes {
			guard let leastRecentlyUsedURL = entries.min(by: {
				$0.value.lastAccessedAt < $1.value.lastAccessedAt
			})?.key else { return }
			removeEntry(for: leastRecentlyUsedURL)
		}
	}

	private func removeEntry(for url: URL) {
		guard let entry = entries.removeValue(forKey: url) else { return }
		storedHTMLBytes -= entry.cost
	}

}
