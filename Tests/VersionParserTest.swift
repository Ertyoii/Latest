//
//  VersionParserTest.swift
//  Latest Tests
//
//  Created by Max Langer on 29.11.23.
//  Copyright © 2023 Max Langer. All rights reserved.
//

import XCTest
@testable import Latest


final class VersionParserTest: XCTestCase {

	func testBuildNumberParsing() {
		XCTAssertEqual(VersionParser.parse(buildNumber: "1234"), "1234")
		XCTAssertEqual(VersionParser.parse(buildNumber: "IU-1234"), "1234")
		XCTAssertEqual(VersionParser.parse(buildNumber: "WS-1234"), "1234")
		XCTAssertEqual(VersionParser.parse(buildNumber: "1.2/1234"), "1234")
		XCTAssertEqual(VersionParser.parse(buildNumber: "1.2 (r1234)"), "1234")
		XCTAssertEqual(VersionParser.parse(buildNumber: "ab-1234"), "ab-1234")
	}
	
	func testVersionNumberParsing() {
		XCTAssertEqual(VersionParser.parse(versionNumber: "1234"), "1234")
		XCTAssertEqual(VersionParser.parse(versionNumber: "v1234"), "1234")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2.3.4"), "1.2.3.4")
		XCTAssertEqual(VersionParser.parse(versionNumber: "Build 1234"), "1234")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2.3 (r1234)"), "1.2.3")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2.3.osx14"), "1.2.3")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2-HEAD-123abc"), "1.2")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2-stable.123abc"), "1.2")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2-latest"), "1.2")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2-release"), "1.2")
		XCTAssertEqual(VersionParser.parse(versionNumber: "1.2-demo"), "1.2")
	}

	func testCombinedVersionNumberParsing() {
		XCTAssertEqual(VersionParser.parse(combinedVersionNumber: "1234"), Version(versionNumber: "1234", buildNumber: nil))
		XCTAssertEqual(VersionParser.parse(combinedVersionNumber: "1234,321"), Version(versionNumber: "1234", buildNumber: "321"))
		XCTAssertEqual(VersionParser.parse(combinedVersionNumber: "1.2.3.4,321ABC,70"), Version(versionNumber: "1.2.3.4", buildNumber: "321ABC"))
		XCTAssertEqual(VersionParser.parse(combinedVersionNumber: "2.2.1-763"), Version(versionNumber: "2.2.1", buildNumber: "763"))
	}
	
	func testEmptyVersionParsing() {
		XCTAssertNil(VersionParser.parse(buildNumber: ""))
		XCTAssertNil(VersionParser.parse(versionNumber: ""))
		
		XCTAssertEqual(VersionParser.parse(combinedVersionNumber: ""), Version(versionNumber: nil, buildNumber: nil))
	}

	func testHomebrewCaskEntryProvidesFormattedFallbackReleaseNotes() throws {
		let json = """
		{
			"token": "example-app",
			"version": "2.4.1",
			"name": ["Example App"],
			"desc": "Notes, tasks & reminders",
			"homepage": "https://example.com",
			"depends_on": {
				"macos": {
					">=": ["13.0"]
				}
			},
			"artifacts": [
				{
					"app": ["Example App.app"]
				}
			]
		}
		"""
		let entry = try JSONDecoder().decode(UpdateRepository.Entry.self, from: Data(json.utf8))

		guard case .html(let html) = entry.releaseNotes else {
			return XCTFail("Expected Homebrew entries to provide fallback HTML release notes.")
		}

		XCTAssertTrue(html.contains("<h2>Example App</h2>"))
		XCTAssertTrue(html.contains("Notes, tasks &amp; reminders"))
		XCTAssertTrue(html.contains("<strong>Version:</strong> 2.4.1"))
		XCTAssertTrue(html.contains("https://formulae.brew.sh/cask/example-app"))
		XCTAssertTrue(html.contains("<a href=\"https://example.com\">https://example.com</a>"))
	}
	
}
