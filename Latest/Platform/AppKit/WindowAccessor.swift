// Copyright © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.
import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
  func makeNSView(context: Context) -> ToolbarTitleView { ToolbarTitleView() }
  func updateNSView(_ view: ToolbarTitleView, context: Context) { view.updateTitle() }
  static func dismantleNSView(_ view: ToolbarTitleView, coordinator: ()) { view.removeTitle() }
}

final class ToolbarTitleView: NSView {
  private let titleField = ToolbarTitleField(
    labelWithString: NSLocalizedString("Updates", comment: "Main toolbar title"))

  override init(frame: NSRect) {
    super.init(frame: frame)
    titleField.font = .systemFont(ofSize: 15, weight: .semibold)
    titleField.textColor = .labelColor
    titleField.setAccessibilityIdentifier("toolbar.title")
    titleField.sizeToFit()
    addSubview(titleField)
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    removeTitle()
    if let window { MainWindowConfiguration.apply(to: window) }
    updateTitle()
  }
  override func layout() {
    super.layout()
    updateTitle()
  }
  func updateTitle() {
    guard let window, let contentView = window.contentView else { return }
    let windowBounds = contentView.convert(contentView.bounds, to: nil)
    let toolbar = NSRect(
      x: windowBounds.minX + VisualMetrics.sidebarIdealWidth,
      y: window.contentLayoutRect.maxY,
      width: max(0, windowBounds.width - VisualMetrics.sidebarIdealWidth),
      height: max(0, windowBounds.maxY - window.contentLayoutRect.maxY))
    let rect = convert(toolbar, from: nil).intersection(bounds)
    if titleField.superview !== self { addSubview(titleField) }
    let origin = NSPoint(
      x: rect.minX + VisualMetrics.detailHeaderHorizontalPadding,
      y: rect.midY - titleField.frame.height / 2)
    if titleField.frame.origin != origin { titleField.setFrameOrigin(origin) }
  }
  func removeTitle() { titleField.removeFromSuperview() }
}

/// The static title leaves titlebar dragging to the window.
private final class ToolbarTitleField: NSTextField {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
