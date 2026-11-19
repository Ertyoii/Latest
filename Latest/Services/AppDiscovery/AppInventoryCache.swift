// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import Foundation

/// The last local inventory can populate the sidebar before a volume responds.
/// Provider results and installation actions always come from a live check.
struct AppInventoryCache {
  let url: URL

  static var live: Self {
    Self(
      url: URL.cachesDirectory
        .appending(component: Bundle.main.bundleIdentifier ?? "com.max-langer.Latest")
        .appending(component: "InstalledApps-v1.plist"))
  }

  private struct Record: Codable {
    let url: URL
    let name: String
    let identifier: String
    let version: String?
    let build: String?
    let source: String
    let date: Date

    init(_ bundle: App.Bundle) {
      url = bundle.fileURL
      name = bundle.name
      identifier = bundle.bundleIdentifier
      version = bundle.version.versionNumber
      build = bundle.version.buildNumber
      source = bundle.source.rawValue
      date = bundle.modificationDate
    }

    func bundle(in directory: URL) -> App.Bundle? {
      let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
      guard url.isFileURL, url.pathExtension.lowercased() == "app",
        url.standardizedFileURL.path.hasPrefix(prefix),
        let source = App.Source(rawValue: source)
      else { return nil }
      return App.Bundle(
        version: Version(versionNumber: version, buildNumber: build), name: name,
        bundleIdentifier: identifier, fileURL: url, source: source, modificationDate: date)
    }
  }

  func load(for directories: [URL]) -> [URL: [App.Bundle]] {
    guard let data = try? Data(contentsOf: url),
      let saved = try? PropertyListDecoder().decode([String: [Record]].self, from: data)
    else { return [:] }
    var result = [URL: [App.Bundle]]()
    for directory in directories {
      let root = directory.standardizedFileURL
      result[directory] = saved[root.path]?.compactMap { $0.bundle(in: root) }
    }
    return result
  }

  func store(_ inventory: [URL: [App.Bundle]]) {
    var saved = [String: [Record]]()
    for (directory, bundles) in inventory {
      saved[directory.standardizedFileURL.path] = bundles.map(Record.init)
    }
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    guard let data = try? encoder.encode(saved) else { return }
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }
}
