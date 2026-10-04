import AppKit
import Foundation
import Synchronization

/// Shared download, cancellation and commit lifecycle for vendor installers.
class DownloadUpdateOperation: UpdateOperation, @unchecked Sendable {
  let app: App.Bundle
  private struct Work {
    var task: Task<Void, Never>?
  }
  private let work = Mutex(Work())

  init(app: App.Bundle) {
    self.app = app
    super.init(bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
  }

  final override func execute() {
    super.execute()
    work.withLock { work in
      work.task = Task.detached { [self] in
        do {
          try Task.checkCancellation()
          try await performUpdate()
          finish()
        } catch  where error is CancellationError || (error as? URLError)?.code == .cancelled {
          cancel()
          finish()
        } catch {
          // A late cancellation must never hide an installation or rollback failure.
          finish(with: error)
        }
      }
      if isCancelled { work.task?.cancel() }
    }
  }

  final override func cancel() {
    super.cancel()
    guard isCancelled else { return }
    work.withLock { work in
      work.task?.cancel()
    }
  }

  func performUpdate() async throws { fatalError("Subclasses must implement performUpdate") }

  func download(from url: URL, into directory: URL, maximumSize: Int = 8 * 1_024 * 1_024 * 1_024)
    async throws -> URL
  {
    guard url.scheme == "https" else { throw AppDownloadError.invalidMetadata }
    progressState = .downloading(loadedSize: 0, totalSize: 0)
    let delegate = BoundedDownloadDelegate(maximumSize: maximumSize) { [weak self] loaded, total in
      self?.progressState = .downloading(loadedSize: loaded, totalSize: total)
    }
    let temporary: URL
    let response: URLResponse
    do {
      (temporary, response) = try await URLSession.shared.download(from: url, delegate: delegate)
    } catch {
      if delegate.exceededLimit { throw AppDownloadError.invalidDownload }
      throw error
    }
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard !delegate.exceededLimit,
      (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https",
      (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= maximumSize
    else { throw AppDownloadError.invalidDownload }
    try Task.checkCancellation()
    let archive = directory.appendingPathComponent("download." + url.pathExtension.lowercased())
    try FileManager.default.moveItem(at: temporary, to: archive)
    return archive
  }

  /// Reopen the surviving app after success, rollback, or cancellation after quitting.
  @MainActor
  func withApplicationClosed(_ install: @Sendable () async throws -> Void) async throws {
    try Task.checkCancellation()
    let running = NSWorkspace.shared.runningApplications.filter {
      $0.bundleURL?.standardizedFileURL == app.fileURL.standardizedFileURL
    }
    if !running.isEmpty {
      let alert = NSAlert()
      alert.messageText = "Quit \(app.name) to install its update?"
      alert.informativeText = "Save your work first. The app will reopen after the update."
      alert.addButton(withTitle: "Quit and Update")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { throw CancellationError() }
    }
    try await ApplicationQuitLifecycle.run(
      terminate: { running.forEach { $0.terminate() } },
      isTerminated: { running.allSatisfy(\.isTerminated) },
      reopen: {
        guard !running.isEmpty,
          FileManager.default.fileExists(atPath: app.fileURL.path)
        else { return }
        MacApplicationWorkspace.shared.openApplication(at: app.fileURL)
      },
      install: install
    )
  }

  /// Same-volume renames with rollback. Keep the backup if recovery itself fails.
  static func replaceItem(at target: URL, with candidate: URL, backupDirectory: URL) throws {
    let manager = FileManager.default
    let backup = backupDirectory.appendingPathComponent("original")
    let hadOriginal = manager.fileExists(atPath: target.path)
    if hadOriginal { try manager.moveItem(at: target, to: backup) }
    do {
      try manager.moveItem(at: candidate, to: target)
    } catch {
      if hadOriginal {
        do { try manager.moveItem(at: backup, to: target) } catch {
          throw AppDownloadError.replacementFailed("The original was saved at \(backup.path).")
        }
      }
      throw error
    }
    if hadOriginal { try? manager.removeItem(at: backup) }
  }

  static func removeStageUnlessRecoveryIsNeeded(_ stage: URL) {
    if !FileManager.default.fileExists(atPath: stage.appendingPathComponent("original").path) {
      try? FileManager.default.removeItem(at: stage)
    }
  }
}

/// Quit cannot be recalled after sending terminate(). Wait for its outcome even
/// after cancellation, then reopen the surviving app without starting an install.
@MainActor
enum ApplicationQuitLifecycle {
  static func run(
    terminate: () -> Void,
    isTerminated: @escaping @MainActor @Sendable () -> Bool,
    reopen: () -> Void,
    install: @Sendable () async throws -> Void
  ) async throws {
    // Confirmation can run a nested event loop where cancellation is accepted.
    try Task.checkCancellation()
    defer { if isTerminated() { reopen() } }
    terminate()
    let terminated = await Task { @MainActor in
      for _ in 0..<100 {
        if isTerminated() { return true }
        try? await Task.sleep(for: .milliseconds(200))
      }
      return isTerminated()
    }.value
    guard terminated else { throw AppDownloadError.applicationStillRunning }
    try Task.checkCancellation()
    try await install()
  }
}

/// Enforce the limit while receiving bytes, including responses without a
/// Content-Length. The final file-size check also covers a last callback race.
final class BoundedDownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
  private let maximumSize: Int64
  private let progress: @Sendable (Int64, Int64) -> Void
  private let oversized = Mutex(false)
  var exceededLimit: Bool { oversized.withLock { $0 } }

  init(maximumSize: Int, progress: @escaping @Sendable (Int64, Int64) -> Void) {
    self.maximumSize = Int64(maximumSize)
    self.progress = progress
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    if totalBytesWritten > maximumSize || totalBytesExpectedToWrite > maximumSize {
      oversized.withLock { $0 = true }
      downloadTask.cancel()
      return
    }
    progress(totalBytesWritten, max(totalBytesExpectedToWrite, totalBytesWritten))
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
}
