import CryptoKit
import Foundation
import Security
import Synchronization

enum ObsidianUpdate {
  struct Release: Decodable, Sendable {
    let minimumVersion: String
    let latestVersion: String
    let downloadUrl: URL
    let hash: String
    let signature: String
    var isEarlyAccess = false

    private enum CodingKeys: String, CodingKey {
      case minimumVersion, latestVersion, downloadUrl, hash, signature
    }
  }

  private struct Manifest: Decodable {
    let minimumVersion: String
    let latestVersion: String
    let downloadUrl: URL
    let hash: String
    let signature: String
    let beta: Release?

    var stable: Release {
      Release(
        minimumVersion: minimumVersion, latestVersion: latestVersion,
        downloadUrl: downloadUrl, hash: hash, signature: signature)
    }
  }

  /// Follow Obsidian's explicit user preference, never infer a beta opt-in from version numbers.
  static func release(from data: Data, includesEarlyAccess: Bool) throws -> Release {
    let manifest = try JSONDecoder().decode(Manifest.self, from: data)
    if includesEarlyAccess, var beta = manifest.beta {
      beta.isEarlyAccess = true
      return beta
    }
    return manifest.stable
  }

  static func check(_ bundle: App.Bundle) async throws -> App.Update {
    var request = URLRequest(
      url: URL(
        string:
          "https://raw.githubusercontent.com/obsidianmd/obsidian-releases/master/desktop-releases.json"
      )!,
      cachePolicy: .reloadIgnoringLocalCacheData)
    request.timeoutInterval = 30
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 65_536 else {
      throw AppDownloadError.invalidMetadata
    }
    let settingsURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
    let settings = (try? Data(contentsOf: settingsURL)).flatMap {
      (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
    }
    let release = try release(
      from: data, includesEarlyAccess: settings?["insider"] as? Bool == true)
    let version = Version(versionNumber: release.latestVersion, buildNumber: nil)
    let plist = try Data(contentsOf: bundle.fileURL.appendingPathComponent("Contents/Info.plist"))
    let information =
      try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
    let installer = Version(
      versionNumber: information?["CFBundleShortVersionString"] as? String, buildNumber: nil)
    let compatible = [.samePrecedence, .newer].contains(
      installer.comparisonForUpdate(
        to:
          Version(versionNumber: release.minimumVersion, buildNumber: nil)))
    let canInstall = compatible && !release.isEarlyAccess
    let action: App.Update.Action
    if canInstall {
      action = .builtIn { app in
        UpdateQueue.shared.addOperation(ObsidianUpdateOperation(app: app, release: release))
      }
    } else if release.isEarlyAccess && compatible {
      // Catalyst downloads require Obsidian's authenticated session. Keep its
      // credentials in Obsidian and let its own updater download these releases.
      action = .external(label: bundle.name) { app in
        Task { @MainActor in MacApplicationWorkspace.shared.openApplication(at: app.fileURL) }
      }
    } else {
      action = .external(label: "Obsidian Installer") { _ in
        Task { @MainActor in
          MacApplicationWorkspace.shared.open(URL(string: "https://obsidian.md/download")!)
        }
      }
    }
    return App.Update(
      app: bundle, remoteVersion: version, minimumOSVersion: nil,
      source: canInstall ? .directDownload : .vendor, date: nil,
      releaseNotes: ReleaseNotesSourceCatalog.releaseNotes(for: bundle, remoteVersion: version),
      updateAction: action)
  }

  static func verify(_ data: Data, release: Release) throws {
    guard
      SHA256.hash(data: data).withUnsafeBytes({ Data($0).base64EncodedString() }) == release.hash,
      let certificateData = Data(base64Encoded: certificate),
      let certificate = SecCertificateCreateWithData(nil, certificateData as CFData),
      let key = SecCertificateCopyKey(certificate),
      let signature = Data(base64Encoded: release.signature),
      SecKeyVerifySignature(
        key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, signature as CFData, nil)
    else { throw AppDownloadError.checksumMismatch }
  }

  // Obsidian's public payload-signing certificate, shipped by its desktop launcher.
  private static let certificate =
    "MIIDjzCCAnegAwIBAgIJAOFHLJ2gTCBzMA0GCSqGSIb3DQEBCwUAMF4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIDApTb21lLVN0YXRlMREwDwYDVQQKDAhEeW5hbGlzdDERMA8GA1UECwwIRHluYWxpc3QxFDASBgNVBAMMC2R5bmFsaXN0LmlvMB4XDTE2MDUxNjAyMTA1NFoXDTQwMDUxMDAyMTA1NFowXjELMAkGA1UEBhMCVVMxEzARBgNVBAgMClNvbWUtU3RhdGUxETAPBgNVBAoMCER5bmFsaXN0MREwDwYDVQQLDAhEeW5hbGlzdDEUMBIGA1UEAwwLZHluYWxpc3QuaW8wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDcodSNp30B0oE+2vRUdr//SGfbDow+67OtGuRYQSjn86bn55fQXhMJb5xgZ0natiCriCyllLWgPf+4PnxGRSJZGbm38QSArb0MWR8/yXA+q+7nZisIsN2dXih8B3APImxJ4A50nsK/C+fl7nYdo04iz3oerP0UhLDrsLbL+9rdmshjB1boLPf6QpAAC57OTPQpFBd2hFoS6xAnIb708SHOndsrWDIFEFVCPDYcme3WF5jznuT05OFGMIX8SZe2jXpg2Vco/1oKRPC7mYFN5B0JTZ7mOH48vB/zPNIsVz8KHh3P9Ru2fC2r3nPDXFGKzcUZneJmXh4LIUVqwdEPw7hvAgMBAAGjUDBOMB0GA1UdDgQWBBTF2xMx8xVDZ2wteJPsHUe0OCu18TAfBgNVHSMEGDAWgBTF2xMx8xVDZ2wteJPsHUe0OCu18TAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQB6rgBF+DvDHifP+U6ZFqJ4mX1nalEXEPI1jvRZaOheKpkOEBbhkCAosbBEmYxfj8xay1GGgB9nkJk2dodRsGVhrZz+CwGR+hSEfYDQwMBvmzm3OcETfEtvwEAU1P93prbxul2oSWP48AVDDYKepxTZvW/yZcnoHI9XzhLNMYIEvOs+wKWAOF0+BjsIukQouaXs6gklul2J99IqpdPhw2l4l7mkPx8htCbTE47GTraHt2i2mwyBZSKbfqzi73Fj5SFRtZlWJDNPKoWxcFg291B7IHumd5jwAUdVJit3K5Tgt/q4OzwokcDZcrh5lJg0+Kstsz4RDWDbfzTNJuKnoueR"
}

final class ObsidianUpdateOperation: UpdateOperation, @unchecked Sendable {
  private let app: App.Bundle
  private let release: ObsidianUpdate.Release
  private let task = Mutex<Task<Void, Never>?>(nil)

