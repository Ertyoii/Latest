//
//  WindowAccessor.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
  let configure: (NSWindow) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    DispatchQueue.main.async {
      if let window = view.window {
        configure(window)
      }
    }
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    DispatchQueue.main.async {
      if let window = view.window {
        configure(window)
      }
    }
  }
}

/// A local capability bridge for the system-owned sidebar glass. SwiftUI does
/// not expose the generated surface's corner or window-edge alignment, so this
/// view walks only its own ancestor chain and adjusts the public glass view and
/// its public edge constraints. It never searches the wider SwiftUI hierarchy.
struct SidebarGlassGeometryAccessor: NSViewRepresentable {
  let cornerRadius: CGFloat
  let leadingLayoutInset: CGFloat

  func makeNSView(context: Context) -> SidebarGlassGeometryConfigurationView {
    SidebarGlassGeometryConfigurationView(
      cornerRadius: cornerRadius,
      leadingLayoutInset: leadingLayoutInset
    )
  }

  func updateNSView(_ view: SidebarGlassGeometryConfigurationView, context: Context) {
    view.cornerRadius = cornerRadius
    view.leadingLayoutInset = leadingLayoutInset
    view.scheduleConfiguration()
  }
}

@MainActor
final class SidebarGlassGeometryConfigurationView: NSView {
  var cornerRadius: CGFloat
  var leadingLayoutInset: CGFloat
  private var configurationIsScheduled = false

  init(cornerRadius: CGFloat, leadingLayoutInset: CGFloat) {
    self.cornerRadius = cornerRadius
    self.leadingLayoutInset = leadingLayoutInset
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    scheduleConfiguration()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    scheduleConfiguration()
  }

  override func layout() {
    super.layout()
    scheduleConfiguration()
  }

  func scheduleConfiguration() {
    guard !configurationIsScheduled else { return }
    configurationIsScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      configurationIsScheduled = false
      _ = configureNearestGlassAncestor()
    }
  }

  @discardableResult
  func configureNearestGlassAncestor() -> Bool {
    var ancestor = superview
    while let currentView = ancestor {
      if let glassView = currentView as? NSGlassEffectView {
        if abs(glassView.cornerRadius - cornerRadius) > 0.5 {
          glassView.cornerRadius = cornerRadius
        }
        configureLeadingLayout(of: glassView)
        return true
      }
      ancestor = currentView.superview
    }
    return false
  }

  private func configureLeadingLayout(of glassView: NSGlassEffectView) {
    guard let container = glassView.superview else { return }

    for constraint in container.constraints where constraint.isActive {
      if constraint.matches(
        first: glassView,
        attribute: .leading,
        second: container,
        attribute: .leading
      ) {
        constraint.setConstantIfNeeded(leadingLayoutInset)
      } else if constraint.matches(
        first: container,
        attribute: .leading,
        second: glassView,
        attribute: .leading
      ) {
        constraint.setConstantIfNeeded(-leadingLayoutInset)
      } else if constraint.matches(
        first: container,
        attribute: .width,
        second: glassView,
        attribute: .width
      ) {
        constraint.setConstantIfNeeded(leadingLayoutInset)
      } else if constraint.matches(
        first: glassView,
        attribute: .width,
        second: container,
        attribute: .width
      ) {
        constraint.setConstantIfNeeded(-leadingLayoutInset)
      }
    }
  }
}

extension NSLayoutConstraint {
  fileprivate func setConstantIfNeeded(_ target: CGFloat) {
    guard abs(constant - target) > 0.5 else { return }
    constant = target
  }

  fileprivate func matches(
    first firstView: NSView,
    attribute firstAttribute: NSLayoutConstraint.Attribute,
    second secondView: NSView,
    attribute secondAttribute: NSLayoutConstraint.Attribute
  ) -> Bool {
    (self.firstItem as? NSView) === firstView && self.firstAttribute == firstAttribute
      && (self.secondItem as? NSView) === secondView && self.secondAttribute == secondAttribute
  }
}
