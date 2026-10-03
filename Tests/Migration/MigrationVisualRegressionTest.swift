//
//  MigrationVisualRegressionTest.swift
//  Latest Tests
//
//  Created by ertyoii on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-01.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import ScreenCaptureKit
import SwiftUI
import WebKit
import XCTest

@testable import Latest

@MainActor
func captureWindowBitmap(_ window: NSWindow) async throws -> NSBitmapImageRep {
  let shareable = try await SCShareableContent.currentProcess
  let capturedWindow = try XCTUnwrap(shareable.windows.first { $0.windowID == window.windowNumber })
  let configuration = SCStreamConfiguration()
  configuration.width = Int(window.frame.width * 2)
  configuration.height = Int(window.frame.height * 2)
  configuration.showsCursor = false
  configuration.scalesToFit = true
  let image = try await SCScreenshotManager.captureImage(
    contentFilter: SCContentFilter(desktopIndependentWindow: capturedWindow),
    configuration: configuration)
  return NSBitmapImageRep(cgImage: image)
}

final class MigrationVisualRegressionTest: XCTestCase {
  func testSidebarIndicatorPathsMatchOriginalRasterAtBackingScales() throws {
    // Independently rasterize the shipping Bezier geometry and the replacement
    // paths. This catches curve/precision changes even between animation frames.
    func raster(_ path: CGPath, scale: CGFloat, fill: Bool = false) throws -> Data {
      let pixels = Int(24 * scale)
      let context = try XCTUnwrap(
        CGContext(
          data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
          bytesPerRow: pixels * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.scaleBy(x: scale, y: scale)
      let tint = CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
      context.setStrokeColor(tint)
      context.setFillColor(tint)
      context.setLineWidth(2.5)
      context.setLineCap(.round)
      context.addPath(path)
      if fill { context.fillPath() } else { context.strokePath() }
      return Data(bytes: try XCTUnwrap(context.data), count: pixels * pixels * 4)
    }

    let center = CGPoint(x: 12, y: 12)
    let radius = 24.0 * 0.4
    for scale: CGFloat in [1, 2, 3] {
      let minimum = floor((12 - radius) * scale) / scale
      let maximum = ceil((12 + radius) * scale) / scale
      let rect = CGRect(
        x: minimum, y: minimum, width: maximum - minimum, height: maximum - minimum)
      XCTAssertEqual(
        try raster(NSBezierPath(ovalIn: rect).cgPath, scale: scale),
        try raster(SidebarIndicatorPaths.ring(in: rect).cgPath, scale: scale))
      for offset in [-2.0, 2.0] {
        let rect = CGRect(x: 12 + offset - 1, y: 8, width: 2, height: 8)
        XCTAssertEqual(
          try raster(
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).cgPath,
            scale: scale, fill: true),
          try raster(
            SidebarIndicatorPaths.pauseMark(at: CGPoint(x: 12 + offset, y: 12)).cgPath,
            scale: scale, fill: true))
      }
      // Rotation/segment boundaries and diagonal starts exercise the distinct
      // curve cases. Every integer degree repeated the same construction.
      let angles: [Double] = [
        -90, -89, -46, -45, -44, -1, 0, 1, 44, 45, 46, 89, 90, 91,
        179, 180, 181, 269, 270, 271, 359,
      ]
      for angle in angles {
        for sweep in [0.01, 0.5, 1, 9.6, 45, 90, 151.2, 180, 270, 359.9, 360] {
          let reference = NSBezierPath()
          reference.appendArc(
            withCenter: center, radius: radius, startAngle: angle, endAngle: angle + sweep)
          let candidate = SidebarIndicatorPaths.arc(
            center: center, radii: CGSize(width: radius, height: radius),
            angle: angle, sweep: sweep)
          XCTAssertEqual(
            try raster(reference.cgPath, scale: scale),
            try raster(candidate.cgPath, scale: scale),
            "scale=\(scale) angle=\(angle) sweep=\(sweep)")
        }
      }
    }
  }

  @MainActor
  func testProductionSidebarUsesMeasuredOriginalTableGeometryAndRealIcons() async throws {
    try requireUITests()
    let environment = AppEnvironment.localUATFixture(
      settings: try isolatedAppListSettings(for: self))
    let viewModel = environment.updatesListViewModel
    let window = try await makeLatestTestWindow(environment: environment, testCase: self)
    let hostingView = try XCTUnwrap(window.contentView)
    defer { window.close() }
    window.layoutIfNeeded()
    hostingView.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))

