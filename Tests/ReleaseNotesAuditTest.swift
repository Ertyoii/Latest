//
//  ReleaseNotesAuditTest.swift
//  Latest Tests
//
//  Created by Codex on 30.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation
import XCTest
@testable import Latest

final class ReleaseNotesAuditTest: XCTestCase {

	func testInstalledApplicationReleaseNotesAudit() async throws {
		#if !LATEST_RELEASE_NOTES_AUDIT
		throw XCTSkip("Run script/audit_release_notes.sh to audit installed app release notes.")
		#endif

		let directories = AppDirectoryStore(updateHandler: {}).URLs
		let bundles = Self.discoveredBundles(in: directories)
		XCTAssertFalse(bundles.isEmpty, "Expected at least one discoverable app bundle.")

		let updateResults = await Self.updateResults(for: bundles)
		let provider = await MainActor.run { ReleaseNotesProvider() }
		var rows = [AuditRow]()

		for bundle in bundles {
			guard let updateResult = updateResults[bundle.identifier] else {
				rows.append(AuditRow(bundle: bundle, status: "not-checked", detail: "No update checker operation completed.", excerpt: nil))
				continue
			}

			switch updateResult {
			case .failure(let error):
				rows.append(AuditRow(bundle: bundle, status: "update-check-failed", detail: String(describing: error), excerpt: nil))
			case .success(let update):
				let app = App(bundle: bundle, update: .success(update), isIgnored: false)
				guard app.releaseNotes != nil else {
					rows.append(AuditRow(bundle: bundle, status: "unavailable", detail: "Update source returned no release notes.", excerpt: nil))
					continue
				}

				let rendered = await Self.renderedReleaseNotes(for: app, provider: provider)
				switch rendered {
				case .failure(let error):
					rows.append(AuditRow(bundle: bundle, status: "rejected", detail: String(describing: error), excerpt: nil))
				case .success(let resolved):
					let text = resolved.content.string
					let issues = Self.issues(in: text, quality: resolved.quality, for: bundle)
					if issues.isEmpty {
						rows.append(AuditRow(
							bundle: bundle,
							status: "accepted",
							detail: "source=\(app.source.rawValue) quality=\(resolved.quality) provenance=\(resolved.provenance.rawValue)",
							excerpt: text
						))
					} else {
						rows.append(AuditRow(bundle: bundle, status: "malformed", detail: issues.joined(separator: ", "), excerpt: text))
					}
				}
			}
		}

		let report = Self.report(for: rows, directories: directories)
		try Self.write(report: report)

		let malformedRows = rows.filter { $0.status == "malformed" }
		XCTAssertTrue(malformedRows.isEmpty, "Malformed release notes remain:\n\(malformedRows.map(\.summary).joined(separator: "\n"))")

		let regressionKeys = Set(["betterdisplay", "telegram", "zed", "zoomus"])
		let installedRegressionRows = rows.filter { regressionKeys.contains(Self.normalizedBundleKey($0.bundle)) }
		let unresolvedRegressionRows = installedRegressionRows.filter { $0.status != "accepted" }
		XCTAssertTrue(
			unresolvedRegressionRows.isEmpty,
			"Current release-note regressions remain:\n\(unresolvedRegressionRows.map(\.summary).joined(separator: "\n"))"
		)
	}

	private static func discoveredBundles(in directories: [URL]) -> [App.Bundle] {
		let bundles = directories.flatMap(BundleCollector.collectBundles)
		var seen = Set<App.Bundle.Identifier>()
		return bundles
			.sorted { lhs, rhs in
				lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
			}
			.filter { bundle in
				seen.insert(bundle.identifier).inserted
			}
	}

	private static func updateResults(for bundles: [App.Bundle]) async -> [App.Bundle.Identifier: Result<App.Update, Error>] {
		let repository = UpdateRepository.newRepository()
		let execution = await BoundedUpdateCheckExecutor(maximumConcurrentTasks: 6).run(bundles) { bundle in
			guard let result = await UpdateCheckCoordinator.check(bundle, repository: repository) else {
				throw LatestError.updateInfoUnavailable
			}
			return try result.get()
		}
		return execution.results.reduce(into: [:]) { results, indexedResult in
			guard bundles.indices.contains(indexedResult.index) else { return }
			results[bundles[indexedResult.index].identifier] = indexedResult.result
		}
	}

	@MainActor
	private static func renderedReleaseNotes(for app: App, provider: ReleaseNotesProvider) async -> Result<ResolvedReleaseNotes, Error> {
		await withCheckedContinuation { continuation in
			provider.resolvedReleaseNotes(for: app) { result in
				continuation.resume(returning: result)
			}
		}
	}

	private static func issues(in text: String, quality: ReleaseNotesQuality, for bundle: App.Bundle) -> [String] {
		let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
		var issues = [String]()

		if trimmedText.isEmpty {
			issues.append("empty")
		}

		if ReleaseNotesMarkup.looksLikeBinaryOrMojibakeText(trimmedText) {
			issues.append("mojibake")
		}

		if trimmedText.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) == nil {
			issues.append("no-readable-text")
		}

