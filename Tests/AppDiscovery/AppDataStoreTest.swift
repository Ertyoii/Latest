//
//  AppDataStoreTest.swift
//  Latest Tests
//
//  Created by ertyoii on 19.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-05-20.
//  Licensed under GPL-3.0; see LICENSE.md.

import Synchronization
import XCTest

@testable import Latest

final class AppDataStoreTest: XCTestCase {
  @MainActor
  func testUpdateStreamYieldsInitialAndCoalescedState() async {
    let store = AppDataStore()
    var iterator = store.updates().makeAsyncIterator()

    let initialApps = await iterator.next()
    XCTAssertEqual(initialApps?.count, 0)

    let appURL = URL(
      fileURLWithPath: "/Applications/Stream-\(UUID().uuidString).app", isDirectory: true)
    let bundle = makeBundle(versionNumber: "1.0", at: appURL)
    _ = store.set(appBundle: bundle)

    let updatedApps = await iterator.next()

    XCTAssertEqual(updatedApps?.map(\.identifier), [bundle.identifier])
  }

  func testSingleBundleRefreshPreservesUpdateState() {
    let store = AppDataStore()
    let appURL = URL(
      fileURLWithPath: "/Applications/Indexed-\(UUID().uuidString).app", isDirectory: true)
    let initialBundle = makeBundle(versionNumber: "1.0", at: appURL)
    let remoteVersion = Version(versionNumber: "2.0", buildNumber: nil)

    _ = store.set(appBundles: [initialBundle])
    _ = store.set(
      .success(makeUpdate(for: initialBundle, remoteVersion: remoteVersion)), for: initialBundle)

    let refreshedBundle = makeBundle(versionNumber: "1.1", at: appURL)
    let refreshedApp = store.set(appBundle: refreshedBundle)

    XCTAssertEqual(refreshedApp.version.versionNumber, "1.1")
    XCTAssertEqual(refreshedApp.remoteVersion, remoteVersion)
  }

  func testSingleBundleRefreshClearsAvailableStateWhenInstalledVersionCatchesUp() {
    let store = AppDataStore()
    let appURL = URL(
      fileURLWithPath: "/Applications/Updated-\(UUID().uuidString).app", isDirectory: true)
    let initialBundle = makeBundle(versionNumber: "1.0", at: appURL)
    let remoteVersion = Version(versionNumber: "2.0", buildNumber: nil)

    _ = store.set(appBundles: [initialBundle])
    let availableApp = store.set(
      .success(makeUpdate(for: initialBundle, remoteVersion: remoteVersion)),
      for: initialBundle
    )
    XCTAssertTrue(availableApp.updateAvailable)

    let installedBundle = makeBundle(versionNumber: "2.0", at: appURL)
    let installedApp = store.set(appBundle: installedBundle)

    XCTAssertEqual(installedApp.version, remoteVersion)
    XCTAssertEqual(installedApp.remoteVersion, remoteVersion)
    XCTAssertFalse(installedApp.updateAvailable)
  }

  func testIgnoredIdentifiersAreCachedAndPersistedWithAppState() throws {
    let suiteName = "AppDataStoreTest.\(UUID().uuidString)"
    let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    let store = AppDataStore(userDefaults: userDefaults)
    let appURL = URL(
      fileURLWithPath: "/Applications/Ignored-\(UUID().uuidString).app", isDirectory: true)
    let initialBundle = makeBundle(versionNumber: "1.0", at: appURL)
    let app = store.set(appBundle: initialBundle)

    store.setIgnoredState(true, for: app)

    let refreshedBundle = makeBundle(versionNumber: "1.1", at: appURL)
    XCTAssertTrue(store.set(appBundle: refreshedBundle).isIgnored)
    XCTAssertEqual(
      Set(userDefaults.stringArray(forKey: "IgnoredAppsKey") ?? []),
      Set([initialBundle.bundleIdentifier])
    )
  }

  private func makeBundle(versionNumber: String, at url: URL) -> App.Bundle {
    App.Bundle(
      version: Version(versionNumber: versionNumber, buildNumber: nil),
      name: "Indexed",
      bundleIdentifier: "com.example.indexed.\(url.deletingPathExtension().lastPathComponent)",
      fileURL: url,
      source: .sparkle
    )
  }

  private func makeUpdate(for bundle: App.Bundle, remoteVersion: Version) -> App.Update {
    App.Update(
      app: bundle,
      remoteVersion: remoteVersion,
      minimumOSVersion: nil,
      source: .sparkle,
      date: nil,
      releaseNotes: nil,
      updateAction: .external(label: "Test") { _ in }
    )
  }

}

final class AppDirectoryTest: XCTestCase {
  func testProcessWideCollectionCoordinatorCoalescesSameDirectory() {
    let collectionStarted = DispatchSemaphore(value: 0)
    let allowCollectionToFinish = DispatchSemaphore(value: 0)
    let waiterJoined = DispatchSemaphore(value: 0)
    let invocationCount = Mutex(0)
    let coordinator = BundleCollectionCoordinator(
      collector: { _ in
        invocationCount.withLock { $0 += 1 }
        collectionStarted.signal()
        allowCollectionToFinish.wait()
        return []
      },
      waiterDidJoin: {
        waiterJoined.signal()
      }
    )
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let callersFinished = expectation(description: "Coalesced callers finished")
    callersFinished.expectedFulfillmentCount = 2

    DispatchQueue.global(qos: .userInitiated).async {
      _ = coordinator.collectBundles(at: directoryURL)
      callersFinished.fulfill()
    }

    XCTAssertEqual(collectionStarted.wait(timeout: .now() + 1), .success)
    DispatchQueue.global(qos: .userInitiated).async {
      _ = coordinator.collectBundles(at: directoryURL)
      callersFinished.fulfill()
    }
    XCTAssertEqual(waiterJoined.wait(timeout: .now() + 1), .success)
    allowCollectionToFinish.signal()
    wait(for: [callersFinished], timeout: 2)
    XCTAssertEqual(invocationCount.withLock { $0 }, 1)
  }

