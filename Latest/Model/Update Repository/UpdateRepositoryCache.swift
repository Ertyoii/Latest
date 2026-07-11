//
//  UpdateRepositoryCache.swift
//  Latest
//
//  Created by Max Langer on 10.12.23.
//  Copyright © 2023 Max Langer. All rights reserved.
//

import CryptoKit
import Foundation

final class UpdateRepositoryCache: @unchecked Sendable {
	
	/// Duration after which the cache will be invalidated. (1 hour in seconds)
	private static let cacheInvalidationDuration: Double = 1 * 60 * 60

	init(cacheURL: URL?, userDefaultsKey: String, fileManager: FileManager = .default, userDefaults: UserDefaults = .standard) {
		self.cacheURL = cacheURL
		self.userDefaultsKey = userDefaultsKey
		self.fileManager = fileManager
		self.userDefaults = userDefaults
	}

	private let cacheURL: URL?
	private let userDefaultsKey: String
	private let fileManager: FileManager
	private let userDefaults: UserDefaults

	func cachedData() -> Data? {
		guard isCacheValid, let cacheURL else {
			return nil
		}

		return try? Data(contentsOf: cacheURL)
	}

	func store(_ data: Data) {
		guard let cacheURL else { return }

		do {
			try fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			try data.write(to: cacheURL, options: .atomic)
			userDefaults.setValue(Date.timeIntervalSinceReferenceDate, forKey: userDefaultsKey)
		} catch {
			try? fileManager.removeItem(at: cacheURL)
		}
	}

	private var isCacheValid: Bool {
		let timeInterval = userDefaults.double(forKey: userDefaultsKey) as TimeInterval
		return timeInterval > 0 && timeInterval.distance(to: Date.timeIntervalSinceReferenceDate) < Self.cacheInvalidationDuration
	}

}

struct UpdateRepositoryCompactIndex: Codable, Sendable {
	static let currentSchemaVersion = 2

	let schemaVersion: Int
	let sourceFingerprint: Data
	let sourceByteCount: Int
	let sourceEntryCount: Int
	let records: [UpdateRepository.Entry.CompactRecord]

	init(sourceData: Data, sourceEntryCount: Int, entries: [UpdateRepository.Entry]) {
		self.schemaVersion = Self.currentSchemaVersion
		self.sourceFingerprint = Self.fingerprint(sourceData)
		self.sourceByteCount = sourceData.count
		self.sourceEntryCount = sourceEntryCount
		self.records = entries.map(\.compactRecord)
	}

	func matches(_ sourceData: Data) -> Bool {
		schemaVersion == Self.currentSchemaVersion &&
			sourceByteCount == sourceData.count &&
			sourceFingerprint == Self.fingerprint(sourceData)
	}

	var entries: [UpdateRepository.Entry] {
		records.map(UpdateRepository.Entry.init(compactRecord:))
	}

	private static func fingerprint(_ data: Data) -> Data {
		Data(SHA256.hash(data: data))
	}
}

final class UpdateRepositoryCompactIndexCache: @unchecked Sendable {
	private let cacheURL: URL?
	private let fileManager: FileManager

	init(cacheURL: URL?, fileManager: FileManager = .default) {
		self.cacheURL = cacheURL
		self.fileManager = fileManager
	}

	func load(matching sourceData: Data) -> UpdateRepositoryCompactIndex? {
		guard let cacheURL,
		      let data = try? Data(contentsOf: cacheURL),
		      let index = try? PropertyListDecoder().decode(UpdateRepositoryCompactIndex.self, from: data),
		      index.matches(sourceData) else {
			return nil
		}
		return index
	}

	func store(_ index: UpdateRepositoryCompactIndex) {
		guard let cacheURL else { return }
		do {
			let encoder = PropertyListEncoder()
			encoder.outputFormat = .binary
			let data = try encoder.encode(index)
			try fileManager.createDirectory(
				at: cacheURL.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try data.write(to: cacheURL, options: .atomic)
		} catch {
			try? fileManager.removeItem(at: cacheURL)
		}
	}
}
