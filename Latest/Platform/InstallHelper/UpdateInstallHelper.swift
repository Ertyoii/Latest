//
//  UpdateInstallHelper.swift
//  Latest
//
//  Created by Max Langer on 11.01.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation
import ServiceManagement
import Synchronization

/// Manages the privileged helper daemon used to install App Store updates via XPC.
actor InstallHelper {

  /// The shared instance used for installing packages.
  static let shared = InstallHelper()

  private static let installHelperName = "com.max-langer.latest.UpdateInstaller"
  private static let availabilityRefreshLifetime: TimeInterval = 5 * 60
  private var lastAvailabilityRefresh: Date?
  private var availabilityRefreshTask: Task<Void, Error>?

  private init() {}

  // MARK: - Helper Registration

  /// Verifies that the install helper is registered and approved.
  static func verifyAvailability() throws(InstallHelperError) {
    switch helperService.status {
    case .notFound, .notRegistered:
      throw InstallHelperError.installHelperNotRegistered
    case .requiresApproval:
      throw InstallHelperError.installHelperRequiresApproval
    case .enabled:
      return
    @unknown default:
      throw InstallHelperError.installHelperNotRegistered
    }
  }

  /// Registers the helper or opens System Settings if approval is required.
  static func installHelper() throws {
    let service = helperService
    switch service.status {
    case .notFound, .notRegistered:
      try service.register()
    case .requiresApproval:
      SMAppService.openSystemSettingsLoginItems()
    case .enabled:
      break
    @unknown default:
      break
    }
  }

  private static var helperService: SMAppService {
    SMAppService.daemon(plistName: installHelperName + ".plist")
  }

  /// Re-registers the helper to ensure it is available for use.
  private func ensureAvailability() async throws {
    try Self.verifyAvailability()

    if let lastAvailabilityRefresh,
      Date().timeIntervalSince(lastAvailabilityRefresh) < Self.availabilityRefreshLifetime
    {
      return
    }

    if let availabilityRefreshTask {
      try await availabilityRefreshTask.value
      return
    }

    let refreshTask = Task {
      let service = Self.helperService
      try await service.unregister()
      try await Task.sleep(for: .seconds(0.5))
      try service.register()
    }
    availabilityRefreshTask = refreshTask
    defer { availabilityRefreshTask = nil }

    do {
      try await refreshTask.value
      lastAvailabilityRefresh = Date()
    } catch {
      lastAvailabilityRefresh = nil
      throw error
    }
  }

  // MARK: - Package Installation

  /// Installs an App Store update package at the given target URL via the privileged helper.
  func installPackage(at url: URL, targetURL: String, receiptData: Data, receiptURL: URL)
    async throws
  {
    try await ensureAvailability()

    let connection = NSXPCConnection(machServiceName: Self.installHelperName)
    connection.remoteObjectInterface = NSXPCInterface(with: UpdateInstallerProtocol.self)

    connection.activate()
    defer { connection.invalidate() }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let replyGate = InstallationReplyGate(continuation: continuation)
      replyGate.scheduleTimeout()
      connection.interruptionHandler = {
        replyGate.resume(with: .failure(LatestError.installHelperCommunicationFailed))
      }
      connection.invalidationHandler = {
        replyGate.resume(with: .failure(LatestError.installHelperCommunicationFailed))
      }

      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
          replyGate.resume(with: .failure(error))
        }) as? UpdateInstallerProtocol
      else {
        replyGate.resume(with: .failure(LatestError.installHelperCommunicationFailed))
        return
      }

      proxy.performInstallation(
        ofPackageAt: url, targetURL: targetURL, receiptData: receiptData, receiptURL: receiptURL
      ) { error in
        if let error {
          replyGate.resume(with: .failure(error))
        } else {
          replyGate.resume(with: .success(()))
        }
      }
    }
  }
}

final class InstallationReplyGate: Sendable {
  private struct State {
    var continuation: CheckedContinuation<Void, Error>?
    var timeoutTask: Task<Void, Never>?
  }

  private let state: Mutex<State>

  init(continuation: CheckedContinuation<Void, Error>) {
    state = Mutex(State(continuation: continuation))
  }

  func scheduleTimeout(after duration: Duration = .seconds(120)) {
    let task = Task.detached(priority: .utility) { [self] in
      do {
        try await Task.sleep(for: duration)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      resume(with: .failure(LatestError.installHelperCommunicationFailed))
    }

    let alreadyFinished = state.withLock { state in
      guard state.continuation != nil else { return true }
      state.timeoutTask = task
      return false
    }
    if alreadyFinished {
      task.cancel()
    }
  }

  func resume(with result: Result<Void, Error>) {
    let completion = state.withLock {
      state -> (CheckedContinuation<Void, Error>, Task<Void, Never>?)? in
      guard let continuation = state.continuation else { return nil }
      state.continuation = nil
      let timeoutTask = state.timeoutTask
      state.timeoutTask = nil
      return (continuation, timeoutTask)
    }
    guard let (continuation, timeoutTask) = completion else { return }

    timeoutTask?.cancel()
    switch result {
    case .success:
      continuation.resume()
    case .failure(let error):
      continuation.resume(throwing: error)
    }
  }
}

// MARK: - InstallHelperError

/// Errors related to install helper availability.
enum InstallHelperError: LocalizedError {
  case installHelperNotRegistered
  case installHelperRequiresApproval

  var errorDescription: String? {
    switch self {
    case .installHelperNotRegistered:
      return NSLocalizedString(
        "InstallHelperNotFoundErrorDescription",
        comment: "Shown when the update helper is not installed.")
    case .installHelperRequiresApproval:
      return NSLocalizedString(
        "InstallHelperRequiresApprovalErrorDescription",
        comment: "Shown when the update helper is installed but disabled, requiring approval.")
    }
  }
}
