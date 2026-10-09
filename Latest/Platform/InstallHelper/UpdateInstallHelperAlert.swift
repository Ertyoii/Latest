// Copyright © 2026 Max Langer and ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import Combine
import Foundation
import SwiftUI

/// Owns preparation and the pending action, so dismissal or a late XPC reply
/// cannot accidentally start a download. The sheet remains visible through repair.
@MainActor
final class UpdateInstallHelperAlert: ObservableObject {
  static let shared = UpdateInstallHelperAlert()
  @Published var isPresented = false
  @Published private(set) var isChecking = false
  @Published private(set) var availabilityError = InstallHelperError.installHelperNotRegistered
  @Published private(set) var registrationError: Error?
  private var fallbackURL: URL?
  private var pendingUpdates: [() -> Void] = []
  private var preparation: (@MainActor () async throws -> Void)?
  private var checkTask: Task<Void, Never>?
  private var requestID = UUID()
  private let helper: any InstallHelperServicing
  private let workspace: any ApplicationWorkspace

  init(
    helper: any InstallHelperServicing = LiveInstallHelperService.shared,
    workspace: any ApplicationWorkspace = MacApplicationWorkspace.shared
  ) {
    self.helper = helper
    self.workspace = workspace
  }

  func prepare(
    fallbackURL: URL, preparation: (@MainActor () async throws -> Void)? = nil,
    update: @escaping () -> Void
  ) {
    guard pendingUpdates.isEmpty else {
      pendingUpdates.append(update)
      return
    }
    self.fallbackURL = fallbackURL
    self.preparation = preparation
    pendingUpdates = [update]
    registrationError = nil
    isPresented = true
    check()
  }

  static func present(
    with error: InstallHelperError, fallbackURL: URL, retry: @escaping @MainActor () -> Void = {}
  ) {
    shared.present(error, fallbackURL: fallbackURL, retry: retry)
  }

  func present(_ error: InstallHelperError, fallbackURL: URL, retry: @escaping () -> Void) {
    guard pendingUpdates.isEmpty else {
      pendingUpdates.append(retry)
      return
    }
    availabilityError = error
    self.fallbackURL = fallbackURL
    pendingUpdates = [retry]
    registrationError = nil
    if AppStoreUpdateSettings.alwaysPerformManualUpdates.active {
      openAppStore()
    } else {
      isPresented = true
    }
  }

  var title: String {
    if isChecking { return "Checking Update Helper" }
    switch availabilityError {
    case .installHelperNotRegistered: return "Set Up App Store Updates"
    case .installHelperRequiresApproval: return "Allow App Store Updates"
    case .unavailable: return "Update Helper Unavailable"
    }
  }

  var message: String {
    if isChecking { return "Checking that the helper is ready before downloading any updates." }
    switch availabilityError {
    case .installHelperNotRegistered:
      return
        "Latest needs an approved helper to install App Store updates. No updates will download until it is ready."
    case .installHelperRequiresApproval:
      return
        "Allow Latest in System Settings → General → Login Items & Extensions. Return here to continue automatically once the helper is ready."
    case .unavailable:
      return
        "Latest could not connect to its update helper. No downloads have started. Try checking again, or update using the App Store."
    }
  }

  var primaryTitle: String {
    switch availabilityError {
    case .installHelperNotRegistered: return "Enable Helper"
    case .installHelperRequiresApproval: return "Open System Settings"
    case .unavailable: return "Check Again"
    }
  }

  func enableHelper() {
    switch availabilityError {
    case .unavailable: check()
    default: check(register: true)
    }
  }

  func resumeIfAvailable() {
    guard availabilityError == .installHelperRequiresApproval else { return }
    check()
  }

  private func check(register: Bool = false) {
    guard !pendingUpdates.isEmpty, !isChecking else { return }
    isChecking = true
    registrationError = nil
    let id = requestID
    checkTask = Task {
      do {
        if register { try helper.register() }
        if let preparation { try await preparation() } else { try await helper.prepareForUpdates() }
        guard !Task.isCancelled, id == requestID else { return }
        let updates = pendingUpdates
        clear()
        isPresented = false
        updates.forEach { $0() }
      } catch {
        guard !Task.isCancelled, id == requestID else { return }
        isChecking = false
        checkTask = nil
        availabilityError = error as? InstallHelperError ?? .unavailable(error.localizedDescription)
        if case .unavailable = availabilityError { registrationError = error }
      }
    }
  }

  func openAppStore() {
    let url = fallbackURL
    cancel()
    if let url { workspace.open(url) }
  }

  func cancel() {
    checkTask?.cancel()
    clear()
    isPresented = false
  }

  private func clear() {
    requestID = UUID()
    pendingUpdates = []
    preparation = nil
    checkTask = nil
    isChecking = false
    registrationError = nil
  }
}

struct UpdateInstallHelperPresentation: ViewModifier {
  @ObservedObject var presenter: UpdateInstallHelperAlert = .shared
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(AppStoreUpdateSettings.alwaysPerformManualUpdates.rawValue)
  private var alwaysOpenAppStore = false

  func body(content: Content) -> some View {
    content
      .sheet(
        isPresented: $presenter.isPresented,
        onDismiss: { if !presenter.isPresented { presenter.cancel() } }
      ) {
        VStack(alignment: .leading, spacing: 20) {
          HStack(spacing: 12) {
            Image(systemName: "shippingbox")
              .font(.system(size: 28)).foregroundStyle(.secondary)
            Text(presenter.title).font(.title2.bold())
          }
          Text(presenter.message).fixedSize(horizontal: false, vertical: true)
          if presenter.isChecking {
            HStack(spacing: 10) {
              ProgressView().controlSize(.small)
              Text("Checking and repairing helper…").foregroundStyle(.secondary)
            }
          }
          if let error = presenter.registrationError {
            DisclosureGroup("Details") {
              Text(
                [error.localizedDescription, (error as? LocalizedError)?.failureReason]
                  .compactMap { $0 }.joined(separator: "\n\n")
              )
              .font(.caption).textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          Toggle("Always open App Store", isOn: $alwaysOpenAppStore)
          Divider()
          HStack {
            Button("Cancel", role: .cancel) { presenter.cancel() }
              .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Open App Store") { presenter.openAppStore() }
            Button(presenter.primaryTitle) { presenter.enableHelper() }
              .keyboardShortcut(.defaultAction)
              .disabled(presenter.isChecking)
          }
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .interactiveDismissDisabled(presenter.isChecking)
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { presenter.resumeIfAvailable() }
      }
  }
}
