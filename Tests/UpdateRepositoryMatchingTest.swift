//
//  UpdateRepositoryMatchingTest.swift
//  Latest Tests
//

import XCTest
@testable import Latest

final class UpdateRepositoryMatchingTest: XCTestCase {
	
	func testMatchesByNameWithAndWithoutAppSuffix() throws {
		let json = """
		[
		  {
			"token": "example",
			"version": "1.2.3",
			"artifacts": [
			  { "app": [ { "target": "Example.app" } ] }
			]
		  }
		]
		""".data(using: .utf8)!
		
		let entries = try JSONDecoder().decode([UpdateRepository.Entry].self, from: json)
		let repository = UpdateRepository.makeForTesting(entries: entries)
		
		let bundleURL = URL(fileURLWithPath: "/Applications/Example.app")
		let bundle = App.Bundle(
			version: Version(versionNumber: "1.0.0", buildNumber: "100"),
			name: "Example",
			bundleIdentifier: "com.example.app",
			fileURL: bundleURL,
			source: .none
		)
		
		let expectation = expectation(description: "Repository matches entry")
		repository.updateInfo(for: bundle) { _, entry in
			XCTAssertEqual(entry?.token, "example")
			expectation.fulfill()
		}
		waitForExpectations(timeout: 1)
	}
	
	func testDisambiguatesByBundleIdentifier() throws {
		let json = """
		[
		  {
			"token": "telegram-desktop",
			"version": "5.0",
			"artifacts": [
			  { "app": [ { "target": "Telegram.app" } ] },
			  { "uninstall": [ { "pkgutil": "org.telegram.desktop" } ] }
			]
		  },
		  {
			"token": "telegram-mac",
			"version": "10.0",
			"artifacts": [
			  { "app": [ { "target": "Telegram.app" } ] },
			  { "uninstall": [ { "pkgutil": "com.telegram.mac" } ] }
			]
		  }
		]
		""".data(using: .utf8)!
		
		let entries = try JSONDecoder().decode([UpdateRepository.Entry].self, from: json)
		let repository = UpdateRepository.makeForTesting(entries: entries)
		
		let bundleURL = URL(fileURLWithPath: "/Applications/Telegram.app")
		let bundle = App.Bundle(
			version: Version(versionNumber: "9.0", buildNumber: "900"),
			name: "Telegram",
			bundleIdentifier: "com.telegram.mac",
			fileURL: bundleURL,
			source: .none
		)
		
		let expectation = expectation(description: "Repository disambiguates entry")
		repository.updateInfo(for: bundle) { _, entry in
			XCTAssertEqual(entry?.token, "telegram-mac")
			expectation.fulfill()
		}
		waitForExpectations(timeout: 1)
	}
}
