// Fork contributions © 2026 ertyoii.
// Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI

/// SwiftUI owns layout and row actions. This bridge configures capabilities
/// SwiftUI does not expose: nonelastic scrolling and horizontal trackpad input.
struct SidebarScrollConfiguration: NSViewRepresentable {
  var horizontalScroll: (CGFloat, CGFloat, Bool) -> Void

  func makeNSView(context: Context) -> ConfigurationView {
    ConfigurationView(horizontalScroll: horizontalScroll)
  }

  func updateNSView(_ view: ConfigurationView, context: Context) {
    view.horizontalScroll = horizontalScroll
    view.configure()
  }

  static func dismantleNSView(_ view: ConfigurationView, coordinator: ()) {
    view.removeMonitor()
  }

  final class ConfigurationView: NSView {
    var horizontalScroll: (CGFloat, CGFloat, Bool) -> Void
    private var monitor: Any?
    private var horizontal: Bool?
    private var gestureY: CGFloat = 0
    private var wheelEnd: Task<Void, Never>?

    init(horizontalScroll: @escaping (CGFloat, CGFloat, Bool) -> Void) {
      self.horizontalScroll = horizontalScroll
      super.init(frame: .zero)
      setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      configure()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil { removeMonitor() } else { configure() }
    }

    override func layout() {
      super.layout()
      configure()
    }

    func configure() {
      guard let scroll = enclosingScrollView else { return }
      scroll.scrollerStyle = .overlay
      scroll.autohidesScrollers = true
      scroll.verticalScrollElasticity = .none
      scroll.horizontalScrollElasticity = .none
      if monitor == nil, window != nil {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
          guard let self else { return event }
          return self.handle(event)
        }
      }
    }

    func removeMonitor() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      horizontal = nil
      wheelEnd?.cancel()
      wheelEnd = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
      guard let window, let scroll = enclosingScrollView else { return event }
      let location: NSPoint
      if let eventWindow = event.window {
        guard eventWindow === window else { return event }
        location = event.locationInWindow
      } else {
        // Scroll events can carry screen coordinates without a window number.
        // Keep those events scoped to the frontmost window under the pointer.
        let screenPoint = event.locationInWindow
        guard NSApp.orderedWindows.first(where: { $0.frame.contains(screenPoint) }) === window
        else { return event }
        location = window.convertPoint(fromScreen: screenPoint)
      }
      let clip = scroll.contentView
      let point = clip.convert(location, from: nil)
      guard clip.bounds.contains(point) else { return event }
      if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
        wheelEnd?.cancel()
        horizontal = nil
      }
      let dx = event.scrollingDeltaX
      let dy = event.scrollingDeltaY
      if horizontal == nil, dx != 0 || dy != 0 {
        horizontal = abs(dx) > abs(dy)
        let y = clip.isFlipped ? point.y : clip.bounds.maxY - point.y + clip.bounds.minY
        gestureY = y
      }
      guard horizontal == true else {
        if event.phase.isEmpty || event.phase.contains(.ended) || event.phase.contains(.cancelled) {
          horizontal = nil
        }
        return event
      }
      // Momentum must not reopen an action after the user's fingers lift.
      guard event.momentumPhase.isEmpty else { return nil }
      let finished = event.phase.contains(.ended) || event.phase.contains(.cancelled)
      horizontalScroll(gestureY, dx, finished)
      // Mouse wheels and VM input have no gesture phase. Settle a burst only
      // after input stops, so small deltas accumulate into the same swipe.
      if event.phase.isEmpty {
        wheelEnd?.cancel()
        wheelEnd = Task { @MainActor [weak self] in
          try? await Task.sleep(for: .milliseconds(120))
          guard !Task.isCancelled, let self else { return }
          self.horizontalScroll(self.gestureY, 0, true)
          self.horizontal = nil
        }
      }
      return nil
    }
  }
}
