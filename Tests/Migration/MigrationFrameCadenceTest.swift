// Copyright © 2026 Max Langer. All rights reserved.
// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import QuartzCore
import ScreenCaptureKit
import SwiftUI
import XCTest

@testable import Latest

/// Opt-in, visible-window benchmark. Capture timestamps measure WindowServer
/// presentation; the display-link samples only diagnose application scheduling.
@MainActor
final class MigrationFrameCadenceTest: XCTestCase {
  func testHeldArrowPresentationCadence() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let flag = root.appendingPathComponent("build/run-frame-benchmark")
    guard let path = try? String(contentsOf: flag, encoding: .utf8) else {
      throw XCTSkip("Run script/benchmark_frames.sh to measure presented scrolling frames.")
    }
    let output = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
    try runApplicationTest { try await self.measure(output: output) }
  }

  private func measure(output: URL) async throws {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let settings = try isolatedAppListSettings(for: self)
    let apps = (0..<300).map { index in
      let bundle = Latest.App.Bundle(
        version: Version(versionNumber: "1.0", buildNumber: nil),
        name: String(format: "Frame App %03d", index),
        bundleIdentifier: "com.example.frames.\(index)",
        fileURL: URL(fileURLWithPath: "/Applications/Frame-\(index).app"), source: .appStore)
      let update = Latest.App.Update(
        app: bundle, remoteVersion: Version(versionNumber: "2.0", buildNumber: nil),
        minimumOSVersion: nil, source: .appStore, date: Date(timeIntervalSince1970: 1_750_000_000),
        releaseNotes: .html(string: "<h2>Version 2.0</h2><p>Offline frame benchmark notes.</p>"),
        updateAction: .builtIn { _ in })
      return Latest.App(bundle: bundle, update: .success(update), isIgnored: false)
    }
    let model = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: apps, filterQuery: nil, settings: settings),
      settings: settings)
    let environment = AppEnvironment(settings: settings, updatesListViewModel: model)
    NSApp.setActivationPolicy(.regular)
    let window = try await makeLatestTestWindow(
      environment: environment, dark: true, testCase: self)
    let host = try XCTUnwrap(window.contentView)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(500))
    window.setFrame(
      CGRect(origin: window.frame.origin, size: CGSize(width: 768, height: 516)), display: true)
    window.title = "Latest frame benchmark"
    let sidebar = try SidebarInputFixture(window: window, model: model)
    try await sidebar.activate()
    print("FRAME_BENCHMARK_STARTED active=\(NSApp.isActive)")
    let scroll = sidebar.scroll
    let input = FrameInputRecorder(window: window, selectedRow: { sidebar.selectedRow })
    defer { input.stop() }
    let screen = try XCTUnwrap(window.screen)
    XCTAssertEqual(model.snapshot.entries.count, 301)
    try sidebar.focus()
    let screenshot = try await captureWindowBitmap(window)
    try screenshot.representation(using: .png, properties: [:])?.write(
      to: output.appendingPathComponent("fixture.png"))

    let shareable = try await SCShareableContent.currentProcess
    let capturedWindow = try XCTUnwrap(
      shareable.windows.first { $0.windowID == window.windowNumber })
    let rect = scroll.convert(scroll.bounds, to: nil)
    // Exclude toolbar, detail changes, scrollbar, and window chrome. Hash only
    // the rendered row labels/separators in the moving viewport, at 1x capture.
    let region = CGRect(
      x: 80, y: window.frame.height - rect.maxY + 8,
      width: 190, height: rect.height - 16)
    let capture = FrameCapture(region: region)
    let configuration = SCStreamConfiguration()
    configuration.width = Int(window.frame.width)
    configuration.height = Int(window.frame.height)
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 120)
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.queueDepth = 5
    configuration.showsCursor = false
    configuration.capturesAudio = false
    configuration.ignoreShadowsSingleWindow = true
    let queue = DispatchQueue(label: "Latest.FrameBenchmark.Capture")
    let stream = SCStream(
      filter: SCContentFilter(desktopIndependentWindow: capturedWindow),
      configuration: configuration, delegate: capture)
    try stream.addStreamOutput(capture, type: .screen, sampleHandlerQueue: queue)
    try await stream.startCapture()
    let sampler = DisplaySampler(sidebar: sidebar)
    let link = window.displayLink(target: sampler, selector: #selector(DisplaySampler.frame(_:)))
    let refresh = Float(screen.maximumFramesPerSecond)
    link.preferredFrameRateRange = CAFrameRateRange(
      minimum: refresh, maximum: refresh, preferred: refresh)
    link.add(to: .main, forMode: .common)
    defer { link.invalidate() }

    var trials = [Trial]()
    func prepare(down: Bool) async throws {
      let row = down ? 30 : 230
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      try sidebar.focus()
      // Prepare through the renderer's own navigation. Mutating NSClipView
      // directly bypasses SwiftUI's lazy-stack offset/materialization bookkeeping.
      for _ in 0..<model.snapshot.entries.count {
        if sidebar.selectedRow == row { break }
        try sidebar.press(down: sidebar.selectedRow < row)
        try await Task.sleep(for: .milliseconds(5))
      }
      try await Task.sleep(for: .milliseconds(350))
      XCTAssertTrue(window.isKeyWindow)
      XCTAssertTrue(window.occlusionState.contains(.visible))
      XCTAssertEqual(sidebar.selectedRow, row)
    }
    func run(_ name: String, down: Bool, interval: Double = 1.0 / 30, stall: Bool = false)
      async throws -> Trial
    {
      try await prepare(down: down)
      input.keys.removeAll(keepingCapacity: true)
      input.stallOnKey = stall ? 45 : nil
      defer { input.stallOnKey = nil }
      let startRow = sidebar.selectedRow
      let count = Int((3 / interval).rounded())
      let start = CACurrentMediaTime() + 0.05
      let events = try (0..<count).map { index in
        try arrowEvent(down: down, window: window, timestamp: start + Double(index) * interval)
      }
      let feeder = InputFeeder(application: NSApp, events: events)
      feeder.start()
      try await Task.sleep(for: .seconds(3.05))
      let end = CACurrentMediaTime()
      XCTAssertTrue(window.isKeyWindow)
      XCTAssertTrue(window.occlusionState.contains(.visible))
      // Drain queued input after the measurement endpoint before checking its
      // final selection. The captured trial interval remains unchanged.
      try await Task.sleep(for: .milliseconds(350))
      XCTAssertEqual(input.keys.count, count)
      XCTAssertEqual(sidebar.selectedRow, startRow + (down ? count : -count))
      XCTAssertTrue(scroll.contentView.bounds.contains(sidebar.rowRect(sidebar.selectedRow)))
      return Trial(
        name: name, start: start, end: end, keys: input.keys, inputInterval: interval,
        posted: feeder.samples)
    }

    // Check actual queued mouse delivery after keyboard movement. Native row
    // coordinates must agree with the selected app, including adjacent rows.
    for offset in [-3, 0, 1] {
      try await prepare(down: true)
      NSApp.postEvent(try arrowEvent(down: true, window: window), atStart: false)
      let deadline = ContinuousClock.now + .seconds(1)
      while sidebar.selectedRow != 31 && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
      }
      XCTAssertEqual(sidebar.selectedRow, 31)
      let clickedRow = sidebar.selectedRow + offset
      let document = try XCTUnwrap(scroll.documentView)
      let location = document.convert(
        NSPoint(x: 80, y: sidebar.rowRect(clickedRow).minY + 10), to: nil)
      for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try XCTUnwrap(
          NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [],
            timestamp: CACurrentMediaTime(), windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
        NSApp.postEvent(event, atStart: false)
      }
      let clickDeadline = ContinuousClock.now + .seconds(1)
      while sidebar.selectedRow != clickedRow && ContinuousClock.now < clickDeadline {
        try await Task.sleep(for: .milliseconds(1))
      }
      XCTAssertEqual(sidebar.selectedRow, clickedRow, "Click must select the visibly targeted row.")
    }

    // A stationary interval rejects cursor/chrome/detail noise. A compositor
    // color sweep establishes capture capacity independently of main-thread
    // display-link callbacks, which may not commit a surface every refresh.
    try await prepare(down: true)
    let idleStart = CACurrentMediaTime()
    try await Task.sleep(for: .seconds(1))
    trials.append(Trial(name: "idle", start: idleStart, end: CACurrentMediaTime(), keys: []))
    let calibrationParent = try XCTUnwrap(host.superview)
    let calibration = NSView(frame: host.frame)
    calibration.autoresizingMask = [.width, .height]
    calibration.wantsLayer = true
    // An overlay leaves the scene's hosting view and keyboard responder intact.
    // Replacing contentView loses SwiftUI focus even after reattaching the view.
    calibrationParent.addSubview(calibration, positioned: .above, relativeTo: host)
    let calibrationStart = CACurrentMediaTime()
    let colorSweep = CABasicAnimation(keyPath: "backgroundColor")
    colorSweep.fromValue = CGColor(gray: 0, alpha: 1)
    colorSweep.toValue = CGColor(gray: 1, alpha: 1)
    colorSweep.duration = 2
    colorSweep.timingFunction = CAMediaTimingFunction(name: .linear)
    calibration.layer?.add(colorSweep, forKey: "capture-calibration")
    try await Task.sleep(for: .seconds(2))
    calibration.removeFromSuperview()
    trials.append(
      Trial(name: "calibration", start: calibrationStart, end: CACurrentMediaTime(), keys: []))
    _ = try await run("warmup", down: true)
    for (label, interval) in [
      ("repeat", NSEvent.keyRepeatInterval), ("fast", 1.0 / 30), ("stress", 1.0 / 60),
    ] {
      trials.append(try await run("down-\(label)", down: true, interval: interval))
      trials.append(try await run("up-\(label)", down: false, interval: interval))
    }
    trials.append(try await run("stall-control", down: true, stall: true))
    try await stream.stopCapture()
    queue.sync {}
    XCTAssertNil(capture.failure)
    XCTAssertGreaterThan(capture.frames.count, 100)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let report = Report(
      screen: screen.localizedName, maximumFPS: screen.maximumFramesPerSecond,
      configuredKeyRepeatInterval: NSEvent.keyRepeatInterval,
      windowWidth: window.frame.width, windowHeight: window.frame.height,
      captureRegion: [region.minX, region.minY, region.width, region.height],
      trials: trials, displaySamples: sampler.samples, capturedFrames: capture.frames)
    try encoder.encode(report).write(to: output.appendingPathComponent("raw.json"))
    print("FRAME_BENCHMARK raw=\(output.appendingPathComponent("raw.json").path)")
  }

  private func arrowEvent(down: Bool, window: NSWindow, timestamp: Double = CACurrentMediaTime())
    throws -> NSEvent
  {
    let character = down ? "\u{F701}" : "\u{F700}"
    return try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
        timestamp: timestamp, windowNumber: window.windowNumber, context: nil,
        characters: character, charactersIgnoringModifiers: character,
        isARepeat: true, keyCode: down ? 125 : 126))
  }
}

