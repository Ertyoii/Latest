//
//  MigrationPerformanceTest.swift
//  Latest Tests
//
//  Created by ertyoii on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-01.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import Darwin
import Darwin.Mach
import SwiftUI
import XCTest

@testable import Latest

@MainActor
final class MigrationPerformanceTest: XCTestCase {
  func testMigrationPerformanceMatrix() throws {
    guard FileManager.default.fileExists(atPath: Self.benchmarkFlagURL.path) else {
      throw XCTSkip("Run script/benchmark_migration.sh to execute migration benchmarks.")
    }

    configureSettings()
    emitConfigurationLine()
    let appsBySize = Dictionary(
      uniqueKeysWithValues: [100, 500, 1_500].map { ($0, makeApps(count: $0)) })

    for rowCount in [100, 500, 1_500] {
      let apps = try XCTUnwrap(appsBySize[rowCount])
      let snapshot = AppListSnapshot(withApps: apps, filterQuery: nil)
      let queries = (0..<60).map { "Benchmark App \($0 % max(rowCount / 10, 1))" }
      benchmarkSamples("sidebar_filter_\(rowCount)", values: queries) { query in
        snapshot.refiltered(with: query).entries.count
      }
    }

    let populatedApps = try XCTUnwrap(appsBySize[500])
    benchmark("cold_launch_to_populated_sidebar_fixture", iterations: 30) {
      let snapshot = AppListSnapshot(withApps: populatedApps, filterQuery: nil)
      let viewModel = UpdatesListViewModel(snapshot: snapshot)
      let host = NSHostingView(
        rootView: UpdatesSidebarView(
          viewModel: viewModel,
          searchFocusController: SearchFocusController()
        ))
      host.frame = NSRect(x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: 640)
      let window = attachToWindow(host)
      withExtendedLifetime(window) {
        host.displayIfNeeded()
      }
      return host.descendant(of: NSTableView.self)?.numberOfRows ?? snapshot.apps.count
    }

    let scanRoot = try makeSyntheticAppRoot(count: 120)
    defer { try? FileManager.default.removeItem(at: scanRoot) }
    benchmark("scan_to_stable_snapshot_fixture", iterations: 30) {
      let bundles = BundleCollector.collectBundles(at: scanRoot)
      let apps = bundles.map { Latest.App(bundle: $0, update: nil, isIgnored: false) }
      return AppListSnapshot(withApps: apps, filterQuery: nil).entries.count
    }

    let scrollSnapshot = AppListSnapshot(
      withApps: try XCTUnwrap(appsBySize[1_500]), filterQuery: nil)
    let scrollViewModel = UpdatesListViewModel(snapshot: scrollSnapshot)
    let scrollHost = NSHostingView(
      rootView: UpdatesSidebarView(
        viewModel: scrollViewModel,
        searchFocusController: SearchFocusController()
      ))
    scrollHost.frame = NSRect(x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: 640)
    let scrollWindow = attachToWindow(scrollHost)
    defer { scrollWindow.close() }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    let sidebarScrollView = try XCTUnwrap(
      scrollHost.descendants(of: NSScrollView.self).max {
        ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0)
      }
    )
    let maximumScrollY = max(
      0, (sidebarScrollView.documentView?.bounds.height ?? 0) - sidebarScrollView.contentSize.height
    )
    let smoothScrollStart = min(
      maximumScrollY * 0.25,
      max(maximumScrollY - (VisualMetrics.appRowHeight * 120), 0)
    )
    benchmarkSamples("sidebar_scroll_frame_main_thread", values: Array(0..<120)) { index in
      let y = min(
        smoothScrollStart + (CGFloat(index) * VisualMetrics.appRowHeight),
        maximumScrollY
      )
      sidebarScrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
      sidebarScrollView.reflectScrolledClipView(sidebarScrollView.contentView)
      scrollHost.layoutSubtreeIfNeeded()
      scrollHost.displayIfNeeded()
      return Int(sidebarScrollView.contentView.bounds.origin.y)
    }

