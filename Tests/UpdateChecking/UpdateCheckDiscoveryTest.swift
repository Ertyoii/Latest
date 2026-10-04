//
//  UpdateQueueTest.swift
//  Latest Tests
//
//  Created by ertyoii on 28.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-05-28.
//  Licensed under GPL-3.0; see LICENSE.md.

import Combine
import Synchronization
import XCTest

@testable import Latest

@MainActor
final class UpdateCheckDiscoveryTest: XCTestCase {
  func testScanPublishesSettledRowsAndKeepsPreviousListDuringRefresh() async throws {
    let initialStarted = expectation(description: "Initial checks started")
    initialStarted.expectedFulfillmentCount = 2
    let refreshStarted = expectation(description: "Refresh checks started")
    refreshStarted.expectedFulfillmentCount = 2
    let startedCount = Mutex(0)
    let checks = SuspendedDiscoveryChecks { _ in
      let count = startedCount.withLock {
        $0 += 1
        return $0
      }
      (count <= 2 ? initialStarted : refreshStarted).fulfill()
    }
    let coordinator = UpdateCheckCoordinator(
      check: { bundle, _ in try await checks.check(bundle) }, repositoryProvider: { nil })
    let settings = try isolatedAppListSettings(for: self)
    let model = UpdatesListViewModel(settings: settings, appProvider: coordinator.appProvider)
    var publishedRows = [[String]]()
    var prematureRows = expectation(description: "No provisional rows during startup")
    prematureRows.isInverted = true
    var settledRows = expectation(description: "Settled startup order")
    var isChecking = true
    let observation = model.$snapshot.sink { snapshot in
      let names = snapshot.sections.flatMap(\.apps).map(\.name)
      guard !names.isEmpty else { return }
      publishedRows.append(names)
      if isChecking {
        prematureRows.fulfill()
      } else {
        settledRows.fulfill()
      }
    }
    defer {
      observation.cancel()
      model.stopObserving()
    }
    model.startObserving()
    let bundles = [bundle("A"), bundle("B")]
    coordinator.updateDiscoveredBundles(bundles)
    await fulfillment(of: [initialStarted], timeout: 2)
    await checks.complete("A", remoteVersion: "1", date: Date(timeIntervalSince1970: 10))
    // Give the store's coalesced publication time to expose any provisional rows.
    await fulfillment(of: [prematureRows], timeout: 0.35)
    XCTAssertTrue(model.snapshot.entries.isEmpty)
    XCTAssertNil(model.selectedApp)

    isChecking = false
    await checks.complete("B", remoteVersion: "1", date: Date(timeIntervalSince1970: 20))
    await fulfillment(of: [settledRows], timeout: 2)
    XCTAssertEqual(publishedRows, [["B", "A"]])
    XCTAssertEqual(model.selectedApp?.name, "B")
    let selected = try XCTUnwrap(model.snapshot.apps.first { $0.name == "A" })
    model.select(selected)

    prematureRows = expectation(description: "No partial rows during refresh")
    prematureRows.isInverted = true
    settledRows = expectation(description: "Settled refresh order")
    isChecking = true
    coordinator.updateDiscoveredBundles(bundles, forceRefresh: true)
    await fulfillment(of: [refreshStarted], timeout: 2)
    await checks.complete("A")
    await fulfillment(of: [prematureRows], timeout: 0.35)
    XCTAssertEqual(model.snapshot.sections.flatMap(\.apps).map(\.name), ["B", "A"])
    XCTAssertTrue(model.selectedApp === selected)
    // A view subscribing in the middle of a scan must also see the last settled state.
    var iterator = coordinator.appProvider.updates().makeAsyncIterator()
    let currentApps = await iterator.next()
    let current = try XCTUnwrap(currentApps)
    XCTAssertEqual(current.first { $0.name == "A" }?.remoteVersion?.versionNumber, "1")

    isChecking = false
    await checks.fail("B")
    await fulfillment(of: [settledRows], timeout: 2)
    XCTAssertEqual(publishedRows, [["B", "A"], ["A", "B"]])
    XCTAssertEqual(model.selectedApp?.identifier, selected.identifier)
    XCTAssertEqual(model.selectedApp?.remoteVersion?.versionNumber, "3")
    XCTAssertNotNil(model.snapshot.apps.first { $0.name == "B" }?.error)
  }

  func testUnchangedDiscoveryKeepsPendingChecks() async {
    let started = expectation(description: "Both checks started")
    started.expectedFulfillmentCount = 2
    let checks = SuspendedDiscoveryChecks { _ in started.fulfill() }
    let coordinator = UpdateCheckCoordinator(
      check: { bundle, _ in try await checks.check(bundle) },
      repositoryProvider: {
        XCTFail("Sparkle-only scans must not load the Homebrew catalog")
        return nil
      })
    let progress = DiscoveryCheckProgress(finished: expectation(description: "Scan finished"))
    coordinator.progressDelegate = progress
    let bundles = [bundle("A"), bundle("B")]

    coordinator.updateDiscoveredBundles(bundles)
    await fulfillment(of: [started], timeout: 2)
    coordinator.updateDiscoveredBundles([bundle("B"), bundle("A")])
    await checks.completeAll()
    await fulfillment(of: [progress.finished], timeout: 2)

    XCTAssertEqual(
      Set(coordinator.appProvider.updatableApps.map(\.identifier)), Set(bundles.map(\.identifier)))
    XCTAssertEqual(progress.checked.count, 2)
    XCTAssertEqual(progress.batchSizes, [2])
  }