private struct PostedKey: Codable {
  let intended: Double
  let time: Double
}

// Schedule input independently of rendering. Main-queue posting obeys AppKit's
// Swift actor annotations; event timestamps retain their intended deadlines.
// Feeder jitter is recorded separately from waiting for the application thread.
private final class InputFeeder: @unchecked Sendable {
  private let application: NSApplication
  private let events: [NSEvent]
  private let queue = DispatchQueue(label: "Latest.FrameBenchmark.Input", qos: .userInteractive)
  private let lock = NSLock()
  private var posted = [PostedKey]()
  var samples: [PostedKey] { lock.withLock { posted } }

  init(application: NSApplication, events: [NSEvent]) {
    self.application = application
    self.events = events
  }

  func start() {
    queue.async { [self] in
      for index in events.indices {
        let intended = events[index].timestamp
        let remaining = intended - CACurrentMediaTime()
        if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
        lock.withLock { posted.append(PostedKey(intended: intended, time: CACurrentMediaTime())) }
        DispatchQueue.main.async { [self] in
          application.postEvent(events[index], atStart: false)
        }
      }
    }
  }
}

private struct KeySample: Codable {
  let time: Double
  let duration: Double
  let queued: Double
  let row: Int
}

@MainActor
private final class FrameInputRecorder {
  var keys = [KeySample]()
  var stallOnKey: Int?
  let window: NSWindow
  let selectedRow: () -> Int
  private var monitor: Any?

