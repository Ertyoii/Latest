//
//  AppUpdateController.swift
//  Latest
//
//  Structural split from the original implementation.
//

import Combine
import Sparkle

@MainActor
final class AppUpdateController: ObservableObject {
  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  func checkForAppUpdates() {
    updaterController.checkForUpdates(nil)
  }
}
