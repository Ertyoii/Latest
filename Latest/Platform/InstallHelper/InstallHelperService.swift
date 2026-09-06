//
//  InstallHelperService.swift
//  Latest
//
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-29.
//  Licensed under GPL-3.0; see LICENSE.md.

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
