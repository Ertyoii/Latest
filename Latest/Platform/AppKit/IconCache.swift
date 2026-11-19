//
//  IconCache.swift
//  Latest
//
//  Created by Max Langer on 12.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import AppKit
import UniformTypeIdentifiers

@MainActor
final class IconCache {
  static let shared = IconCache()

  private let cache = NSCache<NSString, NSImage>()
  private let reader = IconReader()
  private lazy var placeholder = NSWorkspace.shared.icon(for: .applicationBundle)

  private init() {
    cache.countLimit = 256
    cache.totalCostLimit = 64 * 1_024 * 1_024
  }

  func cachedIconOrPlaceholder(for app: App) -> NSImage {
    cache.object(forKey: key(for: app)) ?? placeholder
  }

  func icon(for app: App) async -> NSImage {
    let key = key(for: app)
    if let cached = cache.object(forKey: key) {
      // SwiftUI can start a view task during rendering. Defer cached results as well.
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async { continuation.resume() }
      }
      return cached
    }
    guard let icon = await reader.read(at: app.fileURL) else { return placeholder }
    let pixels = max(Int(icon.size.width * icon.size.height), 1)
    cache.setObject(icon, forKey: key, cost: pixels * 4)
    return icon
  }

  private func key(for app: App) -> NSString {
    "\(app.fileURL.path)\u{0}\(app.bundle.modificationDate.timeIntervalSinceReferenceDate)"
      as NSString
  }
}

/// Waiting for an icon on a slow volume must not hold up the first frame or input.
private actor IconReader {
  func read(at url: URL) -> sending NSImage? {
    guard !Task.isCancelled, FileManager.default.fileExists(atPath: url.path) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
  }
}
