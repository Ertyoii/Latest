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
    try await HelperRegistration.shared.refreshIfNeeded()
    // Transfer an open descriptor: the root daemon cannot reopen files in the
    // user's protected temporary directory on current macOS releases.
    let package = try FileHandle(forReadingFrom: url)
    defer { try? package.close() }

    let connection = NSXPCConnection(
      machServiceName: UpdateInstallerIdentity.service, options: .privileged)
    connection.setCodeSigningRequirement(UpdateInstallerIdentity.helperRequirement)
    connection.remoteObjectInterface = NSXPCInterface(with: UpdateInstallerProtocol.self)

    defer { connection.invalidate() }

    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<URL, Error>) in
      let replyGate = InstallationReplyGate(continuation: continuation)
      // A deadline here would release the queue while /usr/sbin/installer is
      // still replacing the app. Wait for its result or an XPC connection error.
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
        ofPackage: package, appURL: appURL, receiptData: receiptData
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

  /// SMAppService does not replace an already-running executable automatically.
  /// Persist the exact helper signature and bundle path, so replacement builds
  /// refresh once while multiple updates share the same registration.
  private actor HelperRegistration {
    static let shared = HelperRegistration()
    private var refreshTask: Task<Void, Error>?

    func refreshIfNeeded() async throws {
      if let refreshTask { return try await refreshTask.value }
      let task = Task {
        try InstallHelper.verifySigning()
        let helperURL = Bundle.main.bundleURL.appendingPathComponent(
          "Contents/Resources/LatestUpdateInstaller")
        var code: SecStaticCode?
        var information: CFDictionary?
        guard SecStaticCodeCreateWithPath(helperURL as CFURL, [], &code) == errSecSuccess,
          let code,
          SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
          let hash = (information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
        else { throw LatestError.installHelperCommunicationFailed }
        let identity = Bundle.main.bundleURL.path + ":" + hash.base64EncodedString()
        let key = "RegisteredInstallHelperIdentity"
        guard UserDefaults.standard.string(forKey: key) != identity else { return }
        let service = InstallHelper.helperService
        // The asynchronous completion waits until the old process has exited.
        try await service.unregister()
        // Background Task Management settles its enabled state separately.
        // Keep the original delay, once per helper build rather than periodically.
        try await Task.sleep(for: .milliseconds(500))
        try service.register()
        try InstallHelper.verifyAvailability()
        UserDefaults.standard.set(identity, forKey: key)
      }
      refreshTask = task
      do { try await task.value } catch {
        refreshTask = nil
        throw error
      }
    }
  }
}

final class InstallationReplyGate: Sendable {
  private let state: Mutex<CheckedContinuation<URL, Error>?>

  init(continuation: CheckedContinuation<URL, Error>) {
    state = Mutex(continuation)
  }

  func resume(with result: Result<URL, Error>) {
    let continuation = state.withLock { state in
      defer { state = nil }
      return state
    }
    continuation?.resume(with: result)
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
