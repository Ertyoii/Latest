// Copyright © 2026 Max Langer and ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import Combine
import Foundation
import SwiftUI

/// Only interrupted updates reach this sheet. A healthy helper stays out of the way.
@MainActor
final class UpdateInstallHelperAlert: ObservableObject {
  static let shared = UpdateInstallHelperAlert()
  @Published var isPresented = false
  @Published private(set) var isChecking = false
  @Published private var error = InstallHelperError.installHelperNotRegistered
  private var updates: [(url: URL, start: () -> Void)] = []
  private var checkTask: Task<Void, Never>?
  private let helper: any InstallHelperServicing
  private let workspace: any ApplicationWorkspace

  init(
    helper: any InstallHelperServicing = LiveInstallHelperService.shared,
    workspace: any ApplicationWorkspace = MacApplicationWorkspace.shared
  ) {
    self.helper = helper
    self.workspace = workspace
  }

  func prepare(fallbackURL: URL, error: InstallHelperError, update: @escaping () -> Void) {
    let isFirst = updates.isEmpty
    updates.append((fallbackURL, update))
    guard isFirst else { return }
    self.error = error
    isPresented = true
  }

  var title: String {
    switch error {
    case .installHelperNotRegistered, .installHelperRequiresApproval: "Allow App Store updates"
    case .unavailable: "Continue in the App Store"
    }
  }

  var message: String {
    switch error {
    case .installHelperNotRegistered:
      "Give Latest permission to install App Store updates on this Mac."
    case .installHelperRequiresApproval:
      "Turn on Latest under Login Items & Extensions in System Settings. Your update will continue when you return."
    case .unavailable(let reason): reason
    }
  }

  var primaryTitle: String {
    switch error {
    case .installHelperNotRegistered: "Continue"
    case .installHelperRequiresApproval: "Open Settings"
    case .unavailable: "Open App Store"
    }
  }

  func performPrimaryAction() {
    switch error {
    case .installHelperNotRegistered, .installHelperRequiresApproval:
      check(register: true)
    case .unavailable:
      let url = updates.count > 1 ? AppStoreUpdateSettings.updatesPage : updates.first?.url
      cancel()
      if let url { workspace.open(url) }
    }
  }

  func resumeIfAvailable() {
    guard error == .installHelperRequiresApproval else { return }
    check(register: false)
  }

  private func check(register: Bool) {
    guard !updates.isEmpty, checkTask == nil else { return }
    isChecking = true
    checkTask = Task {
      do {
        if register { try helper.register() }
        try await helper.prepareForUpdates()
        try Task.checkCancellation()
        let ready = updates
        cancel()
        ready.forEach { $0.start() }
      } catch {
        guard !Task.isCancelled else { return }
        self.error = error as? InstallHelperError ?? .unavailable(error.localizedDescription)
        isChecking = false
        checkTask = nil
      }
    }
  }

  func cancel() {
    checkTask?.cancel()
    checkTask = nil
    updates.removeAll()
    isChecking = false
    isPresented = false
  }
}

struct UpdateInstallHelperPresentation: ViewModifier {
  @ObservedObject var presenter: UpdateInstallHelperAlert = .shared
  @Environment(\.scenePhase) private var scenePhase

  func body(content: Content) -> some View {
    content
      .sheet(
        isPresented: $presenter.isPresented,
        onDismiss: { if !presenter.isPresented { presenter.cancel() } }
      ) {
        VStack(alignment: .leading, spacing: 12) {
          Text(presenter.title).font(.headline)
          Text(presenter.message).fixedSize(horizontal: false, vertical: true)
          HStack {
            if presenter.isChecking { ProgressView().controlSize(.small) }
            Spacer()
            Button("Cancel", role: .cancel) { presenter.cancel() }
              .keyboardShortcut(.cancelAction)
            Button(presenter.primaryTitle) { presenter.performPrimaryAction() }
              .keyboardShortcut(.defaultAction)
              .disabled(presenter.isChecking)
          }
          .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 380, alignment: .leading)
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { presenter.resumeIfAvailable() }
      }
  }
}
