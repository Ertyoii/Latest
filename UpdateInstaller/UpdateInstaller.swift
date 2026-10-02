// Copyright © 2026 Max Langer and ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import Foundation

/// Installs an App Store package without shell interpolation. The client is
/// authenticated by the listener; PackageKit validates the signed package.
final class UpdateInstaller: NSObject, UpdateInstallerProtocol {
  func performInstallation(
    ofPackageAt url: URL, appURL: URL, receiptData: Data,
    reply: @escaping (URL?, Error?) -> Void
  ) {
    do {
      guard url.isFileURL, url.pathExtension == "pkg", appURL.isFileURL, !receiptData.isEmpty,
        let expectedIdentifier = Bundle(url: appURL)?.bundleIdentifier
      else {
        throw failure("The App Store package, installed app, or receipt is unavailable.")
      }
      let volume =
        try appURL.resourceValues(forKeys: [.volumeURLKey]).volume ?? URL(fileURLWithPath: "/")
      let output = try performCommand(
        "/usr/sbin/installer",
        arguments: ["-dumplog", "-pkg", url.path, "-target", volume.path])
      let expression = try NSRegularExpression(
        pattern: "PackageKit: Registered bundle (\\S+) for uid 0")
      let range = NSRange(output.startIndex..<output.endIndex, in: output)
      let registeredURLs = expression.matches(in: output, range: range).compactMap {
        match -> URL? in
        guard let range = Range(match.range(at: 1), in: output),
          let candidate = URL(string: String(output[range])), candidate.isFileURL,
          Bundle(url: candidate)?.bundleIdentifier == expectedIdentifier
        else { return nil }
        return candidate
      }
      guard let installedURL = registeredURLs.min(by: { $0.path.count < $1.path.count }) else {
        throw failure("The installer did not register the expected app: \(expectedIdentifier).")
      }
      // Derive the receipt path from the actual installed bundle. Never use a
      // caller-provided receipt path as an arbitrary privileged write target.
      let destination = installedURL.appendingPathComponent("Contents/_MASReceipt/receipt")
      let fileManager = FileManager.default
      try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
      try receiptData.write(to: destination, options: .atomic)
      try fileManager.setAttributes(
        [
          .ownerAccountID: 0, .groupOwnerAccountID: 0,
          .posixPermissions: 0o644,
        ], ofItemAtPath: destination.path)
      reply(installedURL, nil)
    } catch { reply(nil, error) }
  }

  private func performCommand(_ executable: String, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    // Drain while the process runs; waiting first can deadlock on a full pipe.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else { throw failure(output) }
    return output
  }

  private func failure(_ message: String) -> NSError {
    NSError(
      domain: "LatestInstallerErrorDomain", code: 1,
      userInfo: [NSLocalizedDescriptionKey: message])
  }
}
