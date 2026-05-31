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

	func testCanPerformUpdateCheckRequiresExistingReceipt() throws {
		let appURL = temporaryAppURL()
		try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

		XCTAssertFalse(AppStoreUpdateCheckerOperation.canPerformUpdateCheck(forAppAt: appURL))
	}

	func testCanPerformUpdateCheckFindsStandardMacAppReceipt() throws {
		let appURL = temporaryAppURL()
		let receiptURL = AppStoreReceipt.standardReceiptURL(forAppAt: appURL)
		try writeReceipt(at: receiptURL)

		XCTAssertTrue(AppStoreUpdateCheckerOperation.canPerformUpdateCheck(forAppAt: appURL))
		XCTAssertFalse(AppStoreUpdateCheckerOperation.isIOSAppBundle(at: appURL))
	}

	func testReceiptURLFindsExistingWrappedIOSReceipt() throws {
		let appURL = temporaryAppURL()
		let receiptURL = appURL.appendingPathComponent("Contents/Wrapper/WrappedBundle.app/_MASReceipt/receipt", isDirectory: false)
		try writeReceipt(at: receiptURL)

		XCTAssertEqual(
			AppStoreReceipt.url(forAppAt: appURL)?.resolvingSymlinksInPath(),
			receiptURL.resolvingSymlinksInPath()
		)
		XCTAssertTrue(AppStoreUpdateCheckerOperation.canPerformUpdateCheck(forAppAt: appURL))
		XCTAssertTrue(AppStoreUpdateCheckerOperation.isIOSAppBundle(at: appURL))
	}

	func testStandardReceiptTakesPriorityOverWrappedReceipt() throws {
		let appURL = temporaryAppURL()
		let standardReceiptURL = AppStoreReceipt.standardReceiptURL(forAppAt: appURL)
		let wrappedReceiptURL = appURL.appendingPathComponent("Contents/Wrapper/WrappedBundle.app/_MASReceipt/receipt", isDirectory: false)
		try writeReceipt(at: standardReceiptURL)
		try writeReceipt(at: wrappedReceiptURL)

		XCTAssertEqual(
			AppStoreReceipt.url(forAppAt: appURL)?.resolvingSymlinksInPath(),
			standardReceiptURL.resolvingSymlinksInPath()
		)
		XCTAssertFalse(AppStoreUpdateCheckerOperation.isIOSAppBundle(at: appURL))
	}

	private func temporaryAppURL() -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
			.appendingPathExtension("app")
		addTeardownBlock {
			try? FileManager.default.removeItem(at: url)
		}
		return url
	}

	private func writeReceipt(at url: URL) throws {
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data().write(to: url)
	}

}
