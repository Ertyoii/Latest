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
  func prepareForUpdates() async throws
}

@MainActor
final class LiveInstallHelperService: InstallHelperServicing {
  static let shared = LiveInstallHelperService()

  private init() {}

  func verifyAvailability() throws {
    try InstallHelper.verifyAvailability()
  }

  func prepareForUpdates() async throws {
    try await InstallHelper.prepareForUpdates()
  }

  func register() throws {
    AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
    try InstallHelper.installHelper()
  }
}

/// Registration is only a prerequisite. Every new batch proves live XPC health;
/// concurrent requests share only the check currently in flight.
struct InstallHelperHealth: Sendable {
  let signature: Data
  let isInstalling: Bool
}

protocol InstallHelperReadinessBackend: Sendable {
  func verify() async throws -> Data
  func probe() async throws -> InstallHelperHealth
  func refresh() async throws
}

actor InstallHelperReadiness {
  private let backend: any InstallHelperReadinessBackend
  private var preparation: (id: UUID, generation: Int, task: Task<Bool, Error>)?
  private var installations = 0
  private var uncertainInstallation = false
  private var failureGeneration = 0

  init(backend: any InstallHelperReadinessBackend) { self.backend = backend }

  func prepare() async throws {
    let pending: (id: UUID, generation: Int, task: Task<Bool, Error>)
    if let preparation {
      pending = preparation
    } else {
      let mayRefresh = installations == 0
      let outcomeUnknown = uncertainInstallation
      let task = Task { [backend] in
        let expected = try await backend.verify()
        let health = try? await backend.probe()
        if let health, health.signature == expected {
          if outcomeUnknown && health.isInstalling {
            throw InstallHelperError.unavailable(
              "The helper is still installing an update. Wait for it to finish before trying again."
            )
          }
          return !health.isInstalling
        }
        // A lost reply does not prove installer stopped. Only a live, idle
        // response can clear that uncertainty; never restart blindly.
        guard mayRefresh, health?.isInstalling != true,
          !outcomeUnknown || health?.isInstalling == false
        else {
          throw InstallHelperError.unavailable(
            "An installation may still be running. Check its result before trying again; Latest will not restart the helper while its outcome is unknown."
          )
        }
        try await backend.refresh()
        // Registration can report enabled before launchd can service requests.
        for attempt in 0..<3 {
          do {
            let health = try await backend.probe()
            guard health.signature == expected else {
              throw InstallHelperError.unavailable("The running update helper is out of date.")
            }
            return !health.isInstalling
          } catch {
            if attempt == 2 { throw error }
            try await Task.sleep(for: .milliseconds(500))
          }
        }
        return false
      }
      pending = (UUID(), failureGeneration, task)
      preparation = pending
    }
    defer { if preparation?.id == pending.id { preparation = nil } }
    let idle = try await pending.task.value
    if idle, failureGeneration == pending.generation { uncertainInstallation = false }
    try Task.checkCancellation()
  }

  func install(_ action: @Sendable () async throws -> URL) async throws -> URL {
    try await prepare()
    // Another check can enter while this caller resumes from prepare(). Reserve
    // the installation only when no refresh is in flight, on this actor.
    while preparation != nil { try await prepare() }
    try Task.checkCancellation()
    installations += 1
    defer { installations -= 1 }
    do { return try await action() } catch {
      uncertainInstallation = true
      failureGeneration += 1
      throw error
    }
  }
}
