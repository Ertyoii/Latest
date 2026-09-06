//
//  InstallHelperService.swift
//  Latest
//
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation

@MainActor
protocol InstallHelperServicing: AnyObject {
  func verifyAvailability() throws
  func register() throws
}

@MainActor
final class LiveInstallHelperService: InstallHelperServicing {
  static let shared = LiveInstallHelperService()

  private init() {}

  func verifyAvailability() throws {
    try InstallHelper.verifyAvailability()
  }

  func register() throws {
    AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
    try InstallHelper.installHelper()
  }
}