    // Preserve the former benchmark's deliberately hostile teleport pattern as
    // a separately named stress test. It skips roughly 79 rows per sample at
    // 1,500 apps and therefore measures long-distance seeking/materialization,
    // not one frame of continuous scrolling.
    benchmarkSamples("sidebar_long_jump_main_thread", values: Array(0..<120)) { index in
      let fraction = Double(index % 20) / 19
      sidebarScrollView.contentView.scroll(to: NSPoint(x: 0, y: maximumScrollY * fraction))
      sidebarScrollView.reflectScrolledClipView(sidebarScrollView.contentView)
      scrollHost.layoutSubtreeIfNeeded()
      scrollHost.displayIfNeeded()
      return Int(sidebarScrollView.contentView.bounds.origin.y)
    }

    let detailApps = Array(populatedApps.prefix(80))
    let detailViewModel = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: detailApps, filterQuery: nil))
    let detailState = ReleaseNotesDetailViewModel(
      releaseNotesProvider: ImmediateReleaseNotesProvider(
        text: NSAttributedString(string: "Migration benchmark release notes")
      )
    )
    let detailHost = NSHostingView(
      rootView: ReleaseNotesDetailView(
        updatesViewModel: detailViewModel,
        detailViewModel: detailState
      ))
    detailHost.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
    let detailWindow = attachToWindow(detailHost)
    defer { detailWindow.close() }
    detailHost.layoutSubtreeIfNeeded()
    let memoryBefore = residentMemoryBytes()
    benchmarkSamples("selection_to_detail", values: Array(0..<160)) { index in
      let app = detailApps[index % detailApps.count]
      detailViewModel.select(app)
      // The production view routes the same selection into this persistent state
      // object from its task. Keep the host alive so this measures selection,
      // detail-state publication, and rendering rather than root reconstruction.
      detailState.display(app)
      detailHost.layoutSubtreeIfNeeded()
      detailHost.displayIfNeeded()
      return detailState.app?.identifier == app.identifier ? 1 : 0
    }
    let memoryAfter = residentMemoryBytes()
    emitMemoryLine(
      name: "repeated_selection_160",
      before: memoryBefore,
      after: memoryAfter
    )

    let markup = makeReleaseNotesMarkup(sectionCount: 220)
    try benchmark("rich_text_normalization_layout", iterations: 30) {
      let text = try ReleaseNotesMarkup.attributedString(
        from: markup,
        baseURL: URL(string: "https://example.com/changelog"),
        relevantVersion: "220.0"
      ).get()
      let storage = NSTextStorage(attributedString: text)
      let layoutManager = NSLayoutManager()
      let container = NSTextContainer(
        size: NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude))
      container.widthTracksTextView = false
      storage.addLayoutManager(layoutManager)
      layoutManager.addTextContainer(container)
      layoutManager.ensureLayout(for: container)
      return layoutManager.glyphRange(for: container).length
    }

    let environment = AppEnvironment(
      updatesListViewModel: UpdatesListViewModel(snapshot: scrollSnapshot)
    )
    let splitHost = NSHostingView(rootView: LatestRootView(environment: environment))
    splitHost.frame = NSRect(x: 0, y: 0, width: 1_000, height: 640)
    let splitWindow = attachToWindow(splitHost)
    defer { splitWindow.close() }
    benchmarkSamples("resize_split_frame", values: Array(0..<100)) { index in
      let width = index.isMultiple(of: 2) ? 700.0 : 1_300.0
      splitHost.frame.size = NSSize(width: width, height: index.isMultiple(of: 3) ? 480 : 760)
      splitHost.layoutSubtreeIfNeeded()
      return Int(splitHost.bounds.width)
    }

    let settingsViewModel = SettingsViewModel()
    benchmark("settings_locations_refresh", iterations: 40) {
      settingsViewModel.refreshDirectories()
      return settingsViewModel.directoryURLs.count
    }
  }

  private static var benchmarkFlagURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("build/run-migration-benchmarks")
  }

  func testReleaseNotesSelectionPerformance() throws {
    guard FileManager.default.fileExists(atPath: Self.benchmarkFlagURL.path) else {
      throw XCTSkip("Run script/benchmark_migration.sh to execute selection benchmarks.")
    }
    configureSettings()
    let apps = makeApps(count: 30)
    for mode in ["cold", "disk", "memory"] {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let cache = ReleaseNotesPersistentCache(directoryURL: directory)
      let provider = ReleaseNotesProvider(persistentCache: cache)
      if mode != "cold" {
        let seeded = expectation(description: "Seed isolated cache")
        Task { @MainActor in
          for app in apps {
            let resolved = ResolvedReleaseNotes(
              content: NSAttributedString(string: "Cached notes for \(app.name)"),
              quality: .genuine, provenance: .changelog)
            if let payload = ReleaseNotesPersistentCache.payload(from: resolved) {
              await cache.store(payload, forKey: ReleaseNotesCacheKey(app: app).stableIdentifier)
            }
          }
          seeded.fulfill()
        }
        wait(for: [seeded], timeout: 10)
      }
      if mode == "memory" {
        for app in apps {
          let loaded = expectation(description: "Warm provider cache")
          provider.releaseNotes(for: app) { _ in loaded.fulfill() }
          wait(for: [loaded], timeout: 3)
        }
      }
      let model = UpdatesListViewModel(snapshot: AppListSnapshot(withApps: apps, filterQuery: nil))
      let detail = ReleaseNotesDetailViewModel(releaseNotesProvider: provider)
      let host = NSHostingView(
        rootView: ReleaseNotesDetailView(updatesViewModel: model, detailViewModel: detail))
      host.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
      let window = attachToWindow(host)
      defer { window.close() }
      let memoryBefore = residentMemoryBytes()
      var heapBefore = malloc_statistics_t()
      malloc_zone_statistics(nil, &heapBefore)
      benchmarkSamples("selection_to_render_\(mode)", values: apps) { app in
        model.select(app)
        // Drive the actual SwiftUI selection task, provider, and text view. A
        // previously rendered app's content must not satisfy this sample.
        let deadline = Date(timeIntervalSinceNow: 3)
        var rendered = false
        repeat {
          host.layoutSubtreeIfNeeded()
          host.displayIfNeeded()
          if detail.app === app, case .text(let text) = detail.contentState,
            let view = host.descendant(of: NSTextView.self), view.string == text.string,
            view.string.contains(app.name)
              || view.string.contains("app \(apps.firstIndex(where: { $0 === app })!).")
          {
            rendered = true
            break
          }
          RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        } while Date() < deadline
        XCTAssertTrue(rendered, "Selection did not render: \(mode) / \(app.name)")
        return rendered ? 1 : 0
      }
      emitMemoryLine(
        name: "selection_to_render_\(mode)", before: memoryBefore, after: residentMemoryBytes())
      var heapAfter = malloc_statistics_t()
      malloc_zone_statistics(nil, &heapAfter)
      let line =
        "MIGRATION_HEAP name=selection_to_render_\(mode) live_bytes_before=\(heapBefore.size_in_use) live_bytes_after=\(heapAfter.size_in_use) live_blocks_before=\(heapBefore.blocks_in_use) live_blocks_after=\(heapAfter.blocks_in_use)"
      FileHandle.standardError.write(Data((line + "\n").utf8))
    }
  }

  private func benchmark(
    _ name: String,
    iterations: Int,
    operation: () throws -> Int
  ) rethrows {
    try benchmarkSamples(name, values: Array(0..<iterations)) { _ in try operation() }
  }

  private func benchmarkSamples<Value>(
    _ name: String,
    values: [Value],
    operation: (Value) throws -> Int
  ) rethrows {
    var samples = [Double]()
    var checksum = 0
    for value in values {
      let start = DispatchTime.now().uptimeNanoseconds
      checksum &+= try operation(value)
      let end = DispatchTime.now().uptimeNanoseconds
      samples.append(Double(end - start) / 1_000_000)
    }

    let sorted = samples.sorted()
    emitBenchmarkLine(
      name: name,
      iterations: samples.count,
      minimum: samples.min() ?? 0,
      average: samples.reduce(0, +) / Double(max(samples.count, 1)),
      median: percentile(0.50, in: sorted),
      p95: percentile(0.95, in: sorted),
      maximum: samples.max() ?? 0,
      checksum: checksum
    )
  }

  private func percentile(_ value: Double, in sortedSamples: [Double]) -> Double {
    guard !sortedSamples.isEmpty else { return 0 }
    let index = Int((Double(sortedSamples.count - 1) * value).rounded(.up))
    return sortedSamples[index]
  }

  private func emitBenchmarkLine(
    name: String,
    iterations: Int,
    minimum: Double,
    average: Double,
    median: Double,
    p95: Double,
    maximum: Double,
    checksum: Int
  ) {
    let line = String(
      format:
        "MIGRATION_BENCHMARK name=%@ iterations=%d min_ms=%.3f avg_ms=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f checksum=%d",
      name, iterations, minimum, average, median, p95, maximum, checksum
    )
    FileHandle.standardError.write(Data((line + "\n").utf8))
  }

  private func emitMemoryLine(name: String, before: UInt64, after: UInt64) {
    let delta = Int64(bitPattern: after) - Int64(bitPattern: before)
    let line =
      "MIGRATION_MEMORY name=\(name) before_bytes=\(before) after_bytes=\(after) delta_bytes=\(delta)"
    FileHandle.standardError.write(Data((line + "\n").utf8))
  }

  private func emitConfigurationLine() {
    #if DEBUG
      let configuration = "Debug"
    #else
      let configuration = "Release"
    #endif
    let line = "MIGRATION_CONFIGURATION sidebar=appkit-parity configuration=\(configuration)"
    FileHandle.standardError.write(Data((line + "\n").utf8))
  }

  private func residentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { rebound in
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
      }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
  }

  private func configureSettings() {
    AppListSettings.shared.sortOrder = .name
    AppListSettings.shared.showInstalledUpdates = true
    AppListSettings.shared.showIgnoredUpdates = true
    AppListSettings.shared.includeUnsupportedApps = true
    AppListSettings.shared.includeAppsWithLimitedSupport = true
  }

  private func attachToWindow<Content: View>(_ host: NSHostingView<Content>) -> NSWindow {
    let window = NSWindow(
      contentRect: host.bounds,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    return window
  }

  private func makeApps(count: Int) -> [Latest.App] {
    (0..<count).map { index in
      let bundle = Latest.App.Bundle(
        version: Version(versionNumber: "1.\(index)", buildNumber: nil),
        name: "Benchmark App \(index)",
        bundleIdentifier: "com.example.migration.\(index)",
        fileURL: URL(fileURLWithPath: "/Applications/Migration-\(index).app", isDirectory: true),
        source: .appStore
      )
      let update = Latest.App.Update(
        app: bundle,
        remoteVersion: Version(versionNumber: "2.\(index)", buildNumber: nil),
        minimumOSVersion: nil,
        source: .appStore,
        date: Date(timeIntervalSince1970: 1_750_000_000 + Double(index)),
        releaseNotes: .html(
          string: "<h2>Version 2.\(index)</h2><p>Migration fixture notes for app \(index).</p>"),
        updateAction: .builtIn { _ in }
      )
      return Latest.App(bundle: bundle, update: .success(update), isIgnored: index % 17 == 0)
    }
  }

  private func makeReleaseNotesMarkup(sectionCount: Int) -> String {
    (0..<sectionCount).map { index in
      "<h2>Version \(index).0</h2><p>Improved update discovery and fixed layout issue \(index).</p>"
    }.joined(separator: "\n")
  }

  private func makeSyntheticAppRoot(count: Int) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("LatestMigrationBenchmark-\(UUID().uuidString)", isDirectory: true)
    for index in 0..<count {
      let contents =
        root
        .appendingPathComponent("Group-\(index / 20)", isDirectory: true)
        .appendingPathComponent("Migration-\(index).app/Contents", isDirectory: true)
      try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
      let info: [String: Any] = [
        "CFBundleIdentifier": "com.example.synthetic-migration.\(index)",
        "CFBundleName": "Synthetic Migration \(index)",
        "CFBundleShortVersionString": "1.\(index)",
        "CFBundleVersion": "\(index)",
      ]
      let data = try PropertyListSerialization.data(
        fromPropertyList: info, format: .binary, options: 0)
      try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
    return root
  }
}

@MainActor
private final class ImmediateReleaseNotesProvider: ReleaseNotesProviding {
  private let text: NSAttributedString

  init(text: NSAttributedString) {
    self.text = text
  }

  func releaseNotes(
    for app: Latest.App,
    with completion: @escaping ReleaseNotesProvider.Completion
  ) {
    completion(.success(text))
  }
}

extension NSView {
  fileprivate func descendant<ViewType: NSView>(of type: ViewType.Type) -> ViewType? {
    if let match = self as? ViewType { return match }
    return subviews.lazy.compactMap { $0.descendant(of: type) }.first
  }

  fileprivate func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
    let current = (self as? ViewType).map { [$0] } ?? []
    return current + subviews.flatMap { $0.descendants(of: type) }
  }
}
