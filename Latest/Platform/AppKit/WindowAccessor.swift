// Copyright © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.
import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
  func makeNSView(context: Context) -> WindowConfigurationView { WindowConfigurationView() }
  func updateNSView(_ view: WindowConfigurationView, context: Context) {}
}

final class WindowConfigurationView: NSView {
  override init(frame: NSRect) { super.init(frame: frame) }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let window { MainWindowConfiguration.apply(to: window) }
  }
}
