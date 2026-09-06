//
//  BundleCollectorTest.swift
//  Latest Tests
//
//  Structural split from the original implementation.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-29.
//  Licensed under GPL-3.0; see LICENSE.md.

import XCTest

@testable import Latest

final class BundleCollectorTest: XCTestCase {
  func testRenamedCodexBundleUsesCatalogedSparkleSource() throws {
    let directory = try makeTemporaryDirectory()
    let appURL = try makeAppBundle(
      named: "ChatGPT",
      in: directory,
      info: [
        "CFBundleName": "ChatGPT",
        "CFBundleExecutable": "ChatGPT",
        "CFBundleIdentifier": "com.openai.codex",
        "CFBundleShortVersionString": "26.707.51957",
        "CFBundleVersion": "5175",
      ]
    )

    let bundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

    XCTAssertEqual(bundle.source, .sparkle)
  }

  func testCollectsAppUsingDisplayNameWhenBundleNameIsMissing() throws {
    let directory = try makeTemporaryDirectory()
    let appURL = try makeAppBundle(
      named: "Display Name Only",
      in: directory,
      info: [
        "CFBundleDisplayName": "Display Name Only",
        "CFBundleExecutable": "Display Name Only",
        "CFBundleIdentifier": "com.example.display-name-only",
        "CFBundleShortVersionString": "1.2.3",
        "CFBundleVersion": "123",
      ]
    )

    let bundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

    XCTAssertEqual(bundle.name, "Display Name Only")
  }

  func testCollectsAppUsingBuildVersionWhenShortVersionIsMissing() throws {
    let directory = try makeTemporaryDirectory()
    let appURL = try makeAppBundle(
      named: "Build Version Only",
      in: directory,
      info: [
        "CFBundleName": "Build Version Only",
        "CFBundleExecutable": "Build Version Only",
        "CFBundleIdentifier": "com.example.build-version-only",
        "CFBundleVersion": "456",
      ]
    )

    let bundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

    XCTAssertEqual(bundle.version.buildNumber, "456")
    XCTAssertNil(bundle.version.versionNumber)
  }

  func testBundleModificationDateUsesContentsWhenPackageRootHasArchiveTimestamp() throws {
    let directory = try makeTemporaryDirectory()
    let appURL = try makeAppBundle(
      named: "Archive Timestamp",
      in: directory,
      info: [
        "CFBundleName": "Archive Timestamp",
        "CFBundleExecutable": "Archive Timestamp",
        "CFBundleIdentifier": "com.example.archive-timestamp",
        "CFBundleVersion": "1",
      ]
    )
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
    let archiveTimestamp = Date(timeIntervalSince1970: 315_504_000)
    let contentsTimestamp = Date(timeIntervalSince1970: 1_778_179_586)

    try setModificationDate(archiveTimestamp, for: appURL)
    try setModificationDate(contentsTimestamp, for: contentsURL)
    try setModificationDate(contentsTimestamp, for: infoPlistURL)

    let bundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

    XCTAssertEqual(bundle.modificationDate, contentsTimestamp)
  }

