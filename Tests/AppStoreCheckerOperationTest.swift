//
//  AppStoreCheckerOperationTest.swift
//  Latest Tests
//
//  Created by Codex on 12.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import XCTest
@testable import Latest

class AppStoreCheckerOperationTest: XCTestCase {

	func testNativeMacAppStoreAppsPreferDesktopLookupBeforeFallback() throws {
		XCTAssertEqual(AppStoreUpdateCheckerOperation.lookupEntityTypes(isIOSAppBundle: false), ["desktopSoftware", "macSoftware"])
	}

	func testWrappedIOSAppsSkipDesktopLookup() throws {
		XCTAssertEqual(AppStoreUpdateCheckerOperation.lookupEntityTypes(isIOSAppBundle: true), ["macSoftware"])
	}

	func testReceiptURLFallsBackToStandardMacAppReceiptLocation() throws {
		let appURL = temporaryAppURL()
		try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

		XCTAssertEqual(
			AppStoreReceipt.url(forAppAt: appURL),
			appURL.appendingPathComponent("Contents/_MASReceipt/receipt", isDirectory: false)
		)
	}

	func testReceiptURLFindsExistingWrappedIOSReceipt() throws {
		let appURL = temporaryAppURL()
		let receiptURL = appURL.appendingPathComponent("Contents/Wrapper/WrappedBundle.app/_MASReceipt/receipt", isDirectory: false)
		try FileManager.default.createDirectory(at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data().write(to: receiptURL)

		XCTAssertEqual(AppStoreReceipt.url(forAppAt: appURL), receiptURL)
		XCTAssertTrue(AppStoreUpdateCheckerOperation.isIOSAppBundle(at: appURL))
	}

	private func temporaryAppURL() -> URL {
		FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
			.appendingPathExtension("app")
	}

}