  func testRefreshRecollectsBundleVersionFromDisk() throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let appURL = directoryURL.appendingPathComponent("Refreshable.app", isDirectory: true)
    try writeAppBundle(at: appURL, versionNumber: "1.0")

    let initialCollection = expectation(description: "Initial collection")
    let directory = AppDirectory(url: directoryURL) {
      initialCollection.fulfill()
    }
    wait(for: [initialCollection], timeout: 2)

    XCTAssertEqual(directory.bundles.first?.version.versionNumber, "1.0")
    XCTAssertEqual(BundleCollector.cachedBundleCount(at: directoryURL), 1)

    try writeAppBundle(at: appURL, versionNumber: "1.1")

    let refreshedCollection = expectation(description: "Refreshed collection")
    directory.refresh {
      refreshedCollection.fulfill()
    }
    wait(for: [refreshedCollection], timeout: 2)

    XCTAssertEqual(directory.bundles.first?.version.versionNumber, "1.1")
  }

  func testInitialCollectionCanCompleteWithoutCallingUpdateHandler() throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    try writeAppBundle(
      at: directoryURL.appendingPathComponent("Initial.app", isDirectory: true),
      versionNumber: "1.0")

    let initialCollection = expectation(description: "Initial collection")
    let updateHandler = expectation(description: "Update handler")
    updateHandler.isInverted = true

    let directory = AppDirectory(
      url: directoryURL,
      notifyOnInitialCollection: false,
      initialCollectionCompletion: {
        initialCollection.fulfill()
      }
    ) {
      updateHandler.fulfill()
    }

    wait(for: [initialCollection, updateHandler], timeout: 1)

    XCTAssertEqual(directory.bundles.first?.version.versionNumber, "1.0")
  }

  func testRefreshBurstCoalescesIntoSingleTrailingCollection() throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let probe = AppDirectoryCollectionProbe()
    let directory = AppDirectory(
      url: directoryURL,
      notifyOnInitialCollection: false,
      bundleCollector: { probe.collect(at: $0) },
      updateHandler: {}
    )

    XCTAssertEqual(probe.firstCollectionStarted.wait(timeout: .now() + 1), .success)

    let refreshesCompleted = expectation(description: "Coalesced refreshes completed")
    refreshesCompleted.expectedFulfillmentCount = 10
    for _ in 0..<10 {
      directory.refresh {
        refreshesCompleted.fulfill()
      }
    }

    probe.allowFirstCollectionToFinish.signal()
    wait(for: [refreshesCompleted], timeout: 2)

    XCTAssertEqual(probe.invocationCount, 2)
    withExtendedLifetime(directory) {}
  }

  private func writeAppBundle(at url: URL, versionNumber: String) throws {
    let contentsURL = url.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

    let information: [String: Any] = [
      "CFBundleIdentifier": "com.example.refreshable",
      "CFBundleName": "Refreshable",
      "CFBundleShortVersionString": versionNumber,
      "CFBundleVersion": "1",
      "SUFeedURL": "https://example.com/appcast.xml",
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: information, format: .xml, options: 0)
    try data.write(to: contentsURL.appendingPathComponent("Info.plist"), options: .atomic)
  }

}

private final class AppDirectoryCollectionProbe: Sendable {
  let firstCollectionStarted = DispatchSemaphore(value: 0)
  let allowFirstCollectionToFinish = DispatchSemaphore(value: 0)

  private let invocationCountStorage = Mutex(0)

  var invocationCount: Int {
    invocationCountStorage.withLock { $0 }
  }

  func collect(at url: URL) -> [App.Bundle] {
    let invocation = invocationCountStorage.withLock { invocationCount in
      invocationCount += 1
      return invocationCount
    }

    if invocation == 1 {
      firstCollectionStarted.signal()
      allowFirstCollectionToFinish.wait()
    }

    return []
  }
}

extension AppDataStoreTest {
  func testConcurrentSnapshotsAndMutationsPreserveEveryApp() {
    let store = AppDataStore()
    let bundles = (0..<200).map { index in
      makeBundle(versionNumber: "1.0", at: URL(fileURLWithPath: "/tmp/Concurrent-\(index).app"))
    }
    DispatchQueue.concurrentPerform(iterations: bundles.count) { index in
      _ = store.set(appBundle: bundles[index])
      _ = store.apps
      _ = store.updatableApps
    }
    XCTAssertEqual(Set(store.apps.map(\.identifier)), Set(bundles.map(\.identifier)))
  }

  func testCountPredicateCanReadStoreWithoutDeadlocking() {
    let store = AppDataStore()
    let bundle = makeBundle(versionNumber: "1.0", at: URL(fileURLWithPath: "/tmp/Reentrant.app"))
    _ = store.set(
      .success(
        makeUpdate(for: bundle, remoteVersion: Version(versionNumber: "2.0", buildNumber: nil))),
      for: bundle)
    XCTAssertEqual(
      store.countOfAvailableUpdates { app in
        store.apps.contains(app)
      }, 1)
  }
}
