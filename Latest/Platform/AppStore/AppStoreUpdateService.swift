//
//  AppStoreUpdateService.swift
//  Latest
//
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation

@MainActor
protocol AppStoreUpdateServicing: AnyObject {
  var alwaysUsesManualUpdates: Bool { get }
  func prepareForUpdates() throws(InstallHelperError)
}

@MainActor
final class LiveAppStoreUpdateService: AppStoreUpdateServicing {
  static let shared = LiveAppStoreUpdateService()

  private init() {}

  var alwaysUsesManualUpdates: Bool {
    AppStoreUpdateSettings.alwaysPerformManualUpdates.active
  }

  func prepareForUpdates() throws(InstallHelperError) {
    try AppStoreUpdater.prepareForUpdates()
  }
}
