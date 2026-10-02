// Copyright © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.
import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
  func makeNSView(context: Context) -> WindowConfigurationView { WindowConfigurationView() }
  func updateNSView(_ view: WindowConfigurationView, context: Context) {}
}

final class WindowConfigurationView: NSView {
  private weak var presentedSheet: NSWindow?
  deinit { NotificationCenter.default.removeObserver(self) }

  override init(frame: NSRect) { super.init(frame: frame) }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(self)
    if let window {
      MainWindowConfiguration.apply(to: window)
      NotificationCenter.default.addObserver(
        self, selector: #selector(sheetWillBegin(_:)),
        name: NSWindow.willBeginSheetNotification, object: window)
      NotificationCenter.default.addObserver(
        self, selector: #selector(sheetDidEnd(_:)),
        name: NSWindow.didEndSheetNotification, object: window)
    }
  }

  @objc private func sheetWillBegin(_ notification: Notification) {
    Task { @MainActor [weak self] in self?.presentedSheet = self?.window?.attachedSheet }
  }

  @objc private func sheetDidEnd(_ notification: Notification) {
    defer { presentedSheet = nil }
    guard let content = presentedSheet?.contentView,
      let checkbox = suppressionCheckbox(in: content)
    else { return }
    let isSuppressed = checkbox.state == .on
    // SwiftUI's native dialogSuppressionToggle discards Cancel/Escape changes.
    // Preserve the original alert's all-response preference without rendering
    // controls or tracking native focus in this existing window boundary.
    Task { @MainActor in
      AppStoreUpdateSettings.alwaysPerformManualUpdates.active = isSuppressed
    }
  }

  private func suppressionCheckbox(in view: NSView) -> NSButton? {
    if let button = view as? NSButton,
      button.title == NSLocalizedString("UpdateInstallHelperAlert.SuppressionTitle", comment: "")
    {
      return button
    }
    return view.subviews.lazy.compactMap { self.suppressionCheckbox(in: $0) }.first
  }
}
