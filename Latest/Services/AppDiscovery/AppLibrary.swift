//
//  AppLibrary.swift
//  Latest
//
//  Created by Max Langer on 08.01.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import Foundation
import OSLog

private let appLibraryLogger = Logger(
  subsystem: Foundation.Bundle.main.bundleIdentifier ?? "com.max-langer.Latest",
  category: "AppDiscovery"
)

/// Observes the local collection of apps and notifies its owner of changes.
class AppLibrary: @unchecked Sendable {

  /// The handler to be called when apps change locally.
  typealias UpdateHandler = @Sendable ([App.Bundle]) -> Void
  let updateHandler: UpdateHandler

  /// The handler to be called when a full reload completed.
  typealias ReloadHandler = @Sendable ([App.Bundle]) -> Void

  /// A list of all application bundles that are available locally.
  var bundles: [App.Bundle] {
    stateQueue.sync {
      let inventory = currentInventory()
      return Self.uniqueBundles(directoryURLs.compactMap { inventory[$0] })
    }
  }

  private var directoryURLs = [URL]()
  private var directories = [URL: AppDirectory]()
  private var pendingDirectories = [URL: UUID]()
  private var reloadHandler: ReloadHandler?
  private var hasPublishedInventory = false
  private var cachedDirectories = [URL: [App.Bundle]]()
  private var didReadCache = false
  private struct Replacement {
    let token: UUID
    let bundleIdentifier: String
    var bundle: App.Bundle?
    let otherCopies: [App.Bundle]
  }
  private var replacements = [URL: Replacement]()
  private let cache: AppInventoryCache?
  private let previewHandler: UpdateHandler
  private let bundleCollector: @Sendable (URL) -> [App.Bundle]

  /// Initializes the library with the given handler for updates.
  typealias DirectoryStoreFactory =
    @Sendable (@escaping AppDirectoryUpdateHandler) -> any AppDirectoryStoring
  private let directoryStoreFactory: DirectoryStoreFactory

  init(
    directoryStoreFactory: @escaping DirectoryStoreFactory = {
      AppDirectoryStore(updateHandler: $0)
    },
    cache: AppInventoryCache? = nil,
    bundleCollector: @escaping @Sendable (URL) -> [App.Bundle] = BundleCollector.collectBundles,
    previewHandler: @escaping UpdateHandler = { _ in },
    handler: @escaping UpdateHandler
  ) {
    self.cache = cache
    self.previewHandler = previewHandler
    self.bundleCollector = bundleCollector
    self.directoryStoreFactory = directoryStoreFactory
    self.updateHandler = handler
  }

  private let stateQueue = DispatchQueue(label: "AppLibraryStateQueue")

  private var scheduledUpdateWorkItem: DispatchWorkItem?

  private static let updateCoalescingInterval: TimeInterval = 0.5

  // MARK: - Actions

  /// Starts the update checking process
  func startQuery() {
    stateQueue.async { [weak self] in
      guard let self else { return }
      self.setupDirectoryObservers()
    }
  }

  /// Forces all observed directories to be read from disk again.
  func reload(handler: @escaping ReloadHandler) {
    stateQueue.async { [weak self] in
      guard let self else { return }
      self.reloadHandler = handler
      self.setupDirectoryObservers(refreshExisting: true)
    }
  }

  /// Directory events can see the new package before its App Store receipt is written.
  func beginReplacing(_ bundle: App.Bundle) {
    stateQueue.sync {
      let copies = Self.uniqueBundles(Array(currentInventory().values)).filter {
        $0.identifier != bundle.identifier && $0.bundleIdentifier == bundle.bundleIdentifier
      }
      replacements[bundle.identifier] = Replacement(
        token: UUID(), bundleIdentifier: bundle.bundleIdentifier, bundle: bundle,
        otherCopies: copies)
    }
  }

  func finishReplacing(
    at url: URL, with installed: App.Bundle?, registeredURL: URL? = nil,
    reconcile: @Sendable (App.Bundle) -> Void
  ) {
    stateQueue.sync {
      guard var replacement = replacements[url] else { return }
      replacement.bundle = installed
      replacements[url] = replacement
      // A coalesced watcher event may still contain the pre-receipt inventory.
      // Retire the override only after all owning directories have read again.
      let refreshed = DispatchGroup()
      let path = url.standardizedFileURL.path
      let paths =
        (replacement.otherCopies.map(\.fileURL) + [url] + [registeredURL].compactMap { $0 })
        .map { $0.standardizedFileURL.path }
      let owners = directories.filter {
        let prefix = Self.descendantPrefix(for: $0.key)
        return paths.contains { $0.hasPrefix(prefix) }
      }
      guard !owners.isEmpty else {
        replacements[url] = nil
        return
      }
      if let installed,
        owners.keys.contains(where: { path.hasPrefix(Self.descendantPrefix(for: $0)) })
      {
        reconcile(installed)
      }
      for (directory, observer) in owners {
        BundleCollector.invalidateCollection(at: directory)
        refreshed.enter()
        observer.refresh { refreshed.leave() }
      }
      let token = replacement.token
      refreshed.notify(queue: stateQueue) {
        guard self.replacements[url]?.token == token else { return }
        self.replacements[url] = nil
        self.performUpdate()
      }
    }
  }