    let icon: NSRect
    let accessibilityLabel: String
    if let tableView = hostingView.firstDescendant(of: SwiftUIUpdateTableView.self) {
      XCTAssertEqual(tableView.rowHeight, 60)
      XCTAssertEqual(tableView.intercellSpacing, .zero)
      XCTAssertEqual(tableView.style, .sourceList)
      XCTAssertEqual(tableView.frame.minX, 0, accuracy: 0.5)
      XCTAssertEqual(tableView.numberOfRows, viewModel.snapshot.entries.count)

      let firstSectionRow = try XCTUnwrap(
        viewModel.snapshot.entries.firstIndex(where: {
          if case .section = $0 { return true }
          return false
        })
      )
      let firstAppRow = try XCTUnwrap(viewModel.snapshot.firstIndex(of: viewModel.snapshot.apps[0]))
      XCTAssertEqual(
        tableView.rect(ofRow: firstSectionRow).height, VisualMetrics.sectionHeaderHeight)
      XCTAssertEqual(tableView.rect(ofRow: firstAppRow).height, 60)
      // Snapshot.apps retains input order; Notes sorts below the initial viewport.
      tableView.scrollRowToVisible(firstAppRow)
      try await Task.sleep(for: .milliseconds(100))

      for row in firstAppRow..<min(tableView.numberOfRows, firstAppRow + 5) {
        _ = tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
      }
      tableView.layoutSubtreeIfNeeded()
      let cell = try XCTUnwrap(
        tableView.view(atColumn: 0, row: firstAppRow, makeIfNecessary: false))
      cell.layoutSubtreeIfNeeded()
      accessibilityLabel = try XCTUnwrap(cell.accessibilityLabel())
      let row = tableView.convert(tableView.rect(ofRow: firstAppRow), to: nil)
      icon = NSRect(x: row.minX + 16, y: row.midY - 25, width: 50, height: 50)
    } else {
      let sidebar = try SidebarInputFixture(window: window, model: viewModel)
      let app = viewModel.snapshot.apps[0]
      let rowIndex = try XCTUnwrap(viewModel.snapshot.firstIndex(of: app))
      sidebar.scroll(to: max(0, sidebar.rowRect(rowIndex).minY - 37))
      try await Task.sleep(for: .milliseconds(100))
      // SwiftUI builds virtual accessibility children only after inspection is
      // enabled. This is the same application attribute an AX client requests.
      NSApp.accessibilitySetValue(true, forAttribute: .init(rawValue: "AXEnhancedUserInterface"))
      let elements = sidebar.accessibilityElements()
      let row = try XCTUnwrap(
        elements.first {
          $0.accessibilityIdentifier() == "updates.app.\(app.identifier)"
            && $0.accessibilityFrame().intersects(window.frame)
        })
      XCTAssertEqual(row.accessibilityFrame().height, 60, accuracy: 0.5)
      accessibilityLabel = try XCTUnwrap(row.accessibilityLabel())
      let rect = window.convertFromScreen(row.accessibilityFrame())
      XCTAssertEqual(rect.minX, 0, accuracy: 0.5)
      icon = NSRect(x: rect.minX + 16, y: rect.maxY - 55, width: 50, height: 50)
      let paintedRows = elements.filter {
        $0.accessibilityIdentifier()?.hasPrefix("updates.app.") == true
          && $0.accessibilityFrame().intersects(window.frame)
      }.sorted { $0.accessibilityFrame().minY > $1.accessibilityFrame().minY }
      XCTAssertGreaterThan(paintedRows.count, 5)
      for (first, second) in zip(paintedRows, paintedRows.dropFirst()) {
        XCTAssertEqual(first.accessibilityFrame().height, 60, accuracy: 0.5)
        XCTAssertEqual(
          first.accessibilityFrame().minY - second.accessibilityFrame().minY, 60, accuracy: 0.5)
      }
    }
    let app = viewModel.snapshot.apps[0]
    let versions = try XCTUnwrap(app.localizedVersionInformation)
    XCTAssertTrue(accessibilityLabel.contains(app.name))
    XCTAssertTrue(accessibilityLabel.contains(versions.rawCurrent))
    XCTAssertTrue(accessibilityLabel.contains(try XCTUnwrap(versions.rawNew)))
    XCTAssertTrue(accessibilityLabel.contains(app.source.supportState.label))
    XCTAssertTrue(accessibilityLabel.contains(NSLocalizedString("UpdateAction", comment: "")))
    let rendered = try await captureWindowBitmap(window)
    let pixels = NSRect(
      x: icon.minX * 2, y: (window.frame.height - icon.maxY) * 2,
      width: icon.width * 2, height: icon.height * 2)
    let bounds = NSRect(x: 0, y: 0, width: rendered.pixelsWide, height: rendered.pixelsHigh)
    XCTAssertTrue(bounds.contains(pixels), "Icon crop \(pixels) must fit capture \(bounds)")
    guard bounds.contains(pixels) else { return }
    var goldenIconPixels = 0
    for y in Int((window.frame.height - icon.maxY) * 2)..<Int((window.frame.height - icon.minY) * 2)
    {
      for x in Int(icon.minX * 2)..<Int(icon.maxX * 2) {
        let color = try XCTUnwrap(rendered.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        if color.redComponent - color.blueComponent > 0.15,
          color.greenComponent - color.blueComponent > 0.1
        {
          goldenIconPixels += 1
        }
      }
    }
    XCTAssertGreaterThan(
      goldenIconPixels, 100, "The Notes fixture must paint its real yellow icon on the first frame")
  }

  @MainActor
  func testMigrationGalleryRenderedRegions() async throws {
    try requireUITests()
    guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 else {
      throw XCTSkip("Visual baselines are scoped to the macOS 26 renderer.")
    }

    for scenario in MigrationGalleryScenario.regressionCases {
      // Keep capture outside XCTContext activities: Xcode 26.6 on the hosted
      // runner can fail activity teardown with InvalidTransition (idle ->
      // failed(deinit)). Assertions and attachments already name the scenario.
      let rendered = try await MigrationGalleryRenderer.render(scenario)
      try MigrationGalleryRenderer.assertMatchesBaseline(
        rendered, scenario: scenario, testCase: self)
    }
  }
}

