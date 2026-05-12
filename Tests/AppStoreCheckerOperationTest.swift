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

}
