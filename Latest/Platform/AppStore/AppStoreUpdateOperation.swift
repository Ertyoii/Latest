//
//  AppStoreUpdateOperation.swift
//  Latest
//
//  Created by Max Langer on 01.07.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import CommerceKit
import StoreFoundation
import Synchronization
import os

private let appStoreUpdateLogger = Logger(
  subsystem: "com.max-langer.Latest.dev", category: "AppStoreUpdates")

/// Public boundary for App Store updates backed by private Apple frameworks.
enum AppStoreUpdater {

  /// Verifies whether the app can prepare App Store updates.
  static func prepareForUpdates() async throws {
    if AppStoreUpdateOperation.requiresManualInstallation {
      try await InstallHelper.prepareForUpdates()
    }
  }

  /// Enqueues an App Store update operation.
  static func enqueueUpdate(for app: App.Bundle, appStoreIdentifier: UInt64, pageURL: URL) {
    let operation = AppStoreUpdateOperation(
      app: app, itemIdentifier: appStoreIdentifier, pageURL: pageURL
    )
    UpdateQueue.shared.addOperation(operation)
  }

}

/// Owns App Store downloads while Latest displays progress. Apple downloads the
/// purchased update; the signed helper handles PackageKit's entitlement failure.
final class AppStoreUpdateOperation: UpdateOperation, @unchecked Sendable {
  private let itemIdentifier: UInt64
  private let app: App.Bundle
  private let pageURL: URL
  private let downloadFolder: URL
  private let install: @Sendable (FileHandle, URL, Data) async throws -> Void
  @MainActor private var observerIdentifier: String?
  private let artifacts = AppStoreDownloadArtifacts()
  @MainActor private var isInstalling = false
  @MainActor private var purchaseStarted = false

  init(
    app: App.Bundle, itemIdentifier: UInt64, pageURL: URL,
    downloadDirectory: URL = URL(fileURLWithPath: CKDownloadDirectory(nil), isDirectory: true),
    install: (@Sendable (FileHandle, URL, Data) async throws -> Void)? = nil
  ) {
    self.downloadFolder = downloadDirectory.appendingPathComponent(
      String(itemIdentifier), isDirectory: true)
    self.install =
      install ?? { package, url, receipt in
        try await UpdateCheckCoordinator.shared.whileReplacingStoreApp(app) {
          try await InstallHelper.installPackage(package, appURL: url, receiptData: receipt)
        }
      }
    self.app = app
    self.itemIdentifier = itemIdentifier
    self.pageURL = pageURL
    super.init(appIdentifier: app.identifier)
  }

  static let requiresManualInstallation = ProcessInfo.processInfo.isOperatingSystemAtLeast(
    .init(majorVersion: 26, minorVersion: 1, patchVersion: 0))

  override func execute() {
    super.execute()
    Task { @MainActor in
      guard !self.isCancelled else {
        self.finish()
        return
      }
      // Approval may have changed while the operation waited in the queue.
      do { try await AppStoreUpdater.prepareForUpdates() } catch {
        guard !self.isCancelled, !self.isFinished else { return }
        self.preparationFailed(error)
        return
      }
      guard !self.isCancelled, !self.isFinished else { return }
      // Register before starting the purchase: small downloads can finish before
      // its completion callback, and their package/receipt must be preserved.
      self.observerIdentifier = CKDownloadQueue.shared().add(self)
      let purchase = SSPurchase(itemIdentifier: self.itemIdentifier)
      self.purchaseStarted = true
      do {
        let (_, completed, response) = try await CKPurchaseController.shared().perform(
          purchase, withOptions: 0)
        let downloads = response?.downloads ?? []
        // Cancellation can finish the operation before Apple creates its download.
        guard !self.isCancelled else {
          for download in downloads {
            CKDownloadQueue.shared().cancelDownload(
              download, promptToConfirm: false, askToDelete: false)
          }
          self.finishOnMain()
          return
        }
        appStoreUpdateLogger.notice(
          "Purchase completed=\(completed), downloads=\(downloads.count)"
        )
        if downloads.isEmpty, !self.isFinished, !self.isInstalling {
          self.finish(with: LatestError.updateInfoUnavailable)
        }
      } catch {
        guard !self.isFinished, !self.isInstalling else { return }
        self.finish(with: error)
      }
    }
  }

