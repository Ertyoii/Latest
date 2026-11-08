// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI

/// Keep AppKit's first key-view evaluation from activating a text field before
/// SwiftUI's focus targets are ready. Hand off once to the requested SwiftUI focus.
struct InitialWindowFocus: NSViewRepresentable {
  let focus: () -> Void

  func makeNSView(context: Context) -> FocusView {
    FocusView(focus: focus)
  }

  func updateNSView(_ view: FocusView, context: Context) {
    view.focus = focus
  }

  final class FocusView: NSView {
    var focus: () -> Void
    private var didFocus = false

    init(focus: @escaping () -> Void) {
      self.focus = focus
      super.init(frame: .zero)
      setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { !didFocus }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let window, !window.isVisible, !didFocus else { return }
      window.initialFirstResponder = self
    }

    override func becomeFirstResponder() -> Bool {
      guard !didFocus else { return false }
      didFocus = true
      Task { @MainActor [weak self] in
        guard let self, let window, window.firstResponder === self else { return }
        focus()
      }
      return true
    }
  }
}
