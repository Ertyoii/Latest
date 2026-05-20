//
//  UpdateRepositoryCache.swift
//  Latest
//
//  Created by Max Langer on 10.12.23.
//  Copyright © 2023 Max Langer. All rights reserved.
//

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
			try data.write(to: cacheURL)
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
