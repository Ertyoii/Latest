// Copyright © 2026 Max Langer and ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import Combine
import Foundation
import SwiftUI

/// SwiftUI owns dialog presentation and the pending update. Registration never
/// silently consumes an error or loses the update that requested the helper.
@MainActor
final class UpdateInstallHelperAlert: ObservableObject {
  static let shared = UpdateInstallHelperAlert()
  @Published var isPresented = false
  @Published private(set) var availabilityError = InstallHelperError.installHelperNotRegistered
  @Published private(set) var registrationError: Error?
  private var fallbackURL: URL?
  private var pendingUpdate: (() -> Void)?
  private let helper: any InstallHelperServicing
  private let workspace: any ApplicationWorkspace

  init(
    helper: any InstallHelperServicing = LiveInstallHelperService.shared,
    workspace: any ApplicationWorkspace = MacApplicationWorkspace.shared
  ) {
    self.helper = helper
    self.workspace = workspace
  }

  static func present(
    with error: InstallHelperError, fallbackURL: URL,
    retry: @escaping @MainActor () -> Void = {}
  ) {
    shared.present(error, fallbackURL: fallbackURL, retry: retry)
  }

  func present(_ error: InstallHelperError, fallbackURL: URL, retry: @escaping () -> Void) {
    self.availabilityError = error
    self.fallbackURL = fallbackURL
    pendingUpdate = retry
    registrationError = nil
    if AppStoreUpdateSettings.alwaysPerformManualUpdates.active {
      openAppStore()
    } else {
      isPresented = true
    }
  }

  var title: String {
    registrationError == nil
      ? NSLocalizedString("UpdateInstallHelperAlert.Title", comment: "Update helper title")
      : "Unable to Enable Update Helper"
  }

  var message: String {
    if let registrationError {
      return [
        registrationError.localizedDescription,
        (registrationError as? LocalizedError)?.failureReason,
      ]
      .compactMap { $0 }.joined(separator: "\n\n")
    }
    return availabilityError.errorDescription ?? ""
  }

  var primaryTitle: String {
    NSLocalizedString(
      availabilityError == .installHelperNotRegistered
        ? "UpdateInstallHelperAlert.Primary.InstallHelper"
        : "UpdateInstallHelperAlert.Primary.OpenSettings", comment: "Enable update helper")
  }

  func enableHelper() {
    do {
      try helper.register()
      resumeIfAvailable()
    } catch {
      registrationError = error
      Task { @MainActor in isPresented = true }
    }
  }

  func resumeIfAvailable() {
    guard pendingUpdate != nil, registrationError == nil else { return }
    do { try helper.verifyAvailability() } catch { return }
    let update = pendingUpdate
    pendingUpdate = nil
    isPresented = false
    update?()
  }

  func openAppStore() {
    pendingUpdate = nil
    isPresented = false
    if let fallbackURL { workspace.open(fallbackURL) }
  }

  func cancel() {
    pendingUpdate = nil
    registrationError = nil
    isPresented = false
  }

}

struct UpdateInstallHelperPresentation: ViewModifier {
  @ObservedObject var presenter: UpdateInstallHelperAlert = .shared
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(AppStoreUpdateSettings.alwaysPerformManualUpdates.rawValue)
  private var alwaysOpenAppStore = false

  func body(content: Content) -> some View {
    content
      .alert(
        presenter.title,
        isPresented: Binding(
          get: { presenter.isPresented },
          set: { value in if presenter.isPresented != value { presenter.isPresented = value } })
      ) {
        if presenter.registrationError != nil {
          Button("OK", role: .cancel) { Task { @MainActor in presenter.cancel() } }
        } else {
          Button(presenter.primaryTitle) { Task { @MainActor in presenter.enableHelper() } }
            .keyboardShortcut(.defaultAction)
          Button(
            NSLocalizedString(
              "UpdateInstallHelperAlert.Secondary.AppStore", comment: "App Store fallback")
          ) {
            Task { @MainActor in presenter.openAppStore() }
          }
          Button(
            NSLocalizedString("UpdateInstallHelperAlert.Cancel", comment: "Cancel"), role: .cancel
          ) {
            Task { @MainActor in presenter.cancel() }
          }
        }
      } message: {
        Text(presenter.message)
      }
      .dialogSeverity(.standard)
      .dialogSuppressionToggle(
        NSLocalizedString(
          "UpdateInstallHelperAlert.SuppressionTitle", comment: "Always open App Store"),
        isSuppressed: $alwaysOpenAppStore
      )

      .onChange(of: scenePhase) { _, phase in
        if phase == .active { presenter.resumeIfAvailable() }
      }
  }
}
