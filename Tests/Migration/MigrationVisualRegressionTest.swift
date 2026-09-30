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
  let image = try await SCScreenshotManager.captureImage(
    contentFilter: SCContentFilter(desktopIndependentWindow: capturedWindow),
    configuration: configuration)
  return NSBitmapImageRep(cgImage: image)
}

final class MigrationVisualRegressionTest: XCTestCase {
  @MainActor
  func testMigrationGalleryGeometryContracts() {
    let defaultSize = MigrationGalleryMetrics.defaultWindowSize
    let sidebar = MigrationGalleryMetrics.sidebarFrame(in: defaultSize)
    let detail = MigrationGalleryMetrics.detailFrame(in: defaultSize)

    XCTAssertEqual(defaultSize, CGSize(width: 768, height: 516))
    XCTAssertEqual(sidebar.width, VisualMetrics.sidebarIdealWidth)
    XCTAssertEqual(sidebar.height, defaultSize.height)
    XCTAssertEqual(detail.minX, sidebar.maxX)
    XCTAssertEqual(detail.maxX, defaultSize.width)
    XCTAssertEqual(MigrationGalleryMetrics.detailHeaderHeight, VisualMetrics.detailHeaderHeight)
    XCTAssertEqual(MigrationGalleryMetrics.appRowHeight, VisualMetrics.appRowHeight)
    XCTAssertEqual(MigrationGalleryMetrics.locationsContentSize, CGSize(width: 440, height: 296))
    XCTAssertEqual(MigrationGalleryMetrics.locationsTableSize, CGSize(width: 400, height: 200))
    XCTAssertEqual(
      MigrationGalleryMetrics.sidebarFixtureSize.width, VisualMetrics.sidebarIdealWidth)
  }

  @MainActor
  func testProductionSidebarUsesMeasuredOriginalTableGeometryAndRealIcons() async throws {
    let environment = AppEnvironment.localUATFixture(
      settings: try isolatedAppListSettings(for: self))
    let viewModel = environment.updatesListViewModel
    let hostingView = NSHostingView(
      rootView: UpdatesSidebarView(
        viewModel: viewModel,
        searchFocusController: environment.searchFocusController
      ))
    hostingView.frame = NSRect(
      x: 0,
      y: 0,
      width: VisualMetrics.sidebarIdealWidth,
      height: MigrationGalleryMetrics.sidebarFixtureSize.height
    )
    let window = NSWindow(
      contentRect: hostingView.bounds,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    window.orderFront(nil)
    defer { window.close() }
    window.layoutIfNeeded()
    hostingView.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))

    let tableView = try XCTUnwrap(hostingView.firstDescendant(of: NSTableView.self))
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
    XCTAssertEqual(tableView.rect(ofRow: firstSectionRow).height, VisualMetrics.sectionHeaderHeight)
    XCTAssertEqual(tableView.rect(ofRow: firstAppRow).height, 60)

    for row in firstAppRow..<min(tableView.numberOfRows, firstAppRow + 5) {
      _ = tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
    }
    tableView.layoutSubtreeIfNeeded()
    let cell = try XCTUnwrap(
      tableView.view(atColumn: 0, row: firstAppRow, makeIfNecessary: false))
    cell.layoutSubtreeIfNeeded()
    XCTAssertTrue(cell.accessibilityLabel()?.contains(viewModel.snapshot.apps[0].name) == true)
    let rendered = try await captureWindowBitmap(window)
    let icon = cell.convert(
      NSRect(x: 0, y: cell.bounds.midY - 25, width: 50, height: 50), to: nil)
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

