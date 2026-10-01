// Fork contributions © 2026 ertyoii.
// Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import Foundation

@main
struct ProductionParityDriver {
  typealias Gate = ProductionVisualReference

  static func run(
    _ arguments: [String], at root: URL, log: URL? = nil, timeout: TimeInterval? = nil
  ) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = root
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
    if let timeout {
      DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
    }
    defer { watchdog.cancel() }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if let log { try data.write(to: log) }
    let text = String(decoding: data, as: UTF8.self)
    try Gate.require(
      process.terminationStatus == 0,
      "Command failed (\(process.terminationStatus)): \(arguments.joined(separator: " "))\n\(log.map { "See " + $0.path } ?? text)"
    )
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func sources(_ paths: [String], root: URL) throws -> [String: String] {
    let list = try run(
      ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--"] + paths,
      at: root)
    var hashes: [String: String] = [:]
    for file in list.split(separator: "\0").map(String.init).sorted() {
      hashes[file] = Gate.hash(try Data(contentsOf: root.appendingPathComponent(file)))
    }
    return hashes
  }

  static func provenance(root: URL) throws -> Gate.Provenance {
    let platform = try run(["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"], at: root)
    let identity = platform.split(separator: "\n").first { $0.contains("IOPlatformUUID") }
    try Gate.require(identity != nil, "Cannot establish same-machine identity")
    return Gate.Provenance(
      revision: try run(["git", "rev-parse", "HEAD"], at: root),
      productionSources: try sources(
        [
          "Latest", "Frameworks", "Latest.xcodeproj/project.pbxproj",
          "Latest.xcodeproj/xcshareddata/xcschemes/Latest.xcscheme",
          "Latest.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        ], root: root),
      captureSources: try sources(
        [
          "Tests/Migration/ProductionVisualCapture.swift",
          "Tests/Migration/ProductionVisualReference.swift",
          "Tests/App/LocalUATFixture.swift",
          "script/production_visual_parity.sh", "script/production_visual_parity.swift",
        ], root: root),
      environment: [
        "machine": Gate.hash(Data(identity!.utf8)),
        "hardware": try run(["sysctl", "-n", "hw.model"], at: root),
        "os": try run(["sw_vers"], at: root),
        "xcode": try run(["xcodebuild", "-version"], at: root),
        "developerDirectory": try run(["xcode-select", "-p"], at: root),
        "language": "en", "region": "US", "timezone": "UTC", "configuration": "Debug",
        "captureBuild":
          "Derived Latest target; all production phases/configurations/dependencies; alternate Tests entrypoint; PRODUCTION_VISUAL_CAPTURE prevents the shared Tests fixture importing its own module; isolated identity; signing/coverage off",
        "captureLaunch":
          "bundle executable -AppleLanguages (en) -AppleLocale en_US; normal SwiftUI App.main",
      ])
  }

  /// Derive the capture build from the real target rather than maintaining a
  /// second production source/resource list. Only its entrypoint is replaced.
  static func captureProject(root: URL) throws -> URL {
    let manager = FileManager.default
    let project = root.appendingPathComponent("build/production-capture/Latest.xcodeproj")
    try manager.createDirectory(at: project, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("Latest.xcodeproj")
    var plist =
      try PropertyListSerialization.propertyList(
        from: Data(contentsOf: source.appendingPathComponent("project.pbxproj")),
        options: [], format: nil) as! [String: Any]
    var objects = plist["objects"] as! [String: [String: Any]]
    let targetID = try objects.first {
      $0.value["isa"] as? String == "PBXNativeTarget" && $0.value["name"] as? String == "Latest"
    }.map(\.key).unwrap("Missing production target")
    let target = objects[targetID]!
    let sourcePhaseID = try (target["buildPhases"] as! [String]).first {
      objects[$0]?["isa"] as? String == "PBXSourcesBuildPhase"
    }.unwrap("Missing production source phase")
    var phase = objects[sourcePhaseID]!
    let productionFiles = phase["files"] as! [String]
    var files = productionFiles
    let entrypoints = files.filter {
      let ref = objects[$0]?["fileRef"] as! String
      return objects[ref]?["path"] as? String == "main.swift"
    }
    try Gate.require(entrypoints.count == 1, "Expected exactly one production app entrypoint")
    files.removeAll { entrypoints.contains($0) }
    let additions = [
      "Tests/Migration/ProductionVisualCapture.swift",
      "Tests/Migration/ProductionVisualReference.swift",
      "Tests/App/LocalUATFixture.swift",
    ]
    for (index, path) in additions.enumerated() {
      let ref = String(format: "53CA%020X", index * 2)
      let build = String(format: "53CA%020X", index * 2 + 1)
      try Gate.require(objects[ref] == nil && objects[build] == nil, "Capture object ID collision")
      objects[ref] = [
        "isa": "PBXFileReference", "lastKnownFileType": "sourcecode.swift",
        "path": root.appendingPathComponent(path).path, "sourceTree": "<absolute>",
      ]
      objects[build] = ["isa": "PBXBuildFile", "fileRef": ref]
      files.append(build)
    }
    try Gate.require(
      Set(files.filter { productionFiles.contains($0) })
        == Set(productionFiles).subtracting(entrypoints)
        && files.count == productionFiles.count - 1 + additions.count,
      "Capture target must preserve every production source except its entrypoint")
    phase["files"] = files
    objects[sourcePhaseID] = phase
    let configList = objects[target["buildConfigurationList"] as! String]!
    for id in configList["buildConfigurations"] as! [String] {
      var config = objects[id]!
      var settings = config["buildSettings"] as! [String: Any]
      settings["PRODUCT_NAME"] = "Latest Visual Capture"
      settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.max-langer.Latest.visualcapture"
      let existing = settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]
      if var conditions = existing as? [String] {
        conditions.append("PRODUCTION_VISUAL_CAPTURE")
        settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = conditions
      } else {
        settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] =
          (existing as? String ?? "$(inherited)") + " PRODUCTION_VISUAL_CAPTURE"
      }
      config["buildSettings"] = settings
      objects[id] = config
    }
    let projectID = plist["rootObject"] as! String
    objects[projectID]!["projectDirPath"] = root.path
    let mainGroup = objects[projectID]!["mainGroup"] as! String
    objects[mainGroup]!["path"] = root.path
    objects[mainGroup]!["sourceTree"] = "<absolute>"
    plist["objects"] = objects
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: project.appendingPathComponent("project.pbxproj"), options: .atomic)
    for path in [
      "xcshareddata/xcschemes/Latest.xcscheme",
      "project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
    ] {
      let destination = project.appendingPathComponent(path)
      try manager.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      var data = try Data(contentsOf: source.appendingPathComponent(path))
      if path.hasSuffix(".xcscheme") {
        let scheme = String(decoding: data, as: UTF8.self)
          .replacingOccurrences(of: "container:Latest.xcodeproj", with: "container:" + project.path)
          .replacingOccurrences(of: "Latest Dev.app", with: "Latest Visual Capture.app")
        data = Data(scheme.utf8)
      }
      try data.write(to: destination, options: .atomic)
    }
    return project
  }

