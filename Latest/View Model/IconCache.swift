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
final class IconCache {
    
	/// The shared cache object.
	static let shared = IconCache()
    
	/// Initializes the cache.
    private init() {
        self.cache = NSCache()
    }

	/// The object storing app images.
	private var cache: NSCache<App, NSImage>
	
	/// Provides the icon for the given app through the given completion handler.
    func icon(for app: App, with completion: @escaping (NSImage) -> Void) {
        if let icon = self.cache.object(forKey: app) {
            completion(icon)
			return
        }
        
		Task {
			let icon = await Task.detached(priority: .userInitiated) {
				return NSWorkspace.shared.icon(forFile: app.fileURL.path)
			}.value
			
			self.cache.setObject(icon, forKey: app)
			completion(icon)
		}
    }
    
}