  @MainActor private func preparationFailed(_ error: Error) {
    // No purchase has started. Remove the waiting operation without publishing
    // an update failure or a successful-install notification, then offer recovery.
    super.cancel()
    finishOnMain()
    UpdateInstallHelperAlert.shared.prepare(
      fallbackURL: pageURL,
      error: error as? InstallHelperError ?? .unavailable(error.localizedDescription)
    ) { [app, itemIdentifier, pageURL] in
      AppStoreUpdater.enqueueUpdate(for: app, appStoreIdentifier: itemIdentifier, pageURL: pageURL)
    }
  }

  override func cancel() {
    super.cancel()
    guard isCancelled else { return }
    Task { @MainActor in
      if self.purchaseStarted, !self.isFinished {
        CKPurchaseController.shared().cancelPurchase(
          withProductID: NSNumber(value: self.itemIdentifier))
        self.cancelPendingDownload()
      }
      // installer cannot safely be interrupted halfway through replacing an app.
      if !self.isInstalling { self.finish() }
    }
  }

  @MainActor private func cancelPendingDownload() {
    let queue = CKDownloadQueue.shared()
    if let download = queue.download(forItemIdentifier: itemIdentifier) {
      queue.cancelDownload(download, promptToConfirm: false, askToDelete: false)
    }
  }

  override func finish(with error: Error) {
    guard !isCancelled else {
      finish()
      return
    }
    let cause = error as NSError
    appStoreUpdateLogger.error(
      "Update failed for item \(self.itemIdentifier): \(cause.domain, privacy: .public) \(cause.code)"
    )
    super.finish(
      with: AppStoreUpdateFailure(
        pageURL: pageURL, installedVersion: app.version,
        cause: error is CancellationError
          ? LatestError.custom(title: "The App Store cancelled the download.", description: nil)
          : error))
  }

  override func finish() {
    Task { @MainActor in self.finishOnMain() }
  }

  @MainActor private func finishOnMain() {
    guard !isFinished else { return }
    if let observerIdentifier {
      CKDownloadQueue.shared().removeObserver(observerIdentifier)
      self.observerIdentifier = nil
    }
    _ = artifacts.take()
    super.finish()
  }

