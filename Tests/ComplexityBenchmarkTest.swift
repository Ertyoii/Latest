//
//  ComplexityBenchmarkTest.swift
//  Latest Tests
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation
import XCTest
@testable import Latest

@MainActor
final class ComplexityBenchmarkTest: XCTestCase {

	func testComplexityBenchmarks() throws {
		guard FileManager.default.fileExists(atPath: Self.benchmarkFlagURL.path) else {
			throw XCTSkip("Run script/benchmark_complexity.sh to execute complexity benchmarks.")
		}

		configureSettings()

		let dataStoreBundles = makeBundles(count: 2_000)
		let snapshotApps = makeApps(count: 1_500)
		let lookupApps = Array(snapshotApps.prefix(400))
		let versionPairs = makeVersionPairs(count: 80_000)
		let repositoryEntries = try makeRepositoryEntries(count: 3_000)
		let repositoryCandidateGroups = makeRepositoryCandidateGroups(from: repositoryEntries)
		let bundleCollectionRoot = try makeBundleCollectionRoot(appCount: 250, fillerDirectoryCount: 250)
		defer { try? FileManager.default.removeItem(at: bundleCollectionRoot) }

		benchmark("app_data_store_update_batch", iterations: 5) {
			let store = AppDataStore()
			_ = store.set(appBundles: Set(dataStoreBundles))

			var checksum = 0
			for index in stride(from: 0, to: dataStoreBundles.count, by: 2) {
				let bundle = dataStoreBundles[index]
				let remoteVersion = Version(versionNumber: "2.\(index)", buildNumber: nil)
				let app = store.set(.success(makeUpdate(for: bundle, remoteVersion: remoteVersion)), for: bundle)
				if app.updateAvailable {
					checksum &+= 1
				}
			}

			return checksum
		}

		benchmark("app_list_snapshot_build_and_lookup", iterations: 7) {
			let snapshot = AppListSnapshot(withApps: snapshotApps, filterQuery: nil)
			var checksum = snapshot.entries.count
			for app in lookupApps {
				checksum &+= snapshot.firstIndex(of: app) ?? 0
			}
			return checksum
		}

		benchmark("version_comparison_repeated_parse", iterations: 7) {
			var checksum = 0
			for pair in versionPairs {
				if pair.local < pair.remote {
					checksum &+= 1
				}
			}
			return checksum
		}

		benchmark("update_repository_entry_metadata_and_matching", iterations: 5) {
			var checksum = 0
			for entry in repositoryEntries {
				checksum &+= entry.version.versionNumber?.count ?? 0
				if entry.releaseNotes != nil {
					checksum &+= 1
				}
			}

			for group in repositoryCandidateGroups {
				checksum &+= UpdateRepository.preferredEntry(from: group.entries, for: group.bundleIdentifier)?.token.count ?? 0
			}

			return checksum
		}

		benchmark("bundle_collection_path_filtering", iterations: 5) {
			BundleCollector.collectBundles(at: bundleCollectionRoot).count
		}
	}

