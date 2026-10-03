import AppKit
import Foundation
import Synchronization

/// Shared download, cancellation and commit lifecycle for vendor installers.
class DownloadUpdateOperation: UpdateOperation, URLSessionDownloadDelegate, @unchecked Sendable {
  let app: App.Bundle
  private struct Work {
    var task: Task<Void, Never>?
    var committing = false
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
    work.withLock { work in
      guard !work.committing else { return }
      super.cancel()
      work.task?.cancel()
    }
  }

  func performUpdate() async throws { fatalError("Subclasses must implement performUpdate") }

  /// Once replacement starts, cancellation cannot interrupt rollback or suppress success.
  func beginCommit() throws {
    try work.withLock { work in
      try Task.checkCancellation()
      guard !isCancelled else { throw CancellationError() }
      work.committing = true
    }
  }

  func download(from url: URL, into directory: URL, maximumSize: Int = 8 * 1_024 * 1_024 * 1_024)
    async throws -> URL
  {
    guard url.scheme == "https" else { throw AppDownloadError.invalidMetadata }
    progressState = .downloading(loadedSize: 0, totalSize: 0)
    let (temporary, response) = try await URLSession.shared.download(from: url, delegate: self)
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https",
      (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= maximumSize
    else { throw AppDownloadError.invalidDownload }
    try Task.checkCancellation()
    let archive = directory.appendingPathComponent("download." + url.pathExtension.lowercased())
    try FileManager.default.moveItem(at: temporary, to: archive)
    return archive
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    progressState = .downloading(
      loadedSize: totalBytesWritten, totalSize: max(totalBytesExpectedToWrite, totalBytesWritten))
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}

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
    defer {
      if !running.isEmpty, running.allSatisfy(\.isTerminated),
        FileManager.default.fileExists(atPath: app.fileURL.path)
      {
        MacApplicationWorkspace.shared.openApplication(at: app.fileURL)
      }
    }
    running.forEach { $0.terminate() }
    for _ in 0..<100 {
      if running.allSatisfy(\.isTerminated) {
        try Task.checkCancellation()
        try await install()
        return
      }
      try await Task.sleep(for: .milliseconds(200))
    }
    throw AppDownloadError.applicationStillRunning
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