  init(window: NSWindow, selectedRow: @escaping () -> Int) {
    self.window = window
    self.selectedRow = selectedRow
    // Preserve the actual SwiftUI scene's NSWindow and responder chain. Record
    // queued arrows at normal application dispatch, then deliver each once.
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window === self.window, [125, 126].contains(event.keyCode) else {
        return event
      }
      self.record(event)
      return nil
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }

  private func record(_ event: NSEvent) {
    let time = CACurrentMediaTime()
    window.sendEvent(event)
    if keys.count == stallOnKey { Thread.sleep(forTimeInterval: 0.1) }
    let row = selectedRow()
    keys.append(
      KeySample(
        time: time, duration: CACurrentMediaTime() - time, queued: event.timestamp, row: row))
  }
}

private struct Trial: Codable {
  let name: String
  let start: Double
  let end: Double
  let keys: [KeySample]
  var inputInterval: Double = 1.0 / 30
  var posted = [PostedKey]()
}

private struct DisplaySample: Codable {
  let time: Double
  let y: Double
  let row: Int
  let active: Bool
  let key: Bool
  let visible: Bool
}

private struct CapturedFrame: Codable {
  let time: Double
  let received: Double
  let status: Int
  let hash: String?
  let headerHash: String?
  let selectionTop: Int?
  let processingMilliseconds: Double
}