  private func preserveArtifacts(for download: SSDownload, snapshot: AppStoreDownloadSnapshot) {
    guard Self.requiresManualInstallation else { return }
    // CommerceKit may supply an opaque per-download folder. Use the matching
    // asset's exact package when present, otherwise use its item-ID folder.
    let asset = download.primaryAsset
    let paths = [
      asset?.responds(to: #selector(getter: SSDownloadAsset.processedPath)) == true
        ? asset?.processedPath : nil,
      asset?.responds(to: #selector(getter: SSDownloadAsset.downloadPath)) == true
        ? asset?.downloadPath : nil,
    ].compactMap { $0 }
    artifacts.capture(in: downloadFolder, assetPaths: paths, receiptData: snapshot.receiptData)
  }

  @MainActor private func removed(_ snapshot: AppStoreDownloadSnapshot) async {
    guard !isFinished, !isInstalling else { return }
    appStoreUpdateLogger.notice(
      "Download removed: failed=\(snapshot.failed), cancelled=\(snapshot.cancelled), error=\((snapshot.error as NSError?)?.domain ?? "none", privacy: .public):\((snapshot.error as NSError?)?.code ?? 0)"
    )
    switch AppStoreDownloadResult(
      failed: snapshot.failed, cancelled: snapshot.cancelled, error: snapshot.error,
      wasCancelled: isCancelled)
    {
    case .completed:
      finish()
      return
    case .failed(let error):
      finish(with: error)
      return
    case .installPackage:
      break
    }
    let files = artifacts.take()
    guard let package = files?.package,
      let receipt = files?.receiptData
    else {
      finish(
        with: LatestError.custom(
          title: "The App Store download was incomplete.",
          description: "The installer or its receipt was missing."))
      return
    }
    do {
      try beginCommit()
      isInstalling = true
      progressState = .installing
      try await install(package, app.fileURL, receipt)
      finish()
    } catch {
      finish(with: error)
    }
  }
}

/// PackageKit reports its entitlement restriction as both failed and cancelled.
/// Only cancellation requested in Latest must prevent the installer workaround.
enum AppStoreDownloadResult {
  case completed
  case installPackage
  case failed(Error)

  init(failed: Bool, cancelled: Bool, error: Error?, wasCancelled: Bool) {
    if wasCancelled {
      self = .failed(CancellationError())
    } else if let error {
      self =
        AppStoreDownloadArtifacts.requiresPackageInstallation(error)
        ? .installPackage : .failed(error)
    } else if cancelled {
      self = .failed(CancellationError())
    } else if failed {
      self = .failed(LatestError.updateInfoUnavailable)
    } else {
      self = .completed
    }
  }
}

private struct AppStoreDownloadSnapshot: Sendable {
  let failed: Bool
  let cancelled: Bool
  let error: Error?
  let receiptData: Data?
  let phase: Int64?
  let loaded: Int64
  let total: Int64

  init?(_ download: SSDownload, itemIdentifier: UInt64) {
    guard let metadata = download.metadata, metadata.itemIdentifier == itemIdentifier else {
      return nil
    }
    let status = download.status
    failed = status?.isFailed ?? true
    cancelled = status?.isCancelled ?? false
    error = status?.error
    receiptData = metadata.receiptData
    let activePhase = status?.activePhase
    phase = activePhase?.phaseType
    loaded = activePhase?.progressValue ?? 0
    total = activePhase?.totalProgressValue ?? 0
  }
}

extension AppStoreUpdateOperation {
  @MainActor func receiveProgress(phase: Int64?, loaded: Int64, total: Int64) {
    switch phase {
    case 0:
      if case .extracting = progressState { return }
      if case .downloading(let previous, let knownTotal, _) = progressState {
        guard loaded >= previous else { return }
        progressState = .downloading(loadedSize: loaded, totalSize: total > 0 ? total : knownTotal)
      } else {
        progressState = .downloading(loadedSize: max(0, loaded), totalSize: total)
      }
    case 1:
      let fraction = total > 0 ? min(max(Double(loaded) / Double(total), 0), 1) : nil
      if case .extracting(let previous?, _) = progressState {
        guard let fraction, fraction >= previous else { return }
      }
      progressState = .extracting(progress: fraction)
    default:
      // A status without an active phase supplies no new progress information.
      break
    }
  }
}

extension AppStoreUpdateOperation: CKDownloadQueueObserver {
  func downloadQueue(_ queue: CKDownloadQueue, statusChangedFor download: SSDownload) {
    guard let snapshot = AppStoreDownloadSnapshot(download, itemIdentifier: itemIdentifier)
    else { return }
    preserveArtifacts(for: download, snapshot: snapshot)
    Task { @MainActor in
      guard !self.isFinished, !self.isInstalling, !self.isCancelled else { return }
      self.receiveProgress(phase: snapshot.phase, loaded: snapshot.loaded, total: snapshot.total)
    }
  }

  func downloadQueue(_ queue: CKDownloadQueue, changedWithRemoval download: SSDownload) {
    guard let snapshot = AppStoreDownloadSnapshot(download, itemIdentifier: itemIdentifier)
    else { return }
    preserveArtifacts(for: download, snapshot: snapshot)
    Task { @MainActor in await self.removed(snapshot) }
  }
  func downloadQueue(_ queue: CKDownloadQueue, changedWithAddition download: SSDownload) {
    downloadQueue(queue, statusChangedFor: download)
  }
}

/// The Store can unlink its download as soon as the observer callback returns.
final class AppStoreDownloadArtifacts: Sendable {
  struct Files {
    var package: FileHandle?
    var receipt: FileHandle?
    var metadataReceipt: Data?

    var receiptData: Data? {
      guard let data = try? receipt?.readToEnd(), !data.isEmpty else { return metadataReceipt }
      return data
    }
  }

  private let files = Mutex<Files?>(Files())

  func capture(in folder: URL, assetPaths: [String] = [], receiptData: Data? = nil) {
    files.withLock { files in
      guard files != nil else { return }
      if let receiptData, !receiptData.isEmpty { files?.metadataReceipt = receiptData }
      for path in assetPaths where path.hasPrefix("/") && path.hasSuffix(".pkg") {
        let asset = URL(fileURLWithPath: path)
        let directory = asset.deletingLastPathComponent().resolvingSymlinksInPath()
        let root = directory.deletingLastPathComponent()
        let cache = folder.deletingLastPathComponent().resolvingSymlinksInPath()
        let agentCache = cache.deletingLastPathComponent().appendingPathComponent(
          "com.apple.appstoreagent/com.apple.appstore", isDirectory: true)
        guard
          directory.lastPathComponent == folder.lastPathComponent
            || UUID(uuidString: directory.lastPathComponent) != nil,
          root.path == cache.path || root.path == agentCache.path,
          let package = Self.openFile(directory.appendingPathComponent(asset.lastPathComponent))
        else { continue }
        files?.package = package
        if let receipt = Self.openFile(directory.appendingPathComponent("receipt")) {
          files?.receipt = receipt
        }
        return
      }
      let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey,
      ]
      guard
        let entries = try? FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: Array(keys))
      else { return }
      var package: (url: URL, date: Date)?
      for entry in entries {
        guard entry.pathExtension == "pkg" || entry.lastPathComponent == "receipt",
          let info = try? entry.resourceValues(forKeys: keys),
          info.isRegularFile == true, info.isSymbolicLink != true
        else { continue }
        if entry.lastPathComponent == "receipt" {
          files?.receipt = Self.openFile(entry)
        } else {
          let date = info.contentModificationDate ?? .distantPast
          if let package, package.date >= date { continue }
          package = (entry, date)
        }
      }
      if let package { files?.package = Self.openFile(package.url) }
    }
  }