  static func buildCaptureApp(root: URL, log: URL) throws -> URL {
    let project = try captureProject(root: root)
    _ = try run(
      [
        "xcodebuild", "-project", project.path, "-scheme", "Latest", "-configuration", "Debug",
        "-destination", "platform=macOS", "-derivedDataPath", "build/ProductionCaptureDerivedData",
        "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile",
        "CLANG_MODULE_CACHE_PATH=build/ModuleCache", "CODE_SIGNING_ALLOWED=NO",
        "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "CLANG_ENABLE_CODE_COVERAGE=NO",
        "ENABLE_CODE_COVERAGE=NO", "build",
      ], at: root, log: log)
    return root.appendingPathComponent(
      "build/ProductionCaptureDerivedData/Build/Products/Debug/Latest Visual Capture.app/Contents/MacOS/Latest Visual Capture"
    )
  }

  static func capture(
    mode: String, reference: URL?, output: URL, root: URL, originalRevision: String?
  ) throws {
    let manager = FileManager.default
    let provenance = try provenance(root: root)
    if mode == "capture-original" {
      let revision = try run(["git", "rev-parse", originalRevision! + "^{commit}"], at: root)
      try Gate.require(
        revision == provenance.revision,
        "Recording requires HEAD at the explicitly supplied original revision")
      _ = try run(
        [
          "git", "diff", "--exit-code", revision, "--", "Latest", "Frameworks",
          "Latest.xcodeproj/project.pbxproj",
          "Latest.xcodeproj/xcshareddata/xcschemes/Latest.xcscheme",
          "Latest.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        ], at: root)
      let untracked = try run(
        ["git", "ls-files", "--others", "--exclude-standard", "--", "Latest", "Frameworks"],
        at: root)
      try Gate.require(
        untracked.isEmpty, "Recording requires an unchanged original production tree")
    } else if let reference {
      try Gate.compatible(try Gate.validate(reference, kind: "original"), provenance: provenance)
      let originalPath = reference.resolvingSymlinksInPath().path
      let candidatePath = output.resolvingSymlinksInPath().path
      try Gate.require(
        candidatePath != originalPath && !candidatePath.hasPrefix(originalPath + "/"),
        "Candidate output must be separate from the original")
    }
    try Gate.require(
      !manager.fileExists(atPath: output.path),
      "Refusing to overwrite capture directory: \(output.path)")
    let build = root.appendingPathComponent("build")
    try manager.createDirectory(at: build, withIntermediateDirectories: true)
    let lock = build.appendingPathComponent("production-visual-request.lock")
    do { try manager.createDirectory(at: lock, withIntermediateDirectories: false) } catch {
      throw Gate.Failure(message: "Another parity capture owns the request lock: \(lock.path)")
    }
    defer { try? manager.removeItem(at: lock) }
    let request = build.appendingPathComponent("production-visual-request.json")
    try Gate.require(
      !manager.fileExists(atPath: request.path), "Stale parity request exists: \(request.path)")
    try manager.createDirectory(at: output, withIntermediateDirectories: true)
    try Gate.write(
      Gate.Request(mode: mode, output: output, reference: reference, provenance: provenance),
      to: request)
    defer { try? manager.removeItem(at: request) }
    print("Capturing \(mode); log: \(output.path)/capture.log")
    fflush(stdout)
    let executable = try buildCaptureApp(
      root: root, log: output.appendingPathComponent("build.log"))
    _ = try run(
      [executable.path, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"],
      at: root, log: output.appendingPathComponent("capture.log"), timeout: 120)
    let final = try self.provenance(root: root)
    try Gate.require(
      final.revision == provenance.revision
        && final.productionSources == provenance.productionSources
        && final.captureSources == provenance.captureSources
        && final.environment == provenance.environment,
      "Sources, revision or environment changed during capture")
    _ = try Gate.validate(output, kind: mode == "capture-original" ? "original" : "candidate")
    if let reference { _ = try Gate.compareRequired(reference: reference, candidate: output) }
    print("PRODUCTION_PARITY PASS \(mode) images=\(Gate.names.count) output=\(output.path)")
  }

  /// End-to-end negative controls use real recorded windows, copied inputs, and
  /// the same required file verifier used after capture. The original is never edited.
  static func negativeControls(reference: URL, candidate: URL, output: URL) throws {
    let manager = FileManager.default
    try Gate.require(
      !manager.fileExists(atPath: output.path), "Refusing to overwrite negative-control evidence")
    try manager.createDirectory(at: output, withIntermediateDirectories: true)
    _ = try Gate.compareRequired(reference: reference, candidate: candidate)
    var outcomes: [String: String] = [:]
    func rejects(_ name: String, edit: (URL) throws -> Void, expected: String) throws {
      let copy = output.appendingPathComponent(name)
      try manager.createDirectory(at: copy, withIntermediateDirectories: true)
      for file in ["manifest.json"] + Gate.names {
        try manager.copyItem(
          at: reference.appendingPathComponent(file), to: copy.appendingPathComponent(file))
      }
      try edit(copy)
      do {
        _ = try Gate.compareRequired(reference: copy, candidate: candidate)
        throw Gate.Failure(message: "Negative control unexpectedly passed: \(name)")
      } catch let failure as Gate.Failure {
        try Gate.require(
          failure.message.contains(expected),
          "Unexpected negative-control failure \(name): \(failure.message)")
        outcomes[name] = failure.message
        print("NEGATIVE_GATE PASS \(name): \(failure.message)")
      }
    }
    try rejects(
      "missing-directory", edit: { try manager.removeItem(at: $0) },
      expected: "Missing or malformed")
    try rejects(
      "missing-manifest",
      edit: { try manager.removeItem(at: $0.appendingPathComponent("manifest.json")) },
      expected: "Missing or malformed")
    try rejects(
      "malformed-manifest",
      edit: { try Data("{}".utf8).write(to: $0.appendingPathComponent("manifest.json")) },
      expected: "Missing or malformed")
    try rejects(
      "missing-image",
      edit: { try manager.removeItem(at: $0.appendingPathComponent(Gate.names[0])) },
      expected: "Missing image")
    try rejects(
      "malformed-image",
      edit: { try Data("invalid PNG".utf8).write(to: $0.appendingPathComponent(Gate.names[0])) },
      expected: "Malformed PNG")
    try rejects(
      "incomplete-matrix",
      edit: { directory in
        let url = directory.appendingPathComponent("manifest.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["images"] = Array((json["images"] as! [[String: Any]]).dropLast())
        try JSONSerialization.data(withJSONObject: json).write(to: url)
      }, expected: "Incomplete")
    try rejects(
      "incompatible-settings",
      edit: { directory in
        let url = directory.appendingPathComponent("manifest.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["settings"] = ["scale": "99"]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
      }, expected: "Incompatible runtime")
    try rejects(
      "incompatible-environment",
      edit: { directory in
        let url = directory.appendingPathComponent("manifest.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var provenance = json["provenance"] as! [String: Any]
        provenance["environment"] = ["os": "other"]
        json["provenance"] = provenance
        try JSONSerialization.data(withJSONObject: json).write(to: url)
      }, expected: "Incompatible machine")
    try rejects(
      "one-pixel",
      edit: { directory in
        let name = Gate.names[0]
        let imageURL = directory.appendingPathComponent(name)
        let bitmap = try Gate.bitmap(at: imageURL)
        // An opaque RGB interior pixel round-trips losslessly through PNG.
        let before = try Gate.rgba(bitmap)
        var components = [UInt](repeating: 0, count: bitmap.samplesPerPixel)
        bitmap.getPixel(&components, atX: 100, y: 100)
        let maximum = UInt((1 << bitmap.bitsPerSample) - 1)
        components[0] = components[0] > maximum / 2 ? 0 : maximum
        bitmap.setPixel(&components, atX: 100, y: 100)
        try bitmap.representation(using: .png, properties: [:])!.write(to: imageURL)
        let modified = try Gate.bitmap(at: imageURL)
        let after = try Gate.rgba(modified)
        let count = stride(from: 0, to: before.count, by: 4).filter {
          before[$0..<$0 + 4] != after[$0..<$0 + 4]
        }.count
        try Gate.require(
          count == 1, "Mutation must change exactly one decoded pixel; changed \(count)")
        let url = directory.appendingPathComponent("manifest.json")
        let manifest = try Gate.read(Gate.Manifest.self, from: url)
        let images = try manifest.images.map { item in
          item.name == name ? try Gate.describe(modified, name: name) : item
        }
        try Gate.write(
          Gate.Manifest(
            schemaVersion: manifest.schemaVersion, kind: manifest.kind,
            recordedAt: manifest.recordedAt, provenance: manifest.provenance,
            settings: manifest.settings, images: images), to: url)
      }, expected: "1 changed pixels")
    // Save the last comparison (one pixel) independently of the normal candidate report.
    try manager.copyItem(
      at: candidate.appendingPathComponent("comparison.json"),
      to: output.appendingPathComponent("one-pixel-comparison.json"))
    _ = try Gate.compareRequired(reference: reference, candidate: candidate)
    try Gate.write(outcomes, to: output.appendingPathComponent("negative-controls.json"))
  }

  static func main() {
    do {
      let args = Array(CommandLine.arguments.dropFirst())
      try Gate.require(args.count >= 2, usage)
      let root = URL(fileURLWithPath: args[0], isDirectory: true)
      func url(_ index: Int) -> URL {
        URL(fileURLWithPath: args[index], relativeTo: root).standardizedFileURL
      }
      switch args[1] {
      case "build-capture-app":
        try Gate.require(args.count == 2, usage)
        print(
          try buildCaptureApp(
            root: root, log: root.appendingPathComponent("build/production-capture/build.log")
          ).path)
      case "capture-original":
        try Gate.require(args.count == 4, usage)
        try capture(
          mode: args[1], reference: nil, output: url(2), root: root, originalRevision: args[3])
      case "verify-required":
        try Gate.require(args.count == 4, usage)
        try capture(
          mode: args[1], reference: url(2), output: url(3), root: root, originalRevision: nil)
      case "verify-files-required":
        try Gate.require(args.count == 4, usage)
        _ = try Gate.compareRequired(reference: url(2), candidate: url(3))
      case "negative-controls":
        try Gate.require(args.count == 5, usage)
        try negativeControls(reference: url(2), candidate: url(3), output: url(4))
      default: throw Gate.Failure(message: usage)
      }
    } catch {
      FileHandle.standardError.write(
        Data("PRODUCTION_PARITY FAIL: \(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }

  static let usage = """
    Usage: script/production_visual_parity.sh capture-original NEW_REFERENCE ORIGINAL_REVISION
           script/production_visual_parity.sh verify-required REFERENCE NEW_CANDIDATE
           script/production_visual_parity.sh verify-files-required REFERENCE CANDIDATE
           script/production_visual_parity.sh negative-controls REFERENCE CANDIDATE NEW_EVIDENCE
    Recording refuses overwrite and requires HEAD/production files at ORIGINAL_REVISION.
    Required verification never creates, updates, or substitutes original references.
    """
}

extension Optional {
  fileprivate func unwrap(_ message: String) throws -> Wrapped {
    guard let value = self else { throw ProductionVisualReference.Failure(message: message) }
    return value
  }
}