private struct Report: Codable {
  let screen: String
  let maximumFPS: Int
  let configuredKeyRepeatInterval: Double
  let windowWidth: Double
  let windowHeight: Double
  let captureRegion: [Double]
  let trials: [Trial]
  let displaySamples: [DisplaySample]
  let capturedFrames: [CapturedFrame]
}

@MainActor
private final class DisplaySampler: NSObject {
  let sidebar: SidebarInputFixture
  var samples = [DisplaySample]()
  init(sidebar: SidebarInputFixture) { self.sidebar = sidebar }

  @objc func frame(_ link: CADisplayLink) {
    let scroll = sidebar.scroll
    samples.append(
      DisplaySample(
        time: CACurrentMediaTime(),
        y: Double(
          scroll.contentView.layer?.presentation()?.bounds.minY ?? scroll.contentView.bounds.minY),
        row: sidebar.selectedRow,
        active: NSApp.isActive, key: sidebar.window.isKeyWindow == true,
        visible: sidebar.window.occlusionState.contains(.visible) == true))
  }
}

// Only the serial capture queue mutates this object; read after stopCapture and
// queue.sync. No per-frame dispatch back onto the measured main thread.
private final class FrameCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
  let region: CGRect
  var frames = [CapturedFrame]()
  private let failureLock = NSLock()
  private var captureFailure: String?
  var failure: String? { failureLock.withLock { captureFailure } }
  private var timebase = mach_timebase_info_data_t()
  init(region: CGRect) {
    self.region = region
    super.init()
    mach_timebase_info(&timebase)
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    failureLock.withLock { captureFailure = String(describing: error) }
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType
  ) {
    guard type == .screen, buffer.isValid else { return }
    let received = CACurrentMediaTime()
    guard
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let info = attachments.first,
      let ticks = (info[.displayTime] as? NSNumber)?.uint64Value,
      let status = (info[.status] as? NSNumber)?.intValue
    else { return }
    var hash: UInt64?
    var headerHash: UInt64?
    var selectionTop: Int?
    if status == SCFrameStatus.complete.rawValue,
      let pixel = CMSampleBufferGetImageBuffer(buffer)
    {
      CVPixelBufferLockBaseAddress(pixel, .readOnly)
      defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
      if let base = CVPixelBufferGetBaseAddress(pixel) {
        var value: UInt64 = 14_695_981_039_346_656_037
        var header: UInt64 = 14_695_981_039_346_656_037
        let rowBytes = CVPixelBufferGetBytesPerRow(pixel)
        for y in stride(
          from: max(0, Int(region.minY)),
          to: min(Int(region.maxY), CVPixelBufferGetHeight(pixel)), by: 8)
        {
          let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt32.self)
          for x in stride(
            from: max(0, Int(region.minX)),
            to: min(Int(region.maxX), CVPixelBufferGetWidth(pixel)), by: 8)
          {
            value = (value ^ UInt64(row[x])) &* 1_099_511_628_211
          }
        }
        hash = value
        // The measured floating title band ends before the following app's
        // version line. Hash every pixel here to detect even a one-pixel drift.
        for y in Int(region.minY)..<Int(region.minY) + 16 {
          let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt32.self)
          for x in 22..<Int(region.maxX) {
            header = (header ^ UInt64(row[x])) &* 1_099_511_628_211
          }
        }
        headerHash = header
        // Observe the native blue capsule independently of scroll-layer bounds.
        // This strip is inside its rounded edge and outside icons and labels.
        for y in Int(region.minY)..<Int(region.maxY) {
          let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
          let x = 22 * 4
          if row[x] > 150, row[x + 2] < 80, Int(row[x]) > Int(row[x + 1]) + 40 {
            selectionTop = y
            break
          }
        }
      }
    }
    let time = Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    frames.append(
      CapturedFrame(
        time: time, received: received, status: status, hash: hash.map(String.init),
        headerHash: headerHash.map(String.init),
        selectionTop: selectionTop,
        processingMilliseconds: (CACurrentMediaTime() - received) * 1_000))
  }
}
