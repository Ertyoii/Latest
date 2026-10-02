//
//  UpdateInstallHelper.swift
//  Latest
//
//  Created by Max Langer on 11.01.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation
import Security
import ServiceManagement
import Synchronization

/// Manages the privileged helper daemon used to install App Store updates via XPC.
enum InstallHelper {

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
    try verifySigning()
    let service = helperService
    switch service.status {
    case .notFound, .notRegistered:
      try service.register()
      if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    case .requiresApproval:
      SMAppService.openSystemSettingsLoginItems()
    case .enabled:
      break
    @unknown default:
      break
    }
  }

  private static var helperService: SMAppService {
    SMAppService.daemon(plistName: UpdateInstallerIdentity.service + ".plist")
  }

  /// A root daemon must have a stable Apple-issued signing identity. Do not
  /// weaken its launch or peer requirements for unsigned development builds.
  static func verifySigning() throws {
    let helperURL = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Resources/LatestUpdateInstaller")
    for (url, text) in [
      (Bundle.main.bundleURL, UpdateInstallerIdentity.appRequirement),
      (helperURL, UpdateInstallerIdentity.helperRequirement),
    ] {
      var code: SecStaticCode?
      var policy: SecRequirement?
      guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
        SecRequirementCreateWithString(text as CFString, [], &policy) == errSecSuccess,
        let code, let policy,
        SecStaticCodeCheckValidity(code, [], policy) == errSecSuccess
      else {
        throw LatestError.custom(
          title: "Update Helper Requires a Signed Build",
          description:
            "This copy of Latest or its helper does not have the required code signature. Use a signed build of Latest, then enable the helper again."
        )
      }
    }
  }

  // MARK: - Package Installation

  /// Installs an App Store update package at the given target URL via the privileged helper.
  static func installPackage(at url: URL, appURL: URL, receiptData: Data)
    async throws -> URL
  {
    try Self.verifyAvailability()

    let connection = NSXPCConnection(
      machServiceName: UpdateInstallerIdentity.service, options: .privileged)
    connection.setCodeSigningRequirement(UpdateInstallerIdentity.helperRequirement)
    connection.remoteObjectInterface = NSXPCInterface(with: UpdateInstallerProtocol.self)

    defer { connection.invalidate() }

    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<URL, Error>) in
      let replyGate = InstallationReplyGate(continuation: continuation)
      replyGate.scheduleTimeout()
      connection.interruptionHandler = {
        replyGate.resume(with: .failure(LatestError.installHelperCommunicationFailed))
      }
      connection.invalidationHandler = {
        replyGate.resume(with: .failure(LatestError.installHelperCommunicationFailed))
      }
      connection.activate()

      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
          replyGate.resume(with: .failure(error))
        }) as? UpdateInstallerProtocol
      else {
        replyGate.resume(with: .failure(LatestError.installHelperCommunicationFailed))
        return
      }

      proxy.performInstallation(
        ofPackageAt: url, appURL: appURL, receiptData: receiptData
      ) { installedURL, error in
        if let error {
          replyGate.resume(with: .failure(error))
        } else if let installedURL {
          replyGate.resume(with: .success(installedURL))
        } else {
          replyGate.resume(with: .failure(LatestError.installHelperCommunicationFailed))
        }
      }
    }
  }
}

final class InstallationReplyGate: Sendable {
  private struct State {
    var continuation: CheckedContinuation<URL, Error>?
    var timeoutTask: Task<Void, Never>?
  }

  private let state: Mutex<State>

  init(continuation: CheckedContinuation<URL, Error>) {
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

  func resume(with result: Result<URL, Error>) {
    let completion = state.withLock {
      state -> (CheckedContinuation<URL, Error>, Task<Void, Never>?)? in
      guard let continuation = state.continuation else { return nil }
      state.continuation = nil
      let timeoutTask = state.timeoutTask
      state.timeoutTask = nil
      return (continuation, timeoutTask)
    }
    guard let (continuation, timeoutTask) = completion else { return }

    timeoutTask?.cancel()
    continuation.resume(with: result)
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