extension NSView {
  fileprivate func firstDescendant<ViewType: NSView>(of type: ViewType.Type) -> ViewType? {
    if let match = self as? ViewType { return match }
    return subviews.lazy.compactMap { $0.firstDescendant(of: type) }.first
  }

}

@MainActor
private enum MigrationGalleryRenderer {
  /// Recording writes candidates to /tmp for review; it never changes the
  /// checked-in reference images or skips their comparison.
  private static let candidateOutputDirectory: URL? = {
    guard
      ProcessInfo.processInfo.environment["LATEST_RECORD_VISUAL_BASELINES"] == "1"
        || FileManager.default.fileExists(atPath: "/tmp/latest-record-visual-baselines")
    else {
      return nil
    }
    return URL(fileURLWithPath: "/tmp/latest-visual-candidates", isDirectory: true)
  }()
  private static let diagnosticOutputDirectory: URL? = {
    if let path = ProcessInfo.processInfo.environment["LATEST_VISUAL_OUTPUT_DIRECTORY"] {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    let fallbackPath = "/tmp/latest-visual-output"
    guard FileManager.default.fileExists(atPath: fallbackPath) else { return nil }
    return URL(fileURLWithPath: fallbackPath, isDirectory: true)
  }()
  private static let baselineDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("VisualBaselines", isDirectory: true)
    .appendingPathComponent("macos-26", isDirectory: true)

  static func render(_ scenario: MigrationGalleryScenario) async throws -> NSBitmapImageRep {
    let rootView = MigrationGalleryView(scenario: scenario)
    let hostingView = NSHostingView(rootView: rootView)
    hostingView.frame = CGRect(origin: .zero, size: scenario.size)

    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: scenario.size),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(
      named: scenario.colorScheme == .dark ? .darkAqua : .aqua
    )
    window.contentView = hostingView
    defer { window.close() }
    window.layoutIfNeeded()
    hostingView.layoutSubtreeIfNeeded()
    if case .detail(.releaseNotes) = scenario.surface {
      var ready = false
      for _ in 0..<200 {
        if let web = hostingView.firstDescendant(of: WKWebView.self), !web.isLoading,
          let body = try? await web.evaluateJavaScript("document.body.innerText") as? String,
          body.contains("Improvements to Cursor")
        {
          _ = try await web.takeSnapshot(configuration: nil)
          ready = true
          break
        }
        try await Task.sleep(for: .milliseconds(50))
      }
      guard ready else { throw VisualRegressionError.didNotSettle(scenario.id + " WebKit") }
    }
    // Suspend the main actor so SwiftUI .task work (including the header icon)
    // can run. Pumping RunLoop from a synchronous test does not provide that
    // scheduling boundary. Require consecutive settled frames, not one timed
    // screenshot, and fail rather than silently recording an unsettled view.
    var previousPixels: [UInt8]?
    var stableFrames = 0
    for _ in 0..<100 {
      try await Task.sleep(for: .milliseconds(50))
      window.layoutIfNeeded()
      hostingView.layoutSubtreeIfNeeded()
      let bitmap = try capture(hostingView, size: scenario.size)
      let pixels = try rgbaBytes(from: bitmap)
      stableFrames = pixels == previousPixels ? stableFrames + 1 : 0
      if stableFrames >= 5 { return bitmap }
      previousPixels = pixels
    }
    throw VisualRegressionError.didNotSettle(scenario.id)
  }

