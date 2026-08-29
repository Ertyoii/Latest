//
//  ReleaseNotesPersistentCacheTest.swift
//  Latest Tests
//
//  Structural split from the original implementation.
//

import CryptoKit
import XCTest
@testable import Latest

final class ReleaseNotesPersistentCacheTest: XCTestCase {
	@MainActor
	func testPersistentReleaseNotesCacheRoundTripsRenderedContentAndProvenance() async throws {
		let directoryURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let cache = ReleaseNotesPersistentCache(directoryURL: directoryURL)
		let source = NSMutableAttributedString(string: "Version 2.0\nFixed repeated release-note parsing.")
		source.addAttribute(
			.link,
			value: URL(string: "https://example.com/releases/2.0")!,
			range: NSRange(location: 0, length: 11)
		)
		let resolved = ResolvedReleaseNotes(content: source, quality: .genuine, provenance: .changelog)
		let payload = try XCTUnwrap(ReleaseNotesPersistentCache.payload(from: resolved))

		await cache.store(payload, forKey: "com.example.app-2.0")
		let loadedPayload = await cache.payload(forKey: "com.example.app-2.0")
		let storedPayload = try XCTUnwrap(loadedPayload)
		let restored = try XCTUnwrap(ReleaseNotesPersistentCache.resolvedReleaseNotes(from: storedPayload))

		XCTAssertEqual(restored.content.string, source.string)
		XCTAssertEqual(restored.quality, .genuine)
		XCTAssertEqual(restored.provenance, .changelog)
		XCTAssertNotNil(restored.content.attribute(.link, at: 0, effectiveRange: nil))
	}

}
