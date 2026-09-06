//
//  main.swift
//  Latest
//
//  Created by Codex on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation
import SwiftUI

enum ApplicationRuntime {
  static var isRunningUnitTests: Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCTestConfigurationFilePath"] != nil
      || environment["XCTestBundlePath"] != nil || NSClassFromString("XCTestCase") != nil
  }
}

/// The unit-test bundle is linked into the application executable. Launching the
/// production SwiftUI scene from that host used to scan installed applications,
/// make live network requests, and mutate user defaults before XCTest started.
/// A settings-only scene keeps the AppKit test host alive without starting any
/// production service or opening a window.
private struct LatestUnitTestHostApplication: SwiftUI.App {
  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

if ApplicationRuntime.isRunningUnitTests {
  LatestUnitTestHostApplication.main()
} else {
  LatestApplication.main()
}