	private static var benchmarkFlagURL: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("build/run-complexity-benchmarks", isDirectory: false)
	}

	private func benchmark(_ name: String, iterations: Int, block: () throws -> Int) rethrows {
		var samples = [Double]()
		var checksum = 0

		for _ in 0..<iterations {
			let start = DispatchTime.now().uptimeNanoseconds
			checksum &+= try block()
			let end = DispatchTime.now().uptimeNanoseconds
			samples.append(Double(end - start) / 1_000_000)
		}

		let minSample = samples.min() ?? 0
		let maxSample = samples.max() ?? 0
		let average = samples.reduce(0, +) / Double(samples.count)
		emitBenchmarkLine(
			name: name,
			iterations: iterations,
			minimum: minSample,
			average: average,
			maximum: maxSample,
			checksum: checksum
		)
	}

	private func emitBenchmarkLine(
		name: String,
		iterations: Int,
		minimum: Double,
		average: Double,
		maximum: Double,
		checksum: Int
	) {
		let line = String(
			format: "BENCHMARK name=%@ iterations=%d min_ms=%.3f avg_ms=%.3f max_ms=%.3f checksum=%d",
			name,
			iterations,
			minimum,
			average,
			maximum,
			checksum
		)
		FileHandle.standardError.write(Data((line + "\n").utf8))
	}

	private func configureSettings() {
		AppListSettings.shared.sortOrder = .name
		AppListSettings.shared.showInstalledUpdates = true
		AppListSettings.shared.showIgnoredUpdates = true
		AppListSettings.shared.includeUnsupportedApps = true
		AppListSettings.shared.includeAppsWithLimitedSupport = true
	}

	private func makeBundles(count: Int) -> [App.Bundle] {
		(0..<count).map { index in
			App.Bundle(
				version: Version(versionNumber: "1.\(index)", buildNumber: "\(index)"),
				name: "Benchmark App \(index)",
				bundleIdentifier: "com.example.benchmark.\(index)",
				fileURL: URL(fileURLWithPath: "/Applications/Benchmark-\(index).app", isDirectory: true),
				source: .sparkle
			)
		}
	}

	private func makeApps(count: Int) -> [App] {
		makeBundles(count: count).enumerated().map { index, bundle in
			let update: Result<App.Update, Error>?
			if index % 3 == 0 {
				update = .success(makeUpdate(for: bundle, remoteVersion: Version(versionNumber: "2.\(index)", buildNumber: nil)))
			} else {
				update = nil
			}

			return App(bundle: bundle, update: update, isIgnored: index % 17 == 0)
		}
	}

	private func makeUpdate(for bundle: App.Bundle, remoteVersion: Version) -> App.Update {
		App.Update(
			app: bundle,
			remoteVersion: remoteVersion,
			minimumOSVersion: nil,
			source: .sparkle,
			date: nil,
			releaseNotes: nil,
			updateAction: .external(label: "Benchmark") { _ in }
		)
	}

	private func makeVersionPairs(count: Int) -> [(local: Version, remote: Version)] {
		(0..<count).map { index in
			let major = index % 10
			let minor = (index / 10) % 50
			let patch = (index / 500) % 20
			return (
				local: Version(versionNumber: "\(major).\(minor).\(patch)-stable.\(index)", buildNumber: "\(index)"),
				remote: Version(versionNumber: "\(major).\(minor).\(patch + 1)-stable.\(index + 10)", buildNumber: "\(index + 10)")
			)
		}
	}

	private func makeRepositoryEntries(count: Int) throws -> [UpdateRepository.Entry] {
		let objects: [[String: Any]] = (0..<count).map { index in
			let group = index / 3
			let channel = index % 3
			let token: String
			switch channel {
			case 1:
				token = "repo-benchmark-\(group)@beta"
			case 2:
				token = "repo-benchmark-\(group)-for-it-admins"
			default:
				token = "repo-benchmark-\(group)"
			}

			let appName = "Repo Benchmark \(group).app"
			let bundleIdentifier = "com.example.repository.\(group)"
			return [
				"token": token,
				"version": "\(group % 20).\(index % 50).\(index % 9),\(index)",
				"name": ["Repo Benchmark \(group)"],
				"homepage": "https://example.com/repo-\(group)",
				"url": "https://example.com/repo-\(group).zip",
				"desc": "Repository benchmark entry \(index) with metadata.",
				"artifacts": [
					[
						"app": [appName],
						"uninstall": [
							[
								"quit": bundleIdentifier
							]
						]
					]
				],
				"depends_on": [
					"macos": [:]
				]
			]
		}

		let data = try JSONSerialization.data(withJSONObject: objects)
		return try JSONDecoder().decode([UpdateRepository.Entry].self, from: data)
	}

	private func makeRepositoryCandidateGroups(
		from entries: [UpdateRepository.Entry]
	) -> [(bundleIdentifier: String, entries: [UpdateRepository.Entry])] {
		stride(from: 0, to: entries.count - 2, by: 3).map { index in
			(
				bundleIdentifier: "com.example.repository.\(index / 3)",
				entries: Array(entries[index..<(index + 3)])
			)
		}
	}

	private func makeBundleCollectionRoot(appCount: Int, fillerDirectoryCount: Int) throws -> URL {
		let fileManager = FileManager.default
		let rootURL = fileManager.temporaryDirectory
			.appendingPathComponent("LatestComplexityBenchmark-\(UUID().uuidString)", isDirectory: true)
		try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

		for index in 0..<fillerDirectoryCount {
			let directoryURL = rootURL
				.appendingPathComponent("Nested-\(index / 20)", isDirectory: true)
				.appendingPathComponent("Folder-\(index)", isDirectory: true)
			try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
		}

		let setappURL = rootURL.appendingPathComponent("Setapp", isDirectory: true)
		try fileManager.createDirectory(at: setappURL, withIntermediateDirectories: true)
		for index in 0..<50 {
			try makeSyntheticApp(
				at: setappURL.appendingPathComponent("Excluded-\(index).app", isDirectory: true),
				index: index
			)
		}

		for index in 0..<appCount {
			let parentURL = rootURL.appendingPathComponent("Apps-\(index / 25)", isDirectory: true)
			try makeSyntheticApp(
				at: parentURL.appendingPathComponent("Benchmark-\(index).app", isDirectory: true),
				index: index
			)
		}

		return rootURL
	}

	private func makeSyntheticApp(at appURL: URL, index: Int) throws {
		let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
		try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
		let infoPlist: [String: Any] = [
			"CFBundleIdentifier": "com.example.synthetic.\(index)",
			"CFBundleName": "Synthetic \(index)",
			"CFBundleShortVersionString": "1.\(index)",
			"CFBundleVersion": "\(index)"
		]
		let data = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
		try data.write(to: contentsURL.appendingPathComponent("Info.plist", isDirectory: false))
	}

}