  private static func capture(_ hostingView: NSView, size: CGSize) throws -> NSBitmapImageRep {

    // References are Retina captures. Hosted runners have a 1x display,
    // so allocate the reference scale independently of the attached screen.
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * 2),
        pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else {
      throw VisualRegressionError.couldNotCreateBitmap
    }
    bitmap.size = size
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    return bitmap
  }

  static func assertMatchesBaseline(
    _ rendered: NSBitmapImageRep,
    scenario: MigrationGalleryScenario,
    testCase: XCTestCase
  ) throws {
    let baselineURL = baselineDirectory.appendingPathComponent(baselineFilename(for: scenario))
    guard let png = rendered.representation(using: .png, properties: [:]) else {
      throw VisualRegressionError.couldNotEncodePNG
    }
    if let diagnosticOutputDirectory {
      try FileManager.default.createDirectory(
        at: diagnosticOutputDirectory,
        withIntermediateDirectories: true
      )
      try png.write(
        to: diagnosticOutputDirectory.appendingPathComponent("\(scenario.id)-actual.png"),
        options: .atomic
      )
    }

    if let candidateOutputDirectory {
      try FileManager.default.createDirectory(
        at: candidateOutputDirectory,
        withIntermediateDirectories: true
      )
      try png.write(
        to: candidateOutputDirectory.appendingPathComponent("\(scenario.id).png"),
        options: .atomic
      )
    }

    guard let baselineData = try? Data(contentsOf: baselineURL),
      let baseline = NSBitmapImageRep(data: baselineData)
    else {
      XCTFail("Missing checked-in visual reference \(baselineURL.path)")
      return
    }

    let comparison = try compare(
      baseline: baseline,
      actual: rendered,
      regions: comparisonRegions(for: scenario)
    )
    guard !comparison.passed else { return }
    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
    attachment.name = "\(scenario.id)-actual"
    attachment.lifetime = .keepAlways
    testCase.add(attachment)
    XCTFail(
      String(
        format:
          "Visual regression in %@: %.3f%% pixels exceeded tolerance, RMS %.3f (limits %.3f%% / %.3f)",
        scenario.id,
        comparison.changedFraction * 100,
        comparison.rms,
        comparison.changedFractionLimit * 100,
        comparison.rmsLimit
      )
    )
  }

  private static func baselineFilename(for scenario: MigrationGalleryScenario) -> String {
    return "\(scenario.id).png"
  }

  private static func comparisonRegions(for scenario: MigrationGalleryScenario) -> [CGRect] {
    let insetBounds = CGRect(origin: .zero, size: scenario.size).insetBy(dx: 2, dy: 2)
    switch scenario.surface {
    case .detail:
      let leftToRightDetail = MigrationGalleryMetrics.detailFrame(in: scenario.size)
      let detail =
        scenario.layoutDirection == .rightToLeft
        ? CGRect(origin: .zero, size: leftToRightDetail.size)
        : leftToRightDetail
      // Only the real detail surface is covered by these existing references.
      // Sidebar assertions use the production scene above.
      // NSWorkspace owns the generic document icon and can change its shadow
      // pixels independently of Latest. Compare the production-owned metadata
      // and action portion of the header; icon size/placement remains covered
      // by the geometry contract and real app icons by the sidebar references.
      let headerContentStart =
        detail.minX
        + VisualMetrics.detailHeaderHorizontalPadding
        + VisualMetrics.detailIconSize
        + 5
      let header = CGRect(
        x: headerContentStart,
        y: 2,
        width: max(0, detail.maxX - headerContentStart - 2),
        height: MigrationGalleryMetrics.detailHeaderHeight - 2
      )
      let body = CGRect(
        x: detail.minX + 2,
        y: MigrationGalleryMetrics.detailHeaderHeight,
        width: max(0, detail.width - 4),
        height: max(0, detail.height - MigrationGalleryMetrics.detailHeaderHeight - 4)
      )
      return [header, body]
    case .locations, .updateStateShelf, .toolbarStateShelf:
      return [insetBounds]
    }
  }

  private static func compare(
    baseline: NSBitmapImageRep,
    actual: NSBitmapImageRep,
    regions: [CGRect]
  ) throws -> VisualComparison {
    guard baseline.pixelsWide == actual.pixelsWide,
      baseline.pixelsHigh == actual.pixelsHigh
    else {
      throw VisualRegressionError.dimensionMismatch(
        expected: CGSize(width: baseline.pixelsWide, height: baseline.pixelsHigh),
        actual: CGSize(width: actual.pixelsWide, height: actual.pixelsHigh)
      )
    }

    let expected = try rgbaBytes(from: baseline)
    let observed = try rgbaBytes(from: actual)
    let scaleX = CGFloat(actual.pixelsWide) / actual.size.width
    let scaleY = CGFloat(actual.pixelsHigh) / actual.size.height
    let channelTolerance = 12
    var comparedPixels = 0
    var changedPixels = 0
    var squaredError = 0.0

    for region in regions {
      let pixelRegion = CGRect(
        x: region.minX * scaleX,
        y: region.minY * scaleY,
        width: region.width * scaleX,
        height: region.height * scaleY
      ).integral
      let minX = max(0, Int(pixelRegion.minX))
      let maxX = min(actual.pixelsWide, Int(pixelRegion.maxX))
      let minY = max(0, Int(pixelRegion.minY))
      let maxY = min(actual.pixelsHigh, Int(pixelRegion.maxY))

      for y in minY..<maxY {
        for x in minX..<maxX {
          let offset = ((y * actual.pixelsWide) + x) * 4
          var pixelChanged = false
          for channel in 0..<3 {
            let delta = abs(Int(expected[offset + channel]) - Int(observed[offset + channel]))
            pixelChanged = pixelChanged || delta > channelTolerance
            squaredError += Double(delta * delta)
          }
          comparedPixels += 1
          if pixelChanged {
            changedPixels += 1
          }
        }
      }
    }

    let changedFraction = comparedPixels == 0 ? 0 : Double(changedPixels) / Double(comparedPixels)
    let rms = comparedPixels == 0 ? 0 : sqrt(squaredError / Double(comparedPixels * 3))
    let changedFractionLimit = 0.0025
    let rmsLimit = 1.5
    return VisualComparison(
      passed: changedFraction <= changedFractionLimit && rms <= rmsLimit,
      changedFraction: changedFraction,
      rms: rms,
      changedFractionLimit: changedFractionLimit,
      rmsLimit: rmsLimit
    )
  }

  private static func rgbaBytes(from bitmap: NSBitmapImageRep) throws -> [UInt8] {
    guard let image = bitmap.cgImage else {
      throw VisualRegressionError.couldNotReadPixels
    }
    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard
      let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw VisualRegressionError.couldNotReadPixels
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
  }
}

private struct VisualComparison {
  let passed: Bool
  let changedFraction: Double
  let rms: Double
  let changedFractionLimit: Double
  let rmsLimit: Double
}