  init(app: App.Bundle, release: ObsidianUpdate.Release) {
    self.app = app
    self.release = release
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
    guard !release.isEarlyAccess, release.downloadUrl.scheme == "https",
      release.latestVersion.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression)
        != nil,
      app.version.comparisonForUpdate(
        to:
          Version(versionNumber: release.latestVersion, buildNumber: nil)) == .older
    else { throw AppDownloadError.invalidMetadata }
    progressState = .downloading(loadedSize: 0, totalSize: 0)
    let (url, response) = try await URLSession.shared.download(
      from: release.downloadUrl,
      delegate: InstallerDownloadProgress { [weak self] loaded, total in
        self?.progressState = .downloading(loadedSize: loaded, totalSize: max(total, loaded))
      })
    guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https",
      (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 128 * 1_024 * 1_024
    else { throw AppDownloadError.invalidDownload }
    let compressed = try Data(contentsOf: url, options: .mappedIfSafe)
    try ObsidianUpdate.verify(compressed, release: release)
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(
      "Latest-Obsidian-" + UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let archive = directory.appendingPathComponent("payload.asar.gz")
    try manager.moveItem(at: url, to: archive)
    progressState = .extracting(progress: 0)
    _ = try await InstallerCommand.run("/usr/bin/gzip", ["-d", archive.path])
    let payload = archive.deletingPathExtension()
    guard InstalledAppVersion.asarVersion(at: payload) == release.latestVersion else {
      throw AppDownloadError.versionMismatch
    }
    let support = manager.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/obsidian")
    try manager.createDirectory(at: support, withIntermediateDirectories: true)
    let target = support.appendingPathComponent("obsidian-\(release.latestVersion).asar")
    if InstalledAppVersion.asarVersion(at: target) == release.latestVersion { return }
    let staged = support.appendingPathComponent(".latest-" + UUID().uuidString + ".asar")
    try manager.copyItem(at: payload, to: staged)
    defer { try? manager.removeItem(at: staged) }
    let reopen = try await AppDownloadUpdateOperation.quitApplicationIfNeeded(app)
    try Task.checkCancellation()
    progressState = .installing
    try manager.moveItem(at: staged, to: target)
    if reopen {
      await MainActor.run { MacApplicationWorkspace.shared.openApplication(at: app.fileURL) }
    }
  }
}
