// Fork contributions © 2026 ertyoii.
// Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import CryptoKit
import Foundation

/// Shared by the production capture test and its command-line gate. References
/// are immutable inputs; a missing reference is never a request to record one.
enum ProductionVisualReference {
  static let schema = 1
  static let names = [false, true].flatMap { dark in
    ["initial", "selection", "search", "downloading", "pinned", "toolbar"].map {
      "production-\($0)-\(dark ? "dark" : "light").png"
    }
      + [460, 680].flatMap { width in
        [false, true].map {
          "web-\(width)-\(dark ? "dark" : "light")-\($0 ? "scrolled" : "top").png"
        }
      }
  }.sorted()

  struct Provenance: Codable, Equatable {
    let revision: String
    let productionSources: [String: String]
    let captureSources: [String: String]
    let environment: [String: String]
  }

  struct Request: Codable {
    let mode: String
    let output: URL
    let reference: URL?
    let provenance: Provenance
  }

  struct Image: Codable {
    let name: String
    let width: Int
    let height: Int
    let rgbaSHA256: String
  }

  struct Manifest: Codable {
    let schemaVersion: Int
    let kind: String
    let recordedAt: Date
    let provenance: Provenance
    let settings: [String: String]
    let images: [Image]
  }

  struct Comparison: Codable {
    let name: String
    let pixels: Int
    let changedPixels: Int
    let firstChangedX: Int?
    let firstChangedY: Int?
  }

  struct Report: Codable {
    let referenceRevision: String
    let candidateRevision: String
    let comparisons: [Comparison]
    var changedPixels: Int { comparisons.reduce(0) { $0 + $1.changedPixels } }
  }

  struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw Failure(message: message) }
  }

  static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func write<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(value).write(to: url, options: .atomic)
  }

  static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    do { return try JSONDecoder().decode(type, from: Data(contentsOf: url)) } catch {
      throw Failure(message: "Missing or malformed \(url.path): \(error.localizedDescription)")
    }
  }

  static func bitmap(at url: URL) throws -> NSBitmapImageRep {
    let data: Data
    do { data = try Data(contentsOf: url) } catch {
      throw Failure(message: "Missing image: \(url.path)")
    }
    try require(data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]), "Malformed PNG: \(url.path)")
    guard let bitmap = NSBitmapImageRep(data: data) else {
      throw Failure(message: "Cannot decode PNG: \(url.path)")
    }
    return bitmap
  }

  /// Fixed sRGB, premultiplied RGBA8; compare decoded pixels, never PNG metadata.
  static func rgba(_ bitmap: NSBitmapImageRep) throws -> Data {
    guard let image = bitmap.cgImage else { throw Failure(message: "Missing CGImage") }
    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh
    try require(
      width > 0 && height > 0 && width <= 4096 && height <= 4096, "Invalid image dimensions")
    var data = Data(count: width * height * 4)
    try data.withUnsafeMutableBytes { bytes in
      guard
        let context = CGContext(
          data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        )
      else { throw Failure(message: "Cannot normalize RGBA") }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return data
  }

  static func describe(_ bitmap: NSBitmapImageRep, name: String) throws -> Image {
    Image(
      name: name, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
      rgbaSHA256: hash(try rgba(bitmap)))
  }

  static func validate(_ directory: URL, kind: String) throws -> Manifest {
    let manifest = try read(Manifest.self, from: directory.appendingPathComponent("manifest.json"))
    try require(manifest.schemaVersion == schema, "Incompatible manifest schema")
    try require(manifest.kind == kind, "Expected \(kind) manifest")
    try require(
      manifest.images.map(\.name).sorted() == names, "Incomplete or duplicate image matrix")
    try require(manifest.provenance.revision.count == 40, "Missing revision provenance")
    try require(!manifest.provenance.productionSources.isEmpty, "Missing production source hashes")
    try require(!manifest.provenance.captureSources.isEmpty, "Missing capture source hashes")
    try require(
      !manifest.provenance.environment.isEmpty && !manifest.settings.isEmpty,
      "Missing capture environment/settings")
    for item in manifest.images {
      let bitmap = try bitmap(at: directory.appendingPathComponent(item.name))
      try require(
        bitmap.pixelsWide == item.width && bitmap.pixelsHigh == item.height,
        "Incompatible dimensions: \(item.name)")
      try require(
        hash(try rgba(bitmap)) == item.rgbaSHA256, "Image integrity failure: \(item.name)")
    }
    return manifest
  }

  static func compatible(_ original: Manifest, provenance: Provenance) throws {
    try require(
      original.provenance.captureSources == provenance.captureSources,
      "Incompatible capture/fixture source hashes; retain the frozen harness")
    try require(
      original.provenance.environment == provenance.environment,
      "Incompatible machine, OS, Xcode, or launch settings; use the same system")
  }

  static func compareRequired(reference: URL, candidate: URL) throws -> Report {
    let original = try validate(reference, kind: "original")
    let current = try validate(candidate, kind: "candidate")
    try compatible(original, provenance: current.provenance)
    try require(original.settings == current.settings, "Incompatible runtime capture settings")
    var comparisons: [Comparison] = []
    for name in names {
      let lhs = try bitmap(at: reference.appendingPathComponent(name))
      let rhs = try bitmap(at: candidate.appendingPathComponent(name))
      try require(
        lhs.pixelsWide == rhs.pixelsWide && lhs.pixelsHigh == rhs.pixelsHigh,
        "Candidate dimensions differ: \(name)")
      let a = [UInt8](try rgba(lhs))
      let b = [UInt8](try rgba(rhs))
      var changed = 0
      var first: Int?
      for offset in stride(from: 0, to: a.count, by: 4) {
        if a[offset] != b[offset] || a[offset + 1] != b[offset + 1]
          || a[offset + 2] != b[offset + 2] || a[offset + 3] != b[offset + 3]
        {
          changed += 1
          if first == nil { first = offset / 4 }
        }
      }
      comparisons.append(
        Comparison(
          name: name, pixels: a.count / 4, changedPixels: changed,
          firstChangedX: first.map { $0 % lhs.pixelsWide },
          firstChangedY: first.map { $0 / lhs.pixelsWide }))
    }
    let report = Report(
      referenceRevision: original.provenance.revision,
      candidateRevision: current.provenance.revision, comparisons: comparisons)
    try write(report, to: candidate.appendingPathComponent("comparison.json"))
    for comparison in comparisons {
      print(
        "PRODUCTION_PARITY \(comparison.name) changed_pixels=\(comparison.changedPixels) pixels=\(comparison.pixels)"
      )
    }
    try require(
      report.changedPixels == 0,
      "Exact production parity failed: \(report.changedPixels) changed pixels across \(names.count) images; see \(candidate.path)/comparison.json"
    )
    return report
  }
}