  fileprivate func allDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
    let current = (self as? ViewType).map { [$0] } ?? []
    return current + subviews.flatMap { $0.allDescendants(of: type) }
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
    case .main:
      let leftToRightDetail = MigrationGalleryMetrics.detailFrame(in: scenario.size)
      let detail =
        scenario.layoutDirection == .rightToLeft
        ? CGRect(origin: .zero, size: leftToRightDetail.size)
        : leftToRightDetail
      // The old gallery sidebar baseline was a standalone 65pt synthetic row,
      // while the real pre-migration NSTableView resolves rows to 60pt. Do not
      // make the main-window gate enforce that known-false fixture. The shipping
      // sidebar is covered by the production table geometry/icon test above and
      // by same-state on-screen comparison against the real original app.
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

/// Captures the shipping composition, including its NSTableView sidebar, rather
/// than just the migration gallery. A same-machine reference directory enables
/// strict full-frame comparison without accepting any changed RGBA pixels.
final class ProductionVisualParityTest: XCTestCase {
  @MainActor
  func testDetailCapsulePaintsAndRoutesMouseActions() async throws {
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
        window.sendEvent(down)
        try await Task.sleep(for: .milliseconds(50))
        let pressed = try await captureWindowBitmap(window)
        try XCTUnwrap(pressed.representation(using: .png, properties: [:])).write(
          to: output.appendingPathComponent("\(filename)-pressed.png"))
        let pressedFill = try XCTUnwrap(pressed.colorAt(x: 160, y: 58)?.usingColorSpace(.sRGB))
        XCTAssertLessThan(pressedFill.redComponent, center.redComponent - 0.1, filename)
        window.sendEvent(up)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(actions, 1, "\(filename) must invoke the displayed action exactly once")
      }
    }
  }

  @MainActor
  func testSidebarProgressActionCancelsOnlyItsInjectedOperation() async throws {
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
    let row = UpdateRowHostingCell(frame: NSRect(x: 0, y: 0, width: 308, height: 60))
    let window = NSWindow(
      contentRect: row.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = row
    window.orderFront(nil)
    defer { window.close() }
    row.update(
      app: apps[0], isSelected: false, filterQuery: nil,
      dateFormatter: DateFormatter(), updating: service)
    try await Task.sleep(for: .milliseconds(150))
    row.layoutSubtreeIfNeeded()
    let down = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: NSPoint(x: 264, y: 30), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    let up = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseUp, location: down.locationInWindow, modifierFlags: [],
        timestamp: down.timestamp + 0.05, windowNumber: window.windowNumber,
        context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
    // Queue mouse-up first so a native control's tracking loop can consume it.
    NSApp.postEvent(up, atStart: false)
    window.sendEvent(down)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(operations[0].isCancelled)
    XCTAssertFalse(operations[1].isCancelled, "Cancel must target the displayed app only")
  }

  @MainActor
  func testSidebarUpdateControlStates() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let marker = root.appendingPathComponent("build/sidebar-control-capture-set")
    let set =
      (try? String(contentsOf: marker, encoding: .utf8))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "current"
    let output = root.appendingPathComponent("build/sidebar-control-\(set)")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let app = LocalUATFixture.apps[0]
    let started = expectation(description: "Sidebar update fixture started")
    let operation = ProductionCaptureOperation(app: app, started: started)
    UpdateQueue.shared.addOperation(operation)
    await fulfillment(of: [started], timeout: 2)
    defer { operation.finish() }
    let states: [(String, UpdateProgressState)] = [
      ("idle", .none), ("waiting", .pending),
      ("download", .downloading(loadedSize: 25_000_000, totalSize: 100_000_000)),
      ("extract", .extracting(progress: 0.5)),
      ("error", .error(LatestError.updateInfoUnavailable)),
    ]
    for dark in [false, true] {
      for selected in [false, true] {
        let row = UpdateRowHostingCell(frame: NSRect(x: 0, y: 0, width: 308, height: 60))
        let nativeRow = NSTableRowView(frame: row.bounds)
        nativeRow.backgroundColor = .textBackgroundColor
        nativeRow.addSubview(row)
        let window = NSWindow(
          contentRect: row.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = nativeRow
        window.orderFront(nil)
        defer { window.close() }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        row.update(app: app, isSelected: selected, filterQuery: nil, dateFormatter: formatter)
        nativeRow.isSelected = selected
        nativeRow.isEmphasized = selected
        row.backgroundStyle = selected ? .emphasized : .normal
        for (name, state) in states {
          operation.progressState = state
          try await Task.sleep(for: .milliseconds(300))
          window.layoutIfNeeded()
          row.layoutSubtreeIfNeeded()
          let bitmap = try await captureWindowBitmap(window)
          let filename = "\(dark ? "dark" : "light")-\(selected ? "selected" : "plain")-\(name).png"
          try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: output.appendingPathComponent(filename))
          // The status dot returns after a failure; an active operation instead
          // paints its indicator at the established center (264, 30).
          var greenStatusPixels = 0
          var indicatorPixels = 0
          for y in 35..<83 {
            for x in 502..<555 {
              let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
              if color.greenComponent - max(color.redComponent, color.blueComponent) > 0.2 {
                greenStatusPixels += 1
              }
              if selected
                ? color.redComponent > 0.9 : color.blueComponent - color.redComponent > 0.2
              {
                indicatorPixels += 1
              }
            }
          }
          if name == "idle" || name == "error" {
            XCTAssertGreaterThan(greenStatusPixels, 20, filename)
          } else {
            XCTAssertEqual(greenStatusPixels, 0, filename)
            if name != "waiting" || selected {
              XCTAssertGreaterThan(indicatorPixels, 20, filename)
            }
          }
        }
      }
    }
  }

  @MainActor
  func testProductionWindowStates() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let output = root.appendingPathComponent("build/production-visuals", isDirectory: true)
    let reference = root.appendingPathComponent(
      "build/production-visual-reference", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let comparesReference = FileManager.default.fileExists(atPath: reference.path)
    for dark in [false, true] {
      for state in ["initial", "selection", "search", "downloading", "pinned", "toolbar"] {
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
        let view = NSHostingView(
          rootView: LatestRootView(environment: environment)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "en_US")))
        let window = NSWindow(
          contentRect: CGRect(x: 0, y: 0, width: 768, height: 516),
          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if state == "toolbar" {
          window.styleMask.insert(.fullSizeContentView)
          window.toolbarStyle = .unified
          window.toolbar = NSToolbar(identifier: "ProductionVisualParity")
          window.toolbar?.insertItem(withItemIdentifier: .flexibleSpace, at: 0)
        }
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let web = try XCTUnwrap(view.firstDescendant(of: WKWebView.self))
        try await waitForWebPaint(web)
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        if state == "pinned", let table = view.firstDescendant(of: NSTableView.self),
          let scroll = table.enclosingScrollView
        {
          scroll.contentView.scroll(to: NSPoint(x: 0, y: 240))
          scroll.reflectScrolledClipView(scroll.contentView)
          table.layoutSubtreeIfNeeded()
          try await Task.sleep(for: .milliseconds(100))
        }
        let captureMarker = root.appendingPathComponent("build/sidebar-window-capture-set")
        if let captureSet = try? String(contentsOf: captureMarker, encoding: .utf8)
          .trimmingCharacters(in: .whitespacesAndNewlines), !captureSet.isEmpty
        {
          try await captureCompleteWindow(
            window, set: captureSet, name: "window-\(state)-\(dark ? "dark" : "light").png")
        }
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let name = "production-\(state)-\(dark ? "dark" : "light").png"
        try record(
          bitmap, name: name, output: output, reference: reference,
          comparesReference: comparesReference)

        // NSHostingView's cache omits the material-composited sidebar.
        // Capture the real table directly as a second complete surface.
        let table = try XCTUnwrap(view.firstDescendant(of: NSTableView.self))
        XCTAssertGreaterThan(table.numberOfRows, 0, "Sidebar fixture must contain real rows")
        for row in 0..<min(table.numberOfRows, 8) {
          _ = table.view(atColumn: 0, row: row, makeIfNecessary: true)
        }
        table.layoutSubtreeIfNeeded()
        let bounds = table.visibleRect
        XCTAssertGreaterThan(bounds.width, 0)
        XCTAssertGreaterThan(bounds.height, 0)
        let sidebar = try XCTUnwrap(table.bitmapImageRepForCachingDisplay(in: bounds))
        table.cacheDisplay(in: bounds, to: sidebar)
        try record(
          sidebar, name: "sidebar-\(state)-\(dark ? "dark" : "light").png",
          output: output, reference: reference, comparesReference: comparesReference)
      }
    }
  }

  @MainActor
  private func captureCompleteWindow(_ window: NSWindow, set: String, name: String) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let output = root.appendingPathComponent("build/sidebar-window-\(set)", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let bitmap = try await captureWindowBitmap(window)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
      to: output.appendingPathComponent(name), options: .atomic)
  }

  @MainActor
  func testReleaseNotesRenderedPixels() async throws {
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
          rootView: ReleaseNotesWebView(text: text)
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
    _ = try await web.callAsyncJavaScript(
      "await document.fonts.ready; await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));",
      arguments: [:], in: nil, contentWorld: .page)
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