  func testChangedDiscoveryRechecksRetainedAppsAndRejectsRemovedResults() async {
    let initialStarted = expectation(description: "Initial checks started")
    initialStarted.expectedFulfillmentCount = 3
    let replacementStarted = expectation(description: "Changed and retained apps rechecked")
    replacementStarted.expectedFulfillmentCount = 2
    let startedCount = Mutex(0)
    let checks = SuspendedDiscoveryChecks { _ in
      let count = startedCount.withLock {
        $0 += 1
        return $0
      }
      (count <= 3 ? initialStarted : replacementStarted).fulfill()
    }
    let coordinator = UpdateCheckCoordinator(
      check: { bundle, _ in try await checks.check(bundle) }, repositoryProvider: { nil })
    let progress = DiscoveryCheckProgress(
      finished: expectation(description: "Replacement scan finished"))
    coordinator.progressDelegate = progress
    let prematurePublication = expectation(description: "Cancelled scan cannot publish rows")
    prematurePublication.isInverted = true
    let settledPublication = expectation(description: "Replacement rows published")
    let isChecking = Mutex(true)
    var publishedApps = [App]()
    let stream = coordinator.appProvider.updates()
    let observation = Task {
      for await apps in stream {
        guard !apps.isEmpty else { continue }
        publishedApps = apps
        if isChecking.withLock({ $0 }) {
          prematurePublication.fulfill()
        } else {
          settledPublication.fulfill()
        }
      }
    }
    defer { observation.cancel() }

    coordinator.updateDiscoveredBundles([bundle("A"), bundle("B"), bundle("Removed")])
    await fulfillment(of: [initialStarted], timeout: 2)
    let replacement = [bundle("A", version: "2"), bundle("B")]
    coordinator.updateDiscoveredBundles(replacement)
    await fulfillment(of: [replacementStarted], timeout: 2)
    // Finish the cancelled generation while the replacement checks are still pending.
    await checks.complete("A")
    await checks.complete("B")
    await checks.complete("Removed")
    await fulfillment(of: [prematurePublication], timeout: 0.35)
    isChecking.withLock { $0 = false }
    await checks.completeAll()
    await fulfillment(of: [progress.finished, settledPublication], timeout: 2)

    let apps = coordinator.appProvider.updatableApps
    XCTAssertEqual(Set(apps.map(\.identifier)), Set(replacement.map(\.identifier)))
    XCTAssertEqual(apps.first { $0.name == "A" }?.version.versionNumber, "2")
    XCTAssertEqual(progress.batchSizes, [3, 2])
    XCTAssertEqual(progress.checked.count, 2)
    XCTAssertEqual(Set(publishedApps.map(\.identifier)), Set(replacement.map(\.identifier)))
  }

  private func bundle(_ name: String, version: String = "1") -> App.Bundle {
    App.Bundle(
      version: Version(versionNumber: version, buildNumber: nil), name: name,
      bundleIdentifier: "test.discovery.\(name)", fileURL: URL(fileURLWithPath: "/tmp/\(name).app"),
      source: .sparkle, modificationDate: .distantPast)
  }
}

private actor SuspendedDiscoveryChecks {
  private let started: @Sendable (App.Bundle) -> Void
  private var pending = [(App.Bundle, CheckedContinuation<App.Update, Error>)]()

  init(started: @escaping @Sendable (App.Bundle) -> Void) {
    self.started = started
  }

  func check(_ bundle: App.Bundle) async throws -> App.Update {
    try await withCheckedThrowingContinuation { continuation in
      pending.append((bundle, continuation))
      started(bundle)
    }
  }

  func completeAll() {
    while let (bundle, _) = pending.first {
      complete(bundle.name)
    }
  }

  func complete(_ name: String, remoteVersion: String = "3", date: Date? = nil) {
    guard let index = pending.firstIndex(where: { $0.0.name == name }) else { return }
    let (bundle, continuation) = pending.remove(at: index)
    continuation.resume(
      returning: App.Update(
        app: bundle, remoteVersion: Version(versionNumber: remoteVersion, buildNumber: nil),
        minimumOSVersion: nil, source: .sparkle, date: date, releaseNotes: nil,
        updateAction: .builtIn { _ in }))
  }

  func fail(_ name: String) {
    guard let index = pending.firstIndex(where: { $0.0.name == name }) else { return }
    let (_, continuation) = pending.remove(at: index)
    continuation.resume(throwing: LatestError.updateInfoUnavailable)
  }
}

@MainActor
private final class DiscoveryCheckProgress: UpdateCheckProgressReporting {
  let finished: XCTestExpectation
  var checked = [App]()
  var batchSizes = [Int]()

  init(finished: XCTestExpectation) { self.finished = finished }
  func updateCheckerDidStartScanningForApps(_ updateChecker: UpdateCheckCoordinator) {}
  func updateChecker(
    _ updateChecker: UpdateCheckCoordinator, didStartCheckingApps count: Int, generation: Int
  ) {
    batchSizes.append(count)
  }
  func updateChecker(_ updateChecker: UpdateCheckCoordinator, didCheckApp app: App) {
    checked.append(app)
  }
  func updateCheckerDidFinishCheckingForUpdates(
    _ updateChecker: UpdateCheckCoordinator, generation: Int
  ) {
    finished.fulfill()
  }
}
