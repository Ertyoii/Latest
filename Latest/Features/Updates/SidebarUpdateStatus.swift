// Fork contributions © 2026 ertyoii.
// Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI

/// One update-state subscription owns both the status dot and progress control.
struct SidebarUpdateStatus: View {
  let app: App
  let selection: UpdateRowSelection
  let showsSupportStatus: Bool
  let updating: any AppUpdating
  @State private var observed: ObservedState?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private struct ObservationKey: Equatable {
    let app: App.Bundle.Identifier
    let service: ObjectIdentifier
  }

  private struct ObservedState {
    let key: ObservationKey
    let presentation: UpdateActionPresentation
  }

  private var key: ObservationKey {
    ObservationKey(app: app.identifier, service: ObjectIdentifier(updating))
  }

  private var presentation: UpdateActionPresentation {
    if let observed, observed.key == key { return observed.presentation }
    return .make(for: app, progressState: updating.state(for: app.identifier))
  }

  var body: some View {
    Group {
      switch presentation {
      case .waiting(let status):
        TimelineView(.animation(paused: reduceMotion)) { context in
          SidebarIndicatorGlyph(
            fraction: nil,
            angle: reduceMotion
              ? 0
              : context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1) * 360,
            tint: Color(
              nsColor: selection.usesActiveSelectionColors
                ? .alternateSelectedControlTextColor : .tertiaryLabelColor))
        }
        .help(status)
        .accessibilityLabel(status)
      case .progress(let fraction, let status):
        Button {
          updating.cancel(app)
        } label: {
          Color.clear
        }
        .buttonStyle(SidebarProgressButtonStyle(fraction: fraction, selection: selection))
        .help(status)
        .accessibilityLabel(status)
        .accessibilityHint("Cancel update")
        .accessibilityIdentifier("updates.progress")
      case .update, .open, .failed:
        Image(nsImage: app.source.supportState.statusImage)
          .frame(width: 16, height: 16)
          .offset(y: -3)
          .opacity(showsSupportStatus ? 1 : 0)
          .help(app.source.supportState.label)
          .accessibilityLabel(app.source.supportState.label)
          .accessibilityHidden(!showsSupportStatus)
      }
    }
    .frame(width: 24, height: 24)
    .task(id: key) {
      let key = key
      for await state in updating.states(for: app.identifier) {
        guard !Task.isCancelled else { return }
        let next = ObservedState(key: key, presentation: .make(for: app, progressState: state))
        if observed?.key != key || observed?.presentation != next.presentation { observed = next }
      }
    }
  }
}

private struct SidebarProgressButtonStyle: ButtonStyle {
  let fraction: Double
  let selection: UpdateRowSelection
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    let color: NSColor =
      selection.usesActiveSelectionColors
      ? .alternateSelectedControlTextColor : .controlAccentColor
    SidebarIndicatorGlyph(
      fraction: fraction, angle: -90,
      tint: Color(nsColor: configuration.isPressed ? color.withSystemEffect(.pressed) : color)
    )
    .frame(width: 24, height: 24)
    .contentShape(Rectangle())
    .animation(reduceMotion ? nil : .linear(duration: 0.2), value: fraction)
  }
}

/// Uses the original 24-point control's paths and backing-pixel alignment.
private struct SidebarIndicatorGlyph: View, Animatable {
  var fraction: Double?
  let angle: Double
  let tint: Color
  @Environment(\.displayScale) private var displayScale
  @Environment(\.self) private var environment

  var animatableData: Double {
    get { fraction ?? 0 }
    set { if fraction != nil { fraction = newValue } }
  }

  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = size.height * 0.4
      context.withCGContext { cg in
        let resolvedTint = tint.resolve(in: environment).cgColor
        cg.setLineWidth(2.5)
        if let fraction {
          let minX = floor((center.x - radius) * displayScale) / displayScale
          let minY = floor((center.y - radius) * displayScale) / displayScale
          let maxX = ceil((center.x + radius) * displayScale) / displayScale
          let maxY = ceil((center.y + radius) * displayScale) / displayScale
          cg.setStrokeColor(Color(nsColor: .tertiaryLabelColor).resolve(in: environment).cgColor)
          cg.addPath(
            NSBezierPath(ovalIn: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
              .cgPath)
          cg.strokePath()
          cg.setFillColor(resolvedTint)
          for offset in [-2.0, 2.0] {
            cg.addPath(
              NSBezierPath(
                roundedRect:
                  CGRect(x: center.x + offset - 1, y: center.y - 4, width: 2, height: 8),
                xRadius: 1, yRadius: 1
              ).cgPath)
            cg.fillPath()
          }
          guard fraction > 0 else { return }
        }
        cg.setLineCap(.round)
        cg.setStrokeColor(resolvedTint)
        let arc = NSBezierPath()
        arc.appendArc(
          withCenter: center, radius: radius, startAngle: angle,
          endAngle: angle + (fraction.map { $0 * 360 } ?? 270))
        cg.addPath(arc.cgPath)
        cg.strokePath()
      }
    }
  }
}