		let lines = trimmedText.components(separatedBy: .newlines).map {
			$0.trimmingCharacters(in: .whitespacesAndNewlines)
		}.filter { !$0.isEmpty }

		if lines.count > 1,
		   ReleaseNotesMarkup.normalizedReleaseLine(lines[0]) == ReleaseNotesMarkup.normalizedReleaseLine(lines[1]) {
			issues.append("duplicate-leading-title")
		}

		if lines.filter({ $0 == "-" || $0 == "–" || $0 == "—" }).count >= 4 {
			issues.append("navigation-separators")
		}

		if trimmedText.range(of: #"<\s*/?\s*(html|body|p|br|div|span|ul|ol|li|h[1-6]|a|strong|em|table)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
			issues.append("raw-html")
		}

		if trimmedText.count > 20_000 {
			issues.append("excessive-length")
		}

		if Self.requiresSpecificReleaseNotes(bundle), quality == .genericMetadata {
			issues.append("generic-known-source")
		}

		if Self.normalizedBundleKey(bundle) == "obsidian",
		   trimmedText.range(of: #"Includes all new features and bug fixes up to Obsidian Desktop|(?m)^\s*•?\s*iOS:"#, options: [.regularExpression, .caseInsensitive]) != nil {
			issues.append("obsidian-mobile-release-notes")
		}

		if Self.normalizedBundleKey(bundle) == "zed" {
			if trimmedText.range(of: #"Version\s*:|Trusted by world-class developers|Creator of Elixir|(?m)^\s*Loading[.…]?\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
				issues.append("zed-page-chrome")
			}
			if trimmedText.range(of: #"This week's release includes|(?m)^\s*Features\s*$"#, options: [.regularExpression, .caseInsensitive]) == nil {
				issues.append("zed-release-body-missing")
			}
		}

		if Self.normalizedBundleKey(bundle) == "zoomus" {
			if trimmedText.range(of: #"(?s)Windows\s+macOS\s+Linux\s+Android|Type Feature title Description Platforms|Full versions"#, options: [.regularExpression, .caseInsensitive]) != nil {
				issues.append("zoom-version-matrix")
			}
			if trimmedText.range(of: #"Show or hide icon labels|New, enhanced, and changed features|Resolved issues"#, options: [.regularExpression, .caseInsensitive]) == nil {
				issues.append("zoom-release-body-missing")
			}
		}

		return issues
	}

	private static func requiresSpecificReleaseNotes(_ bundle: App.Bundle) -> Bool {
		let key = Self.normalizedBundleKey(bundle)
		return [
			"1password",
			"appcleaner",
			"betterdisplay",
			"bruno",
			"chrome",
			"codexbar",
			"cursor",
			"docker",
			"eqmac",
			"ghostty",
			"iina",
			"latestdev",
			"obsidian",
			"pdfexpert",
			"rectangle",
			"surge",
			"telegram",
			"zed",
			"zoomus"
		].contains(key)
	}

	private static func normalizedBundleKey(_ bundle: App.Bundle) -> String {
		bundle.name.lowercased().filter { character in
			character.isLetter || character.isNumber
		}
	}

	private static func report(for rows: [AuditRow], directories: [URL]) -> String {
		var report = [String]()
		report.append("Release Notes Audit")
		report.append("===================")
		report.append("Directories:")
		report.append(contentsOf: directories.map { "- \($0.path)" })
		report.append("")
		report.append("Summary:")

		let statuses = Dictionary(grouping: rows, by: \.status).mapValues(\.count).sorted { $0.key < $1.key }
		report.append(contentsOf: statuses.map { "- \($0.key): \($0.value)" })
		report.append("")
		report.append("Apps:")

		for row in rows {
			report.append(row.summary)
			if let excerpt = row.excerpt {
				report.append(Self.indentedExcerpt(excerpt))
			}
		}

		return report.joined(separator: "\n") + "\n"
	}

	private static func indentedExcerpt(_ text: String) -> String {
		let normalized = text
			.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)

		let excerpt = String(normalized.prefix(700))
		return excerpt.components(separatedBy: .newlines).map { "    \($0)" }.joined(separator: "\n")
	}

	private static func write(report: String) throws {
		let url: URL
		if let path = ProcessInfo.processInfo.environment["LATEST_RELEASE_NOTES_AUDIT_REPORT"] {
			url = URL(fileURLWithPath: path)
		} else {
			url = URL(fileURLWithPath: #filePath)
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.appendingPathComponent("build/release-notes-audit.txt")
		}
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try report.write(to: url, atomically: true, encoding: .utf8)
		print("Release notes audit report: \(url.path)")
	}

}

private struct AuditRow {
	let bundle: App.Bundle
	let status: String
	let detail: String
	let excerpt: String?

	var summary: String {
		"- \(status): \(bundle.name) \(bundle.version.debugDescription) [\(bundle.source.rawValue)] - \(detail)"
	}
}