  private func setupDirectoryObservers(refreshExisting: Bool = false) {
    let urls = directoryStore.URLs
    let previousURLs = Set(directoryURLs)
    directoryURLs = urls
    if !didReadCache {
      didReadCache = true
      cachedDirectories = cache?.load(for: urls) ?? [:]
      let preview = Self.uniqueBundles(urls.compactMap { cachedDirectories[$0] })
      if !preview.isEmpty { previewHandler(preview) }
    }

    let configuredURLs = Set(urls)
    let removedURLs = previousURLs.subtracting(configuredURLs)
    for url in removedURLs {
      directories[url] = nil
      pendingDirectories[url] = nil
      cachedDirectories[url] = nil
    }
    for url in urls {
      let existing = directories[url]
      guard existing == nil || refreshExisting else { continue }
      let token = UUID()
      pendingDirectories[url] = token
      let completion: AppDirectory.RefreshCompletion = { [weak self] in
        self?.directoryReady(url, token: token)
      }
      if let existing {
        existing.refresh(completion: completion)
      } else {
        directories[url] = AppDirectory(
          url: url, notifyOnInitialCollection: false,
          initialCollectionCompletion: completion, bundleCollector: bundleCollector,
          updateHandler: { [weak self] in self?.scheduleUpdate() })
      }
    }
    if !hasPublishedInventory || previousURLs != configuredURLs || refreshExisting {
      scheduledUpdateWorkItem?.cancel()
      if pendingDirectories.isEmpty {
        performUpdate()
      } else if !hasPublishedInventory, !removedURLs.isEmpty {
        publishPreview()
      }
    }
  }

  private func directoryReady(_ url: URL, token: UUID) {
    stateQueue.async { [weak self] in
      guard let self, self.pendingDirectories[url] == token else { return }
      self.pendingDirectories[url] = nil
      if self.pendingDirectories.isEmpty {
        self.performUpdate()
      } else if !self.hasPublishedInventory {
        self.publishPreview()
      }
    }
  }

  private func publishPreview() {
    // A slow location can keep its cached rows while faster ones report live metadata.
    var live = [[App.Bundle]]()
    var completedPrefixes = [String]()
    for url in directoryURLs {
      if pendingDirectories[url] == nil, let bundles = directories[url]?.bundles {
        live.append(bundles)
        completedPrefixes.append(Self.descendantPrefix(for: url))
      }
    }
    let cached = directoryURLs.compactMap { url -> [App.Bundle]? in
      guard pendingDirectories[url] != nil, let bundles = cachedDirectories[url] else { return nil }
      let prefix = Self.descendantPrefix(for: url)
      let scannedChildren = completedPrefixes.filter { $0.hasPrefix(prefix) }
      guard !scannedChildren.isEmpty else { return bundles }
      // A pending ancestor's old inventory cannot restore a deleted app in a scanned child.
      return bundles.filter { bundle in
        let path = bundle.fileURL.standardizedFileURL.path
        return !scannedChildren.contains { path.hasPrefix($0) }
      }
    }
    previewHandler(Self.uniqueBundles(live + cached))
  }

  private func currentInventory() -> [URL: [App.Bundle]] {
    var inventory = directories.mapValues(\.bundles)
    guard !replacements.isEmpty else { return inventory }
    // PackageKit can replace a sibling copy or create one at its registered path.
    // Only publish a new Store copy once its receipt identifies the source.
    for replacement in replacements.values {
      let oldCopies = replacement.otherCopies
      for directory in directoryURLs {
        let prefix = Self.descendantPrefix(for: directory)
        inventory[directory]?.removeAll { app in
          app.bundleIdentifier == replacement.bundleIdentifier && app.source != .appStore
            && !oldCopies.contains { $0.identifier == app.identifier && $0.source != .appStore }
        }
        for copy in oldCopies
        where copy.source == .appStore && replacements[copy.identifier] == nil
          && copy.fileURL.standardizedFileURL.path.hasPrefix(prefix)
        {
          if inventory[directory]?.contains(where: { $0.identifier == copy.identifier }) == false {
            inventory[directory]?.append(copy)
          }
        }
      }
    }
    for (url, replacement) in replacements {
      let path = url.standardizedFileURL.path
      for directory in directoryURLs where path.hasPrefix(Self.descendantPrefix(for: directory)) {
        inventory[directory]?.removeAll { $0.fileURL.standardizedFileURL.path == path }
        if let bundle = replacement.bundle { inventory[directory]?.append(bundle) }
      }
    }
    return inventory
  }

  private func performUpdate() {
    guard pendingDirectories.isEmpty else { return }
    hasPublishedInventory = true
    cachedDirectories.removeAll()
    let inventory = currentInventory()
    let bundles = Self.uniqueBundles(directoryURLs.compactMap { inventory[$0] })
    appLibraryLogger.info("Publishing \(bundles.count, privacy: .public) discovered apps")
    let handler = reloadHandler ?? updateHandler
    reloadHandler = nil
    handler(bundles)
    cache?.store(inventory)
  }

  private func scheduleUpdate() {
    stateQueue.async { [weak self] in
      guard let self else { return }
      self.scheduleUpdateOnStateQueue()
    }
  }

  private func scheduleUpdateOnStateQueue() {
    self.scheduledUpdateWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      self?.performUpdate()
    }
    self.scheduledUpdateWorkItem = workItem

    self.stateQueue.asyncAfter(deadline: .now() + Self.updateCoalescingInterval, execute: workItem)
  }

  private static func uniqueBundles(_ inventories: [[App.Bundle]]) -> [App.Bundle] {
    var paths = Set<App.Bundle.Identifier>()
    return inventories.flatMap { $0.filter { paths.insert($0.identifier).inserted } }
  }

  private static func descendantPrefix(for url: URL) -> String {
    let path = url.standardizedFileURL.path
    return path.hasSuffix("/") ? path : path + "/"
  }

  // MARK: - Directory Handling

  /// The store handling application directories.
  private lazy var directoryStore = {
    directoryStoreFactory { [weak self] in self?.startQuery() }
  }()

}