  func testCollectingUpdatedBundleReadsCurrentInfoPlistVersions() throws {
    let directory = try makeTemporaryDirectory()
    let appURL = try makeAppBundle(
      named: "Updated In Place",
      in: directory,
      info: [
        "CFBundleName": "Updated In Place",
        "CFBundleExecutable": "Updated In Place",
        "CFBundleIdentifier": "com.example.updated-in-place",
        "CFBundleShortVersionString": "1.2.3",
        "CFBundleVersion": "123",
      ]
    )

    let oldBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))
    XCTAssertEqual(oldBundle.version.versionNumber, "1.2.3")
    XCTAssertEqual(oldBundle.version.buildNumber, "123")

    try writeInfoPlist(
      forAppAt: appURL,
      info: [
        "CFBundleName": "Updated In Place",
        "CFBundleExecutable": "Updated In Place",
        "CFBundleIdentifier": "com.example.updated-in-place",
        "CFBundleShortVersionString": "1.2.5",
        "CFBundleVersion": "125",
      ]
    )

    let updatedBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))
    XCTAssertEqual(updatedBundle.version.versionNumber, "1.2.5")
    XCTAssertEqual(updatedBundle.version.buildNumber, "125")
  }

  func testCollectingUnchangedBundleReusesCachedMetadata() throws {
    let directory = try makeTemporaryDirectory()
    let appURL = try makeAppBundle(
      named: "Cached In Place",
      in: directory,
      info: [
        "CFBundleName": "Cached In Place",
        "CFBundleExecutable": "Cached In Place",
        "CFBundleIdentifier": "com.example.cached-in-place",
        "CFBundleShortVersionString": "1.2.3",
        "CFBundleVersion": "123",
      ]
    )

    let firstBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))
    let secondBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

    XCTAssertTrue(firstBundle === secondBundle)
  }

  func testCollectingBundleWithUpdatedModificationDateRefreshesCachedMetadata() throws {
    let directory = try makeTemporaryDirectory()
    let appURL = try makeAppBundle(
      named: "Updated Metadata",
      in: directory,
      info: [
        "CFBundleName": "Updated Metadata",
        "CFBundleExecutable": "Updated Metadata",
        "CFBundleIdentifier": "com.example.updated-metadata",
        "CFBundleShortVersionString": "1.2.3",
        "CFBundleVersion": "123",
      ]
    )

    let firstBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))
    let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    let newerTimestamp = Date(
      timeIntervalSince1970: floor(firstBundle.modificationDate.timeIntervalSince1970) + 60)
    try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
    try setModificationDate(newerTimestamp, for: resourcesURL)

    let updatedBundle = try XCTUnwrap(BundleCollector.collectBundle(at: appURL))

    XCTAssertFalse(firstBundle === updatedBundle)
    XCTAssertEqual(
      updatedBundle.modificationDate.timeIntervalSince1970, newerTimestamp.timeIntervalSince1970,
      accuracy: 0.001)
  }

  func testCollectBundlesSkipsAppsInsideExcludedSubfolders() throws {
    let directory = try makeTemporaryDirectory()
    let excludedDirectory = directory.appendingPathComponent("Setapp", isDirectory: true)

    _ = try makeAppBundle(
      named: "Excluded App",
      in: excludedDirectory,
      info: [
        "CFBundleName": "Excluded App",
        "CFBundleExecutable": "Excluded App",
        "CFBundleIdentifier": "com.example.excluded-app",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "100",
      ]
    )
    _ = try makeAppBundle(
      named: "Visible App",
      in: directory,
      info: [
        "CFBundleName": "Visible App",
        "CFBundleExecutable": "Visible App",
        "CFBundleIdentifier": "com.example.visible-app",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "100",
      ]
    )

    let bundles = BundleCollector.collectBundles(at: directory)

    XCTAssertEqual(Set(bundles.map(\.name)), ["Visible App"])
  }

  func testSystemApplicationsAreExcludedFromDiscovery() {
    XCTAssertFalse(
      BundleCollector.shouldIncludeApplication(
        at: URL(fileURLWithPath: "/System/Applications/Notes.app", isDirectory: true)
      ))
    XCTAssertFalse(
      BundleCollector.shouldIncludeApplication(
        at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)
      ))
    XCTAssertTrue(
      BundleCollector.shouldIncludeApplication(
        at: URL(fileURLWithPath: "/Applications/Third Party.app", isDirectory: true)
      ))
  }

}

extension BundleCollectorTest {
  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directory)
    }
    return directory
  }

  private func makeAppBundle(named name: String, in directory: URL, info: [String: String]) throws
    -> URL
  {
    let appURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)

    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
    try writeInfoPlist(forAppAt: appURL, info: info)

    return appURL
  }

  private func writeInfoPlist(forAppAt appURL: URL, info: [String: String]) throws {
    let plistURL = appURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: plistURL)
  }

  private func setModificationDate(_ date: Date, for url: URL) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
  }

}
