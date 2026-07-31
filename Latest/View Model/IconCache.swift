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
	}

	/// The object storing app images.
	private var cache: NSCache<NSURL, NSImage>

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
		let cacheKey = app.identifier as NSURL

		if let icon = self.cache.object(forKey: cacheKey) {
			return icon
		}

		let icon = NSWorkspace.shared.icon(forFile: app.fileURL.path)
		self.cache.setObject(icon, forKey: cacheKey)
		return icon
	}

}