private enum VisualRegressionError: LocalizedError {
  case didNotSettle(String)
  case couldNotCreateBitmap
  case couldNotEncodePNG
  case couldNotReadPixels
  case dimensionMismatch(expected: CGSize, actual: CGSize)

  var errorDescription: String? {
    switch self {
    case .didNotSettle(let scenario):
      "Visual fixture did not settle: \(scenario)"
    case .couldNotCreateBitmap:
      "Could not create a bitmap for the migration gallery."
    case .couldNotEncodePNG:
      "Could not encode the migration gallery as PNG."
    case .couldNotReadPixels:
      "Could not normalize migration gallery pixels to RGBA."
    case .dimensionMismatch(let expected, let actual):
      "Visual dimensions differ: expected \(expected), actual \(actual)."
    }
  }
}

/// Captures the shipping scene and the sidebar renderer selected by the OS. A same-machine reference directory enables
/// strict full-frame comparison without accepting any changed RGBA pixels.
final class ProductionVisualParityTest: XCTestCase {
  @MainActor
  func testToolbarScanBecomesVisibleLinearProgressAndClearsOnCompletion() async throws {
    try requireUITests()
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let set =
      (try? String(
        contentsOf: root.appendingPathComponent("build/sidebar-control-capture-set"),
        encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "current"
    let output = root.appendingPathComponent("build/toolbar-control-\(set)")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for dark in [false, true] {
      let environment = AppEnvironment.localUATFixture(
        settings: try isolatedAppListSettings(for: self))
      let service = environment.updateCheckingService
      let coordinator = UpdateCheckCoordinator()
      let window = try await makeLatestTestWindow(
        environment: environment, dark: dark, testCase: self)
      defer { window.close() }
      let sidebar = try SidebarInputFixture(window: window, model: environment.updatesListViewModel)
      try await sidebar.activate()
      let web = try XCTUnwrap(window.contentView?.firstDescendant(of: WKWebView.self))
      try await waitForWebPaint(web)
      var captures: [String: NSBitmapImageRep] = [:]
      for state in ["idle", "scanning", "zero", "quarter", "three-quarters", "finished"] {
        switch state {
        case "idle": break
        case "scanning": service.updateCheckerDidStartScanningForApps(coordinator)
        case "zero":
          service.updateChecker(coordinator, didStartCheckingApps: 4, generation: 1)
        case "quarter":
          service.updateChecker(coordinator, didCheckApp: LocalUATFixture.apps[0])
        case "three-quarters":
          for app in LocalUATFixture.apps[1...2] {
            service.updateChecker(coordinator, didCheckApp: app)
          }
        default: service.updateCheckerDidFinishCheckingForUpdates(coordinator, generation: 1)
        }
        try await Task.sleep(for: .milliseconds(350))
        window.layoutIfNeeded()
        let bitmap = try await settledWindowBitmap(window)
        let toolbar = try XCTUnwrap(
          bitmap.cgImage?.cropping(
            to: CGRect(
              x: bitmap.pixelsWide - 440, y: 0, width: 440, height: 110)))
        let crop = NSBitmapImageRep(cgImage: toolbar)
        let name = "\(dark ? "dark" : "light")-\(state)"
        try XCTUnwrap(crop.representation(using: .png, properties: [:])).write(
          to: output.appendingPathComponent("\(name).png"))
        captures[state] = crop
      }
      func difference(_ first: String, _ second: String, x: Int, y: Int) throws -> CGFloat {
        let a = try XCTUnwrap(captures[first]?.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        let b = try XCTUnwrap(captures[second]?.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        return max(
          abs(a.redComponent - b.redComponent),
          abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent))
      }
      // Native toolbars use a neutral fill. Measure actual changed columns,
      // excluding the refresh button, rather than requiring an accent color.
      var changedColumns = Set<Int>()
      var scanPixels = 0
      var scanTransitionPixels = 0
      var completionPixels = 0
      for y in 0..<110 {
        for x in 0..<300 {
          if try difference("quarter", "three-quarters", x: x, y: y) > 0.04 {
            changedColumns.insert(x)
          }
          if try difference("idle", "scanning", x: x, y: y) > 0.04 { scanPixels += 1 }
          if try difference("scanning", "zero", x: x, y: y) > 0.04 {
            scanTransitionPixels += 1
          }
          if try difference("idle", "finished", x: x, y: y) > 0.04 { completionPixels += 1 }
        }
      }
      XCTAssertGreaterThan(
        changedColumns.count, 40, "The horizontal bar must advance with checked apps")
      XCTAssertGreaterThan(scanPixels, 20, "Scanning must paint the empty linear progress track")
      XCTAssertEqual(
        scanTransitionPixels, 0,
        "Learning the app count must preserve the empty bar without a spinner transition")
      XCTAssertEqual(completionPixels, 0, "Completion must remove the progress indicator")
      XCTAssertLessThan(
        try difference("quarter", "finished", x: 240, y: 20), 0.02,
        "Passive progress must not expand the refresh button's glass background")
    }
  }

  @MainActor
  func testDetailCapsulePaintsAndRoutesMouseActions() throws {
    try requireUITests()
    try runApplicationTest { try await self.checkDetailCapsulePaintsAndRoutesMouseActions() }
  }

  @MainActor
  private func checkDetailCapsulePaintsAndRoutesMouseActions() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let set =
      (try? String(
        contentsOf: root.appendingPathComponent("build/detail-capsule-capture-set"),
        encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "current"
    let output = root.appendingPathComponent("build/detail-capsule-\(set)")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let app = LocalUATFixture.apps[0]
    let states: [(String, UpdateActionPresentation)] = [
      ("update", .update), ("open", .open), ("error", .failed("Fixture failure")),
    ]
    for dark in [false, true] {
      for (name, presentation) in states {
        var actions = 0
        let host = NSHostingView(
          rootView:
            UpdateActionSurface(
              app: app, presentation: presentation, performAction: { actions += 1 }
            )
            .frame(width: 160, height: 80)
            .background(Color(nsColor: .textBackgroundColor)))
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 160, height: 80),
          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let filename = "\(dark ? "dark" : "light")-\(name)"
        let bitmap = try await captureWindowBitmap(window)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
          to: output.appendingPathComponent("\(filename).png"))
        // Independently inspect the original 59 x 24pt capsule and its blue ink.
        var bluePixels = 0
        for y in 56..<104 {
          for x in 101..<219 {
            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            if color.blueComponent - color.redComponent > 0.3 { bluePixels += 1 }
          }
        }
        XCTAssertGreaterThan(bluePixels, 25, filename)
        let center = try XCTUnwrap(bitmap.colorAt(x: 160, y: 58)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(center.redComponent, 0.9, filename)
        XCTAssertLessThan(center.redComponent, 0.98, filename)
        XCTAssertGreaterThan(center.blueComponent - center.redComponent, 0.01, filename)
        let down = try XCTUnwrap(
          NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 80, y: 40), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(
          NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: down.locationInWindow, modifierFlags: [], timestamp: down.timestamp + 0.05,
            windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1,
            pressure: 0))
        // AppKit tracking runs outside this async task so we can capture the
        // genuine pressed pixels before queuing the matching release.
        let pressed = try await { @MainActor in
          NSApp.postEvent(down, atStart: false)
          defer { NSApp.postEvent(up, atStart: false) }
          var pressed: NSBitmapImageRep?
          for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            let bitmap = try await captureWindowBitmap(window)
            let fill = try XCTUnwrap(bitmap.colorAt(x: 160, y: 58)?.usingColorSpace(.sRGB))
            if fill.redComponent < center.redComponent - 0.1 {
              pressed = bitmap
              break
            }
          }
          XCTAssertEqual(actions, 0, "The action must wait for mouse-up")
          return try XCTUnwrap(pressed, "\(filename) must paint its pressed fill before release")
        }()
        try XCTUnwrap(pressed.representation(using: .png, properties: [:])).write(
          to: output.appendingPathComponent("\(filename)-pressed.png"))
        let pressedFill = try XCTUnwrap(pressed.colorAt(x: 160, y: 58)?.usingColorSpace(.sRGB))
        XCTAssertLessThan(pressedFill.redComponent, center.redComponent - 0.1, filename)
        for _ in 0..<40 {
          if actions == 1 { break }
          try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(actions, 1, "\(filename) must invoke the displayed action exactly once")
      }
    }
  }

  @MainActor
  func testSidebarProgressActionCancelsOnlyItsInjectedOperation() async throws {
    try requireUITests()
    let queue = UpdateQueue()
    queue.isSuspended = true
    defer {
      queue.cancelAllOperations()
      queue.isSuspended = false
    }
    let service = AppUpdateService(queue: queue)
    let apps = Array(LocalUATFixture.apps.prefix(2))
    let operations = apps.map {
      UpdateOperation(bundleIdentifier: $0.bundleIdentifier, appIdentifier: $0.identifier)
    }
    for operation in operations { queue.addOperation(operation) }
    operations[0].progressState = .downloading(loadedSize: 25, totalSize: 100)
    let fixture = try await SidebarInputFixture.make(
      apps: apps, updating: service, testCase: self)
    defer { fixture.window.close() }
    try await fixture.clickProgress(for: apps[0])
    XCTAssertTrue(operations[0].isCancelled)
    XCTAssertFalse(operations[1].isCancelled, "Cancel must target the displayed app only")
  }

  @MainActor
  func testSidebarUpdateControlStates() throws {
    try requireUITests()
    try runApplicationTest { try await self.checkSidebarUpdateControlStates() }
  }

  @MainActor
  private func checkSidebarUpdateControlStates() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let marker = root.appendingPathComponent("build/sidebar-control-capture-set")
    let set =
      (try? String(contentsOf: marker, encoding: .utf8))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "current"
    let output = root.appendingPathComponent("build/sidebar-control-\(set)")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let apps = Array(LocalUATFixture.apps.prefix(2))
    let app = apps[0]
    let queue = UpdateQueue()
    queue.isSuspended = true
    let operation = UpdateOperation(
      bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
    queue.addOperation(operation)
    let service = AppUpdateService(queue: queue)
    defer {
      queue.cancelAllOperations()
      queue.isSuspended = false
    }
    let states: [(String, UpdateProgressState)] = [
      ("idle", .none), ("waiting", .pending),
      ("download", .downloading(loadedSize: 25_000_000, totalSize: 100_000_000)),
      ("extract", .extracting(progress: 0.5)),
      ("error", .error(LatestError.updateInfoUnavailable)),
    ]
    for dark in [false, true] {
      for selected in [false, true] {
        let fixture = try await SidebarInputFixture.make(
          apps: apps, selected: selected ? app : apps[1], dark: dark,
          updating: service, testCase: self)
        defer { fixture.window.close() }
        if selected {
          try await fixture.activate()
          try fixture.click(row: XCTUnwrap(fixture.model.snapshot.firstIndex(of: app)))
        }
        for (name, state) in states {
          operation.progressState = state
          try await Task.sleep(for: .milliseconds(250))
          fixture.window.layoutIfNeeded()
          let bitmap = try await fixture.captureRow(for: app)
          let filename = "\(dark ? "dark" : "light")-\(selected ? "selected" : "plain")-\(name).png"
          try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: output.appendingPathComponent(filename))
          // The status dot returns after a failure; an active operation instead
          // paints its indicator below the date, with a visible gap.
          var greenStatusPixels = 0
          var indicatorPixels = 0
          var firstIndicatorY = bitmap.pixelsHigh
          for y in 40..<110 {
            for x in 502..<555 {
              let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
              if color.greenComponent - max(color.redComponent, color.blueComponent) > 0.2 {
                greenStatusPixels += 1
              }
              if selected
                ? color.redComponent > 0.9 : color.blueComponent - color.redComponent > 0.2
              {
                indicatorPixels += 1
                firstIndicatorY = min(firstIndicatorY, y)
              }
            }
          }
          if name == "idle" || name == "error" {
            XCTAssertGreaterThan(greenStatusPixels, 20, filename)
          } else {
            XCTAssertEqual(greenStatusPixels, 0, filename)
            if name != "waiting" || selected {
              XCTAssertGreaterThan(indicatorPixels, 20, filename)
              if selected {
                XCTAssertGreaterThanOrEqual(
                  firstIndicatorY, 50,
                  "The indicator must leave space below the date: \(filename)")
              }
            }
          }
        }
      }
    }
  }

  @MainActor
  func testProductionWindowStates() async throws {
    try requireUITests()
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let output = root.appendingPathComponent(
      "build/production-visuals/main-window-scene", isDirectory: true)
    let reference = root.appendingPathComponent(
      "build/production-visual-reference/main-window-scene", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let comparesReference = FileManager.default.fileExists(atPath: reference.path)
    for dark in [false, true] {
      for state in ["initial", "selection", "search", "downloading", "pinned"] {
        let suite = "ProductionVisualParity.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppListSettings(userDefaults: defaults)
        let apps = LocalUATFixture.apps
        let model = UpdatesListViewModel(
          snapshot: AppListSnapshot(withApps: apps, filterQuery: nil, settings: settings),
          settings: settings
        )
        model.select(apps[0])
        if state == "selection" { model.select(apps[3]) }
        if state == "search" { model.setSearchQuery("Notes") }
        var operation: UpdateOperation?
        if state == "downloading" {
          let started = expectation(description: "Visual fixture operation started")
          let updating = ProductionCaptureOperation(app: apps[0], started: started)
          UpdateQueue.shared.addOperation(updating)
          await fulfillment(of: [started], timeout: 2)
          updating.progressState = .downloading(loadedSize: 25_000_000, totalSize: 100_000_000)
          operation = updating
        }
        defer {
          operation?.finish()
        }
        let environment = AppEnvironment(settings: settings, updatesListViewModel: model)
        let window = try await makeLatestTestWindow(
          environment: environment, dark: dark, testCase: self)
        // Native materials sample the window's backdrop. Keep position and
        // key-window state explicit so earlier input tests cannot change the reference.
        let screen = try XCTUnwrap(window.screen)
        window.setFrameOrigin(
          NSPoint(
            x: screen.visibleFrame.minX + 80,
            y: screen.visibleFrame.maxY - window.frame.height - 80))
        NSApp.deactivate()
        for _ in 0..<100 where window.isKeyWindow {
          try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(window.isKeyWindow)
        let view = try XCTUnwrap(window.contentView)
        defer { window.close() }
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let web = try XCTUnwrap(view.firstDescendant(of: WKWebView.self))
        try await waitForWebPaint(web)
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        let sidebar = try SidebarInputFixture(window: window, model: model)
        let expectedApp = state == "selection" ? apps[3] : apps[0]
        XCTAssertEqual(sidebar.selectedRow, model.snapshot.firstIndex(of: expectedApp))
        let body = try await web.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertTrue(body?.contains("Offline acceptance fixture for \(expectedApp.name).") == true)
        if state == "search" {
          XCTAssertEqual(model.snapshot.sections.flatMap(\.apps).map(\.name), ["Notes"])
        }
        if state == "pinned" {
          let scroll = sidebar.scroll
          sidebar.scroll(to: 240)
          try await Task.sleep(for: .milliseconds(100))
          XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
        }
        // One WindowServer capture covers native chrome, material-composited
        // sidebar, detail and WebKit together. View-cache captures omitted the
        // sidebar and required a redundant second table-only image.
        let bitmap = try await settledWindowBitmap(window)
        try record(
          bitmap, name: "window-\(state)-\(dark ? "dark" : "light").png",
          output: output, reference: reference, comparesReference: comparesReference)
      }
    }
  }

  @MainActor
  private func settledWindowBitmap(_ window: NSWindow) async throws -> NSBitmapImageRep {
    var previous: Data?
    var stableFrames = 0
    for _ in 0..<100 {
      let bitmap = try await captureWindowBitmap(window)
      let pixels = try rgba(bitmap)
      stableFrames = pixels == previous ? stableFrames + 1 : 0
      if stableFrames >= 5 { return bitmap }
      previous = pixels
      try await Task.sleep(for: .milliseconds(50))
    }
    throw VisualRegressionError.didNotSettle("production window")
  }

  @MainActor
  func testReleaseNotesRenderedPixels() async throws {
    try requireUITests()
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let output = root.appendingPathComponent("build/production-visuals", isDirectory: true)
    let reference = root.appendingPathComponent(
      "build/production-visual-reference", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let text = NSMutableAttributedString(
      string:
        "Release 1.2 — Unicode café 中文\nBold and italic with code.\nhttps://example.com/notes\n"
        + Array(
          repeating: "A long release-note line that wraps naturally across the viewport.", count: 35
        ).joined(separator: "\n"))
    let string = text.string as NSString
    text.addAttribute(
      .font, value: NSFont.boldSystemFont(ofSize: 13), range: string.range(of: "Bold"))
    text.addAttribute(
      .font,
      value: NSFontManager.shared.convert(
        NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask),
      range: string.range(of: "italic"))
    text.addAttribute(
      .font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
      range: string.range(of: "code"))
    text.addAttribute(
      .link, value: URL(string: "https://example.com/notes")!,
      range: string.range(of: "https://example.com/notes"))
    for dark in [false, true] {
      for width in [460, 680] {
        let host = NSHostingView(
          rootView: ReleaseNotesWebView(text: ReleaseNotesLegacyBridge.content(from: text))
            .environment(\.colorScheme, dark ? .dark : .light))
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: width, height: 360),
          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        // Inspect the rendering engine, not a particular representable or SwiftUI wrapper.
        var renderer: WKWebView?
        for _ in 0..<200 {
          renderer = host.firstDescendant(of: WKWebView.self)
          if let renderer, !renderer.isLoading,
            let body = try? await renderer.evaluateJavaScript("document.body.innerText") as? String,
            body.contains("Release 1.2")
          {
            break
          }
          try await Task.sleep(for: .milliseconds(50))
        }
        let web = try XCTUnwrap(renderer)
        let body = try await web.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertTrue(body?.contains("Release 1.2") == true)
        for scrolled in [false, true] {
          _ = try await web.evaluateJavaScript("window.scrollTo(0, \(scrolled ? 160 : 0))")
          try await Task.sleep(for: .milliseconds(100))
          let image = try await web.takeSnapshot(configuration: nil)
          let bitmap = try XCTUnwrap(
            NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
          try record(
            bitmap,
            name: "web-\(width)-\(dark ? "dark" : "light")-\(scrolled ? "scrolled" : "top").png",
            output: output, reference: reference,
            comparesReference: FileManager.default.fileExists(atPath: reference.path))
        }
      }
    }
  }

  @MainActor
  private func waitForWebPaint(_ web: WKWebView) async throws {
    var ready = false
    for _ in 0..<200 {
      ready =
        (try? await web.evaluateJavaScript(
          "document.readyState === 'complete' && !!document.querySelector('main')?.textContent.length"
        ) as? Bool) == true && !web.isLoading
      if ready { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertTrue(ready, "Release notes must be loaded before comparing pixels")
    // WebKit suspends animation-frame callbacks in an inactive XCTest host.
    // Snapshotting asks the actual renderer to finish painting without relying
    // on application focus or an unbounded JavaScript promise.
    _ = try await web.takeSnapshot(configuration: nil)
    web.displayIfNeeded()
  }

  private func record(
    _ bitmap: NSBitmapImageRep, name: String, output: URL, reference: URL, comparesReference: Bool
  ) throws {
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: output.appendingPathComponent(name), options: .atomic)
    if comparesReference {
      let baseline = try XCTUnwrap(
        NSBitmapImageRep(data: Data(contentsOf: reference.appendingPathComponent(name))))
      XCTAssertEqual(bitmap.pixelsWide, baseline.pixelsWide, name)
      XCTAssertEqual(bitmap.pixelsHigh, baseline.pixelsHigh, name)
      XCTAssertTrue(try rgba(bitmap) == rgba(baseline), "Every pixel must match: \(name)")
    }
  }

  private func rgba(_ bitmap: NSBitmapImageRep) throws -> Data {
    let image = try XCTUnwrap(bitmap.cgImage)
    var data = Data(count: bitmap.pixelsWide * bitmap.pixelsHigh * 4)
    try data.withUnsafeMutableBytes { bytes in
      let context = try XCTUnwrap(
        CGContext(
          data: bytes.baseAddress,
          width: bitmap.pixelsWide, height: bitmap.pixelsHigh, bitsPerComponent: 8,
          bytesPerRow: bitmap.pixelsWide * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(
        image, in: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
    }
    return data
  }
}

private final class ProductionCaptureOperation: UpdateOperation, @unchecked Sendable {
  private let started: XCTestExpectation
  init(app: Latest.App, started: XCTestExpectation) {
    self.started = started
    super.init(bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
  }
  override func execute() {
    super.execute()
    started.fulfill()
  }
}
