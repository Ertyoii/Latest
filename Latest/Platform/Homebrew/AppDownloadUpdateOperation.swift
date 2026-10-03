import AppKit
import CryptoKit
import Foundation
import Security
import Synchronization

/// Replaces a verified standalone app, retaining the old copy until installation succeeds.
final class AppDownloadUpdateOperation: UpdateOperation, @unchecked Sendable {
  private let app: App.Bundle
  private let source: AppDownloadSource
  private let task = Mutex<Task<Void, Never>?>(nil)

  init(app: App.Bundle, source: AppDownloadSource) {
    self.app = app
    self.source = source
    super.init(bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
  }

  override func execute() {
    super.execute()
    task.withLock { task in
      task = Task.detached { [self] in
        do {
          try await install()
          finish()
        } catch is CancellationError {
          cancel()
          finish()
        } catch {
          if isCancelled { finish() } else { finish(with: error) }
        }
      }
      if isCancelled { task?.cancel() }
    }
  }

  override func cancel() {
    super.cancel()
    task.withLock { $0?.cancel() }
  }

  private func install() async throws {
    let release = try await source.release()
    guard app.version.comparisonForUpdate(to: release.version) == .older else {
      throw AppDownloadError.versionMismatch
    }
    try Task.checkCancellation()
    let manager = FileManager.default
    let work = manager.temporaryDirectory.appendingPathComponent("Latest-" + UUID().uuidString)
    try manager.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: work) }

    progressState = .downloading(loadedSize: 0, totalSize: 0)
    let (download, response) = try await URLSession.shared.download(
      from: release.url,
      delegate: InstallerDownloadProgress { [weak self] loaded, total in
        self?.progressState = .downloading(loadedSize: loaded, totalSize: max(total, loaded))
      })
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      http.url?.scheme == "https"
    else { throw AppDownloadError.invalidDownload }
    let archive = work.appendingPathComponent("download." + release.url.pathExtension)
    try manager.moveItem(at: download, to: archive)
    if let hash = release.sha256 { try Self.verifyChecksum(of: archive, expected: hash) }
    try Task.checkCancellation()

