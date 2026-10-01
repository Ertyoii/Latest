// Fork contributions © 2026 ertyoii.
// Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import Combine
import ScreenCaptureKit
import SwiftUI
import WebKit

/// Alternate entrypoint compiled only in the derived capture project. Normal
/// application sources, resources, build settings and the Window scene are reused.
@main
struct ProductionCaptureApplication: SwiftUI.App {
  @NSApplicationDelegateAdaptor(ApplicationLifecycleDelegate.self)
  private var lifecycleDelegate
  @StateObject private var fixture: ProductionSceneFixture

  init() {
    do {
      let fixture = try ProductionSceneFixture()
      _fixture = StateObject(wrappedValue: fixture)
    } catch {
      FileHandle.standardError.write(Data("PRODUCTION_CAPTURE FAIL: \(error)\n".utf8))
      exit(1)
    }
  }

  var body: some Scene {
    LatestMainWindowScene(
      environment: fixture.environment, appearance: fixture.appearance,
      appUpdateController: fixture.appUpdateController,
      start: fixture.startCapture, stop: {}
    )
    .environment(\.locale, Locale(identifier: "en_US"))
    Settings {
      SettingsRootView(viewModel: fixture.environment.settingsViewModel)
        .modifier(ApplicationAppearanceModifier(appearance: fixture.appearance))
    }
  }
}

@MainActor
private final class ProductionSceneFixture: ObservableObject {
  @Published var appearance = ApplicationAppearance.light
  let apps = LocalUATFixture.apps
  let model: UpdatesListViewModel
  let environment: AppEnvironment
  let appUpdateController = AppUpdateController()
  private let suite = "ProductionSceneFixture.\(UUID().uuidString)"
  private let defaults: UserDefaults
  private var started = false

  init() throws {
    defaults = try unwrap(UserDefaults(suiteName: suite))
    let settings = AppListSettings(userDefaults: defaults)
    settings.sortOrder = .name
    settings.showInstalledUpdates = true
    settings.showIgnoredUpdates = true
    settings.includeUnsupportedApps = true
    settings.includeAppsWithLimitedSupport = true
    model = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: apps, filterQuery: nil, settings: settings),
      settings: settings)
    model.select(apps[0])
    environment = AppEnvironment(settings: settings, updatesListViewModel: model)
  }

  func startCapture() {
    guard !started else { return }
    started = true
    Task { @MainActor in
      var status: Int32 = 0
      do { try await ProductionVisualCapture(fixture: self).run() } catch {
        FileHandle.standardError.write(
          Data("PRODUCTION_CAPTURE FAIL: \(error.localizedDescription)\n".utf8))
        status = 1
      }
      defaults.removePersistentDomain(forName: suite)
      fflush(stdout)
      exit(status)
    }
  }
}

private func unwrap<T>(_ value: T?, _ message: String = "Missing required capture value") throws
  -> T
{
  guard let value else { throw ProductionVisualReference.Failure(message: message) }
  return value
}

