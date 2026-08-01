//
//  IconCache.swift
//  Latest
//
//  Created by Max Langer on 12.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import AppKit

/// A cache for app icons.
@MainActor
class IconCache {

	/// The shared cache object.
	static let shared = IconCache()

	/// Initializes the cache.
	private init() {
		self.cache = NSCache()
		self.cache.countLimit = 256
		self.cache.totalCostLimit = 64 * 1_024 * 1_024
	}

	/// The object storing app images.
	private var cache: NSCache<NSString, NSImage>

	/// Returns a previously decoded icon without scheduling work. Native rows use
	/// this to avoid spawning a task for every cache hit while they are recycled.
	func cachedIcon(for app: App) -> NSImage? {
		cache.object(forKey: cacheKey(for: app))
	}

	/// Returns an icon after an asynchronous scheduling boundary. SwiftUI tasks
	/// use this form so a cache hit cannot mutate view state during rendering.
	func icon(for app: App) async -> NSImage {
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			DispatchQueue.main.async {
				continuation.resume()
			}
		}
		return loadIcon(for: app)
	}

	/// Provides the icon for the given app through the given completion handler.
	func icon(for app: App, with completion: @escaping (NSImage) -> Void) {
		completion(loadIcon(for: app))
	}

	private func loadIcon(for app: App) -> NSImage {
		let cacheKey = cacheKey(for: app)

		if let icon = self.cache.object(forKey: cacheKey) {
			return icon
		}

		let icon = NSWorkspace.shared.icon(forFile: app.fileURL.path)
		let pixelCount = max(Int(icon.size.width * icon.size.height), 1)
		self.cache.setObject(icon, forKey: cacheKey, cost: pixelCount * 4)
		return icon
	}

	private func cacheKey(for app: App) -> NSString {
		"\(app.fileURL.standardizedFileURL.path)\u{0}\(app.bundle.modificationDate.timeIntervalSinceReferenceDate)" as NSString
	}

}