    progressState = .extracting(progress: 0)
    let extracted = work.appendingPathComponent("payload")
    try manager.createDirectory(at: extracted, withIntermediateDirectories: true)
    let isDiskImage = archive.pathExtension.lowercased() == "dmg"
    do {
      if isDiskImage {
        _ = try await InstallerCommand.run(
          "/usr/bin/hdiutil",
          [
            "attach", archive.path, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint",
            extracted.path,
          ])
      } else {
        try await Self.extractZIP(at: archive, to: extracted)
      }
      let candidate = extracted.appendingPathComponent(release.appPath)
      let root = extracted.resolvingSymlinksInPath().path + "/"
      guard candidate.resolvingSymlinksInPath().path.hasPrefix(root) else {
        throw AppDownloadError.invalidDownload
      }
      try Self.validate(candidate: candidate, replacing: app, expectedVersion: release.version)
      try Task.checkCancellation()

      // Stage on the same volume, so final renames do not require a partial copy.
      let stage = app.fileURL.deletingLastPathComponent()
        .appendingPathComponent(".latest-update-" + UUID().uuidString)
      try manager.createDirectory(at: stage, withIntermediateDirectories: true)
      defer {
        // If rollback itself failed, retain the original at the reported recovery path.
        if !manager.fileExists(atPath: stage.appendingPathComponent("original.app").path) {
          try? manager.removeItem(at: stage)
        }
      }
      let stagedApp = stage.appendingPathComponent("candidate.app")
      _ = try await InstallerCommand.run("/usr/bin/ditto", [candidate.path, stagedApp.path])
      try Self.validate(candidate: stagedApp, replacing: app, expectedVersion: release.version)
      try Task.checkCancellation()
      let reopen = try await Self.quitApplicationIfNeeded(app)
      try Task.checkCancellation()
      guard let current = BundleCollector.collectBundle(at: app.fileURL),
        current.bundleIdentifier == app.bundleIdentifier, current.version == app.version
      else { throw AppDownloadError.versionMismatch }
      progressState = .installing
      // No cancellation point between the two renames: either the new app or the
      // restored original must occupy the user's path when this method returns.
      try Self.replaceApplication(at: app.fileURL, with: stagedApp, backupDirectory: stage)
      try? manager.removeItem(at: stage.appendingPathComponent("original.app"))
      if reopen {
        await MainActor.run { MacApplicationWorkspace.shared.openApplication(at: app.fileURL) }
      }
    } catch {
      if isDiskImage {
        _ = try? await InstallerCommand.run(
          "/usr/bin/hdiutil", ["detach", extracted.path], cancellable: false)
      }
      throw error
    }
    if isDiskImage {
      _ = try? await InstallerCommand.run(
        "/usr/bin/hdiutil", ["detach", extracted.path], cancellable: false)
    }
  }

  static func extractZIP(at archive: URL, to directory: URL) async throws {
    let listing = try await InstallerCommand.run("/usr/bin/zipinfo", ["-1", archive.path])
    guard !listing.isEmpty,
      listing.split(separator: "\n").allSatisfy({
        !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..")
      })
    else { throw AppDownloadError.invalidDownload }
    // ditto also rejects archive members that traverse an extracted symlink.
    _ = try await InstallerCommand.run(
      "/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
  }

  static func verifyChecksum(of url: URL, expected: String) throws {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hash = SHA256()
    while let data = try file.read(upToCount: 1_024 * 1_024), !data.isEmpty {
      try Task.checkCancellation()
      hash.update(data: data)
    }
    let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
    guard actual == expected else { throw AppDownloadError.checksumMismatch }
  }

  static func validate(candidate: URL, replacing app: App.Bundle, expectedVersion: Version) throws {
    guard let installed = BundleCollector.collectBundle(at: candidate),
      installed.bundleIdentifier == app.bundleIdentifier
    else { throw AppDownloadError.identityMismatch }
    guard app.version.comparisonForUpdate(to: installed.version) == .older,
      installed.version.comparisonForUpdate(to: expectedVersion) == .samePrecedence
        || installed.version.comparisonForUpdate(to: expectedVersion) == .newer
    else { throw AppDownloadError.versionMismatch }

    var originalCode: SecStaticCode?
    var candidateCode: SecStaticCode?
    var requirement: SecRequirement?
    var information: CFDictionary?
    var candidateInformation: CFDictionary?
    guard SecStaticCodeCreateWithPath(app.fileURL as CFURL, [], &originalCode) == errSecSuccess,
      SecStaticCodeCreateWithPath(candidate as CFURL, [], &candidateCode) == errSecSuccess,
      let originalCode, let candidateCode,
      SecCodeCopySigningInformation(
        originalCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        == errSecSuccess,
      let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
      !team.isEmpty,
      SecCodeCopySigningInformation(
        candidateCode, SecCSFlags(rawValue: kSecCSSigningInformation), &candidateInformation)
        == errSecSuccess,
      (candidateInformation as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        == team,
      SecCodeCopyDesignatedRequirement(originalCode, [], &requirement) == errSecSuccess,
      let requirement,
      SecStaticCodeCheckValidity(
        candidateCode,
        SecCSFlags(
          rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate),
        requirement) == errSecSuccess
    else { throw AppDownloadError.identityMismatch }
  }

  static func replaceApplication(at target: URL, with candidate: URL, backupDirectory: URL) throws {
    let manager = FileManager.default
    let backup = backupDirectory.appendingPathComponent("original.app")
    try manager.moveItem(at: target, to: backup)
    do {
      try manager.moveItem(at: candidate, to: target)
    } catch {
      do { try manager.moveItem(at: backup, to: target) } catch {
        throw AppDownloadError.replacementFailed("The original app was saved at \(backup.path).")
      }
      throw error
    }
  }

  @MainActor
  static func quitApplicationIfNeeded(_ app: App.Bundle) async throws -> Bool {
    let running = NSWorkspace.shared.runningApplications.filter {
      $0.bundleURL?.standardizedFileURL == app.fileURL.standardizedFileURL
    }
    guard !running.isEmpty else { return false }
    let alert = NSAlert()
    alert.messageText = "Quit \(app.name) to install its update?"
    alert.informativeText = "Save your work first. The app will reopen after the update."
    alert.addButton(withTitle: "Quit and Update")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { throw CancellationError() }
    running.forEach { $0.terminate() }
    for _ in 0..<100 {
      if running.allSatisfy(\.isTerminated) { return true }
      try await Task.sleep(for: .milliseconds(200))
    }
    throw AppDownloadError.applicationStillRunning
  }
}

/// Fixed system tools, argument arrays (never shell commands), bounded diagnostics.
enum InstallerCommand {
  static func run(_ executable: String, _ arguments: [String], cancellable: Bool = true)
    async throws -> String
  {
    if cancellable { try Task.checkCancellation() }
    let process = Process()
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath: output.path, contents: nil)
    let handle = try FileHandle(forWritingTo: output)
    defer {
      try? handle.close()
      try? FileManager.default.removeItem(at: output)
    }
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = handle
    process.standardError = handle
    try process.run()
    let deadline = ContinuousClock.now.advanced(by: .seconds(300))
    var terminationRequested: ContinuousClock.Instant?
    while process.isRunning {
      if (cancellable && Task.isCancelled) || ContinuousClock.now >= deadline {
        if let terminationRequested {
          if ContinuousClock.now - terminationRequested > .seconds(5) {
            kill(process.processIdentifier, SIGKILL)
          }
        } else {
          process.terminate()
          terminationRequested = .now
        }
      }
      // Detached sleep allows cleanup commands to complete after cancellation.
      await Task.detached { try? await Task.sleep(for: .milliseconds(100)) }.value
    }
    if cancellable { try Task.checkCancellation() }
    guard ContinuousClock.now < deadline else {
      throw AppDownloadError.toolFailed("The system installer tool timed out.")
    }
    let reader = try FileHandle(forReadingFrom: output)
    defer { try? reader.close() }
    let data = try reader.read(upToCount: 8 * 1_024 * 1_024) ?? Data()
    guard (try reader.read(upToCount: 1))?.isEmpty != false else {
      throw AppDownloadError.invalidDownload
    }
    guard process.terminationStatus == 0 else {
      throw AppDownloadError.toolFailed(String(decoding: data.suffix(2_048), as: UTF8.self))
    }
    return String(decoding: data, as: UTF8.self)
  }
}

/// URLSession keeps the downloaded file on disk while reporting real byte progress.
final class InstallerDownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
  private let progress: @Sendable (Int64, Int64) -> Void

  init(progress: @escaping @Sendable (Int64, Int64) -> Void) { self.progress = progress }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    progress(totalBytesWritten, totalBytesExpectedToWrite)
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
}