@MainActor
private struct ProductionVisualCapture {
  let fixture: ProductionSceneFixture
  @MainActor
  func run() async throws {
    typealias Gate = ProductionVisualReference
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let requestURL = root.appendingPathComponent("build/production-visual-request.json")
    let request: Gate.Request? =
      FileManager.default.fileExists(atPath: requestURL.path)
      ? try Gate.read(Gate.Request.self, from: requestURL) : nil
    if let request {
      try Gate.require(
        ["capture-original", "verify-required"].contains(request.mode), "Invalid capture mode")
      for (path, hash) in request.provenance.productionSources.merging(
        request.provenance.captureSources, uniquingKeysWith: { first, _ in first })
      {
        try Gate.require(
          Gate.hash(try Data(contentsOf: root.appendingPathComponent(path))) == hash,
          "Sources changed after capture request: \(path)")
      }
      if request.mode == "verify-required" {
        let reference = try unwrap(request.reference, "Required verification needs a reference")
        try Gate.compatible(
          try Gate.validate(reference, kind: "original"), provenance: request.provenance)
      }
    }
    let output =
      request?.output ?? root.appendingPathComponent("build/production-scene-fixture-diagnostics")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    // Fix the test host's native formatters too, not just SwiftUI's environment.
    let previousTimezone = NSTimeZone.default
    NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
    defer { NSTimeZone.default = previousTimezone }
    NSApp.activate()
    print(
      "PRODUCTION_CAPTURE nativeLocale=\(Locale.current.identifier) timezone=\(NSTimeZone.default.identifier)"
    )
    if request != nil {
      try Gate.require(
        Locale.current.language.languageCode?.identifier == "en"
          && Locale.current.region?.identifier == "US", "Required capture must launch in en_US")
    }
    var settings = [
      "capture": "ScreenCaptureKit desktopIndependentWindow; no external shadow or cursor",
      "normalization": "sRGB premultiplied RGBA8; exact all pixels",
      "outputScale": "2", "productionContentSize": "768x516",
      "notesContentSizes": "460x360,680x360",
      "appearance": "explicit aqua,darkAqua", "swiftUILocale": "en_US",
      "scene":
        "LatestMainWindowScene through SwiftUI App.main; production Window sizing, toolbar and commands",
      "focus": "key window; neutral first responder; no blinking caret",
      "position": "main visible-frame origin + (100,100)",
      "nativeLocale": Locale.current.identifier,
      "timezone": NSTimeZone.default.identifier,
      "settling":
        "web fonts+2RAF; 1200ms native titlebar activation; 5 equal composited frames at 80ms",
      "pinnedInput":
        "pixel wheel -240 at sidebar content (140,170 from top); unchanged selection; exact stationary painted header band",
      "scrollPositions": "notes 0,160",
      "progress": "downloading 25000000/100000000; settle animations",
      "reduceMotion": String(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion),
      "reduceTransparency": String(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency),
      "increaseContrast": String(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast),
      "screenFrame": NSStringFromRect(try unwrap(NSScreen.main).frame),
      "screenBackingScale": String(describing: try unwrap(NSScreen.main).backingScaleFactor),
    ]
    for key in [
      "AppleLanguages", "AppleLocale", "AppleAccentColor", "AppleHighlightColor",
      "AppleShowScrollBars", "AppleFontSmoothing",
    ] {
      if let value = UserDefaults.standard.object(forKey: key) {
        let json = try JSONSerialization.data(
          withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        settings[key] = String(decoding: json, as: UTF8.self)
      } else {
        settings[key] = "unset"
      }
    }
    for app in LocalUATFixture.apps {
      try Gate.require(
        FileManager.default.fileExists(atPath: app.fileURL.path),
        "Missing fixture icon bundle: \(app.fileURL.path)")
      let icon = await IconCache.shared.icon(for: app)
      let image = try unwrap(icon.cgImage(forProposedRect: nil, context: nil, hints: nil))
      settings["icon:" + app.fileURL.path] = Gate.hash(
        try Gate.rgba(NSBitmapImageRep(cgImage: image)))
    }
    if let request, let reference = request.reference {
      let original = try Gate.validate(reference, kind: "original")
      if original.settings != settings {
        try Gate.write(
          settings, to: output.appendingPathComponent("incompatible-runtime-settings.json"))
        throw Gate.Failure(
          message:
            "Incompatible runtime capture settings; see candidate/incompatible-runtime-settings.json"
        )
      }
    }
    var images: [Gate.Image] = []
    func record(_ bitmap: NSBitmapImageRep, name: String) throws {
      let png = try unwrap(bitmap.representation(using: .png, properties: [:]))
      try png.write(to: output.appendingPathComponent(name), options: .atomic)
      images.append(try Gate.describe(bitmap, name: name))
    }
    try await captureProductionWindowStates(record: record)
    try await captureReleaseNotesRenderedPixels(record: record)
    try Gate.require(
      images.map(\.name).sorted() == Gate.names, "Production capture matrix is incomplete")
    if let request {
      try Gate.write(
        Gate.Manifest(
          schemaVersion: Gate.schema,
          kind: request.mode == "capture-original" ? "original" : "candidate",
          recordedAt: Date(), provenance: request.provenance, settings: settings, images: images),
        to: output.appendingPathComponent("manifest.json"))
      if let reference = request.reference {
        _ = try Gate.compareRequired(reference: reference, candidate: output)
      }
    } else {
      print(
        "PRODUCTION_CAPTURE fixture-only images=\(images.count); use verify-required for migration proof"
      )
    }
  }

  @MainActor
  private func configureCaptureWindow(_ window: NSWindow, dark: Bool, contentSize: NSSize)
    async throws
  {
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let screen = try unwrap(NSScreen.main)
    window.setFrameOrigin(
      NSPoint(x: screen.visibleFrame.minX + 100, y: screen.visibleFrame.minY + 100))
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    for _ in 0..<40 {
      if window.isKeyWindow && NSApp.isActive { break }
      try await Task.sleep(for: .milliseconds(50))
      window.makeKeyAndOrderFront(nil)
    }
    try ProductionVisualReference.require(
      window.isKeyWindow && NSApp.isActive, "Capture window must be active")
    // Automatic TextField focus introduces a blinking caret. Use an explicit
    // neutral responder for these static states; focused-search behavior is a separate contract.
    window.makeFirstResponder(nil)
    window.layoutIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
    // SwiftUI installs the native toolbar asynchronously. Freeze content size
    // after that composition, rather than inheriting NSHostingView's sizing proposal.
    try await Task.sleep(for: .milliseconds(200))
    window.setContentSize(contentSize)
    window.layoutIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
    try ProductionVisualReference.require(
      window.contentView?.bounds.size == contentSize,
      "Production capture content dimensions must be fixed")
  }

  @MainActor
  private func captureProductionWindowStates(record: (NSBitmapImageRep, String) throws -> Void)
    async throws
  {
    var created: NSWindow?
    for _ in 0..<100 {
      created = NSApp.windows.first {
        $0.isVisible && $0.contentView?.captureDescendant(of: WKWebView.self) != nil
      }
      if created != nil { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    let window = try unwrap(
      created, "The production Window scene must create visible release-note content")
    for dark in [false, true] {
      fixture.appearance = dark ? .dark : .light
      for state in ["initial", "selection", "search", "downloading", "pinned", "toolbar"] {
        fixture.model.setSearchQuery("")
        fixture.model.select(fixture.apps[0])
        if state == "selection" { fixture.model.select(fixture.apps[3]) }
        if state == "search" { fixture.model.setSearchQuery("Notes") }
        var operation: UpdateOperation?
        if state == "downloading" {
          let updating = VisualCaptureOperation(app: fixture.apps[0])
          UpdateQueue.shared.addOperation(updating)
          for _ in 0..<40 {
            if updating.didStart { break }
            try await Task.sleep(for: .milliseconds(50))
          }
          try ProductionVisualReference.require(
            updating.didStart, "Fixture operation did not start")
          updating.progressState = .downloading(loadedSize: 25_000_000, totalSize: 100_000_000)
          operation = updating
        }
        defer { operation?.finish() }
        try await configureCaptureWindow(
          window, dark: dark, contentSize: NSSize(width: 768, height: 516))
        // Reopening the same production Window avoids synthetic toolbar variants.
        // Return scroll to the top with real input between fixture states.
        try await scrollSidebarToStart(window)
        try await Task.sleep(for: .milliseconds(400))
        let content = try unwrap(window.contentView)
        let web = try unwrap(content.captureDescendant(of: WKWebView.self))
        try await waitForWebPaint(
          web,
          containing: "Offline acceptance fixture for "
            + (try unwrap(fixture.model.selectedApp)).name)
        let name = "production-\(state)-\(dark ? "dark" : "light").png"
        print(
          "PRODUCTION_CAPTURE ready=\(name) scene=LatestMainWindowScene frame=\(NSStringFromRect(window.frame)) content=\(NSStringFromRect(window.contentLayoutRect))"
        )
        if state == "pinned" { try await scrollSidebarUsingInput(window, model: fixture.model) }
        try ProductionVisualReference.require(
          fixture.model.searchQuery == (state == "search" ? "Notes" : ""),
          "Search fixture not applied")
        try ProductionVisualReference.require(
          fixture.model.selectedApp?.identifier
            == (state == "selection" ? fixture.apps[3] : fixture.apps[0]).identifier,
          "Selection fixture not applied")
        try record(try await settledWindowBitmap(window, name: name), name)
      }
    }
  }

  @MainActor
  private func scrollSidebarToStart(_ window: NSWindow) async throws {
    let content = try unwrap(window.contentView)
    let point = NSPoint(x: 140, y: content.isFlipped ? 170 : content.bounds.height - 170)
    let target = try unwrap(content.hitTest(content.convert(point, to: content.superview)))
    let cg = try unwrap(
      CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
        wheel1: 2000, wheel2: 0, wheel3: 0))
    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    target.scrollWheel(with: try unwrap(NSEvent(cgEvent: cg)))
    try await Task.sleep(for: .milliseconds(150))
  }

  /// Input is delivered to a geometric hit target; no production table or
  /// scroll-container type is required. Composited pixels prove row movement
  /// and a stationary section header, while model selection must stay unchanged.
  @MainActor
  private func scrollSidebarUsingInput(_ window: NSWindow, model: UpdatesListViewModel) async throws
  {
    let content = try unwrap(window.contentView)
    let selection = model.selectedApp?.identifier
    let before = try await settledWindowBitmap(window, name: "pinned-before-input")
    let point = NSPoint(x: 140, y: content.isFlipped ? 170 : content.bounds.height - 170)
    let target = try unwrap(content.hitTest(content.convert(point, to: content.superview)))
    let cg = try unwrap(
      CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
        wheel1: -240, wheel2: 0, wheel3: 0))
    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    let input = try unwrap(NSEvent(cgEvent: cg))
    target.scrollWheel(with: input)
    let after = try await settledWindowBitmap(window, name: "pinned-after-input")
    try ProductionVisualReference.require(
      model.selectedApp?.identifier == selection, "Wheel input must preserve selection")
    let a = try ProductionVisualReference.rgba(before)
    let b = try ProductionVisualReference.rgba(after)
    // Independent state assertions only, never masks in the required full-window comparison.
    // The frozen production layout places the header after the 44pt search strip.
    let contentTop = window.frame.height - window.contentLayoutRect.maxY
    let headerTop = Int((contentTop + 44) * 2)
    var changedHeaderPixels = 0
    var headerInkPixels = 0
    for y in (headerTop + 10)..<(headerTop + 44) {
      for x in 40..<600 {
        let offset = (y * before.pixelsWide + x) * 4
        if a[offset..<offset + 4] != b[offset..<offset + 4] { changedHeaderPixels += 1 }
        if abs(Int(a[offset]) - Int(a[(y * before.pixelsWide + 10) * 4])) > 30 {
          headerInkPixels += 1
        }
      }
    }
    try ProductionVisualReference.require(
      headerInkPixels > 100, "Header band must contain painted text")
    try ProductionVisualReference.require(
      changedHeaderPixels == 0, "Painted section heading must remain pinned")
    var changedSidebarPixels = 0
    for y in (headerTop + 60)..<min(before.pixelsHigh, headerTop + 700) {
      for x in 0..<600 {
        let offset = (y * before.pixelsWide + x) * 4
        if a[offset..<offset + 4] != b[offset..<offset + 4] { changedSidebarPixels += 1 }
      }
    }
    try ProductionVisualReference.require(
      changedSidebarPixels > 1000, "Real scroll input must move sidebar rows")
    print(
      "PRODUCTION_CAPTURE pinned header_changed=\(changedHeaderPixels) moved_row_pixels=\(changedSidebarPixels)"
    )
  }

  @MainActor
  private func settledWindowBitmap(_ window: NSWindow, name: String) async throws
    -> NSBitmapImageRep
  {
    var previous: Data?
    var stableFrames = 0
    var firstBitmap: NSBitmapImageRep?
    var lastBitmap: NSBitmapImageRep?
    for _ in 0..<100 {
      try await Task.sleep(for: .milliseconds(80))
      window.layoutIfNeeded()
      window.contentView?.layoutSubtreeIfNeeded()
      let bitmap = try await captureWindowBitmap(window)
      let pixels = try ProductionVisualReference.rgba(bitmap)
      if firstBitmap == nil { firstBitmap = bitmap }
      lastBitmap = bitmap
      stableFrames = pixels == previous ? stableFrames + 1 : 0
      if stableFrames >= 5 { return bitmap }
      previous = pixels
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let diagnostic = root.appendingPathComponent("build/production-unsettled")
    try FileManager.default.createDirectory(at: diagnostic, withIntermediateDirectories: true)
    for (suffix, bitmap) in [("first", firstBitmap), ("last", lastBitmap)] {
      if let bitmap {
        try bitmap.representation(using: .png, properties: [:])?.write(
          to: diagnostic.appendingPathComponent("\(name)-\(suffix).png"))
      }
    }
    print(
      "PRODUCTION_CAPTURE unsettled=\(name) diagnostics=\(diagnostic.path) firstResponder=\(String(describing: window.firstResponder))"
    )
    throw ProductionVisualReference.Failure(message: "Capture did not settle: " + name)
  }

  @MainActor
  private func captureReleaseNotesRenderedPixels(record: (NSBitmapImageRep, String) throws -> Void)
    async throws
  {
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
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "en_US")))
        host.sizingOptions = []
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: width, height: 360),
          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        try await configureCaptureWindow(
          window, dark: dark, contentSize: NSSize(width: width, height: 360))
        defer { window.close() }
        // Native titlebar controls finish activation after content first paints.
        // Equal WebKit frames alone can precede their delayed emphasis update.
        try await Task.sleep(for: .milliseconds(1200))
        // Inspect the rendering engine, not a particular representable or SwiftUI wrapper.
        var renderer: WKWebView?
        for _ in 0..<200 {
          renderer = host.captureDescendant(of: WKWebView.self)
          if let renderer, !renderer.isLoading,
            let body = try? await renderer.evaluateJavaScript("document.body.innerText") as? String,
            body.contains("Release 1.2")
          {
            break
          }
          try await Task.sleep(for: .milliseconds(50))
        }
        let web = try unwrap(renderer)
        try await waitForWebPaint(web, containing: "Release 1.2")
        for scrolled in [false, true] {
          _ = try await web.evaluateJavaScript("window.scrollTo(0, \(scrolled ? 160 : 0))")
          try await waitForWebPaint(web, containing: "Release 1.2")
          let scrollY = try await web.evaluateJavaScript("window.scrollY") as? Int
          try ProductionVisualReference.require(
            scrollY == (scrolled ? 160 : 0), "Notes scroll input must reach the requested position")
          print(
            "PRODUCTION_CAPTURE notes pointer=\(NSStringFromPoint(NSEvent.mouseLocation)) frame=\(NSStringFromRect(window.frame)) key=\(window.isKeyWindow) main=\(window.isMainWindow) zoomHighlighted=\(window.standardWindowButton(.zoomButton)?.isHighlighted == true)"
          )
          let name = "web-\(width)-\(dark ? "dark" : "light")-\(scrolled ? "scrolled" : "top").png"
          try record(try await settledWindowBitmap(window, name: name), name)
        }
      }
    }
  }

  @MainActor
  private func waitForWebPaint(_ web: WKWebView, containing expectedText: String) async throws {
    var ready = false
    for _ in 0..<200 {
      let text =
        try? await web.evaluateJavaScript("document.querySelector('main')?.textContent") as? String
      ready = text?.contains(expectedText) == true && !web.isLoading
      if ready { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    try ProductionVisualReference.require(
      ready, "Release notes must be loaded before comparing pixels")
    _ = try await web.evaluateJavaScript(
      "window.__capturePaintReady = false; document.fonts.ready.then(() => requestAnimationFrame(() => requestAnimationFrame(() => window.__capturePaintReady = true))); true"
    )
    var painted = false
    for _ in 0..<100 {
      painted = (try? await web.evaluateJavaScript("window.__capturePaintReady") as? Bool) == true
      if painted { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    try ProductionVisualReference.require(
      painted, "Web fonts/animation frames did not settle while visible")
    web.displayIfNeeded()
  }

}

private final class VisualCaptureOperation: UpdateOperation, @unchecked Sendable {
  private let startedLock = NSLock()
  private var started = false
  var didStart: Bool { startedLock.withLock { started } }
  override func execute() {
    super.execute()
    startedLock.withLock { started = true }
  }
  init(app: App) {
    super.init(bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier)
  }
}

@MainActor
private func captureWindowBitmap(_ window: NSWindow) async throws -> NSBitmapImageRep {
  let shareable = try await SCShareableContent.currentProcess
  let capturedWindow = try unwrap(shareable.windows.first { $0.windowID == window.windowNumber })
  let configuration = SCStreamConfiguration()
  configuration.width = Int(window.frame.width * 2)
  configuration.height = Int(window.frame.height * 2)
  configuration.showsCursor = false
  configuration.ignoreShadowsSingleWindow = true
  configuration.ignoreGlobalClipSingleWindow = true
  let image = try await SCScreenshotManager.captureImage(
    contentFilter: SCContentFilter(desktopIndependentWindow: capturedWindow),
    configuration: configuration)
  return NSBitmapImageRep(cgImage: image)
}

extension NSView {
  fileprivate func captureDescendant<T: NSView>(of type: T.Type) -> T? {
    if let match = self as? T { return match }
    return subviews.lazy.compactMap { $0.captureDescendant(of: type) }.first
  }
}