  private static func openFile(_ url: URL) -> FileHandle? {
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else { return nil }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
    return handle
  }

  /// Taking ownership also closes capture to callbacks already in flight.
  func take() -> Files? {
    files.withLock { files in
      defer { files = nil }
      return files
    }
  }

  static func requiresPackageInstallation(_ error: Error) -> Bool {
    var cause = error as NSError
    for _ in 0..<8 {
      if cause.domain == "PKInstallErrorDomain", cause.code == 201 { return true }
      guard let underlying = cause.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
      cause = underlying
    }
    return false
  }

}

extension SSPurchase {
  fileprivate convenience init(itemIdentifier: UInt64) {
    self.init(
      buyParameters:
        "productType=C&price=0&salableAdamId=\(itemIdentifier)&pg=default&appExtVrsId=0&pricingParameters=STDRDL"
    )

    let downloadMetadata = SSDownloadMetadata(kind: "software")
    downloadMetadata.itemIdentifier = itemIdentifier

    self.downloadMetadata = downloadMetadata
    self.itemIdentifier = itemIdentifier
    self.isUpdate = true
    self.isRedownload = true
  }
}

extension SSDownloadMetadata {
  /// Returns the app store receipt from the metadata.
  var receiptData: Data? {
    dictionary?["app-receipt"] as? Data
  }
}
