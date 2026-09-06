//
//  UpdateActionView.swift
//  Latest
//
//  Created by Codex on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Combine
import SwiftUI

@MainActor
enum UpdateActionPresentation: Equatable {
  case update
  case open
  case waiting(String)
  case progress(fraction: Double, status: String)
  case failed(String)

  static func make(for app: App, progressState: UpdateProgressState) -> Self {
    switch progressState {
    case .none:
      return app.updateAvailable ? .update : .open
    case .pending:
      return .waiting(
        NSLocalizedString(
          "WaitingUpdateStatus",
          comment: "Update progress state of waiting to start an update"
        ))
    case .initializing:
      return .waiting(
        NSLocalizedString(
          "InitializingUpdateStatus",
          comment: "Update progress state of initializing an update"
        ))
    case .downloading(let loadedSize, let totalSize):
      let denominator = max(totalSize, 1)
      let fraction = min(max(Double(loadedSize) / Double(denominator), 0), 1) * 0.75
      let format = NSLocalizedString(
        "DownloadingUpdateStatus",
        comment: "Update progress state of downloading an update"
      )
      let status = String.localizedStringWithFormat(
        format,
        Self.byteFormatter.string(fromByteCount: loadedSize),
        Self.byteFormatter.string(fromByteCount: totalSize)
      )
      return .progress(fraction: fraction, status: status)
    case .extracting(let progress):
      return .progress(
        fraction: min(max(0.75 + (progress * 0.25), 0), 1),
        status: NSLocalizedString(
          "ExtractingUpdateStatus",
          comment: "Update progress state of extracting the downloaded update"
        )
      )
    case .installing:
      return .waiting(
        NSLocalizedString(
          "InstallingUpdateStatus",
          comment: "Update progress state of installing an update"
        ))
    case .error(let error):
      return .failed(error.localizedDescription)
    case .cancelling:
      return .waiting(
        NSLocalizedString(
          "CancellingUpdateStatus",
          comment: "Update progress state of cancelling an update"
        ))
    }
  }

  private static let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter
  }()
}

@MainActor
final class UpdateActionViewModel: ObservableObject {
  struct PresentedError: Identifiable {
    let id = UUID()
    let description: String
  }

  let app: App
  @Published private(set) var presentation: UpdateActionPresentation
  @Published var presentedError: PresentedError?

  private var observationTask: Task<Void, Never>?
  private let workspace: any ApplicationWorkspace
  private let updating: any AppUpdating

  init(
    app: App,
    workspace: any ApplicationWorkspace = MacApplicationWorkspace.shared,
    updating: any AppUpdating = AppUpdateService.shared
  ) {
    self.app = app
    self.workspace = workspace
    self.updating = updating
    let feed = updating.stateChanges(for: app.identifier)
    _presentation = Published(
      initialValue: .make(
        for: app,
        progressState: feed.current
      ))
    observationTask = Task { [weak self] in
      for await state in feed.changes {
        guard !Task.isCancelled, let self else { break }
        self.presentation = .make(for: app, progressState: state)
      }
    }
  }

  deinit {
    observationTask?.cancel()
  }

  func performAction() {
    switch presentation {
    case .update:
      updating.update(app)
    case .open:
      workspace.openApplication(at: app.fileURL)
    case .progress:
      updating.cancel(app)
    case .failed(let description):
      presentedError = PresentedError(description: description)
    case .waiting:
      break
    }
  }

  func retry() {
    updating.update(app)
  }
}

struct UpdateActionView: View {
  @StateObject private var viewModel: UpdateActionViewModel

  init(
    app: App,
    workspace: any ApplicationWorkspace = MacApplicationWorkspace.shared,
    updating: any AppUpdating = AppUpdateService.shared
  ) {
    _viewModel = StateObject(
      wrappedValue: UpdateActionViewModel(app: app, workspace: workspace, updating: updating))
  }

  var body: some View {
    UpdateActionSurface(
      app: viewModel.app,
      presentation: viewModel.presentation,
      performAction: viewModel.performAction
    )
    .alert(item: $viewModel.presentedError) { error in
      Alert(
        title: Text(
          String.localizedStringWithFormat(
            NSLocalizedString(
              "UpdateErrorAlertTitle",
              comment: "Title of alert stating that an app update failed"
            ),
            viewModel.app.name
          )),
        message: Text(error.description),
        primaryButton: .default(Text(NSLocalizedString("RetryAction", comment: "Retry update"))) {
          viewModel.retry()
        },
        secondaryButton: .cancel()
      )
    }
  }
}

/// Stateless rendering for the update action. Keeping queue observation and side effects
/// outside this view makes every visual state deterministic in tests and the migration gallery.
struct UpdateActionSurface: View {
  let app: App
  let presentation: UpdateActionPresentation
  let pausesAnimations: Bool
  let performAction: () -> Void

  init(
    app: App,
    presentation: UpdateActionPresentation,
    pausesAnimations: Bool = false,
    performAction: @escaping () -> Void
  ) {
    self.app = app
    self.presentation = presentation
    self.pausesAnimations = pausesAnimations
    self.performAction = performAction
  }

  var body: some View {
    VStack(spacing: 5) {
      UpdateActionControl(
        appName: app.name,
        presentation: presentation,
        pausesAnimations: pausesAnimations,
        performAction: performAction
      )
      .frame(
        width: VisualMetrics.detailUpdateButtonWidth,
        height: VisualMetrics.detailUpdateButtonHeight
      )

      if app.updateAvailable,
        let externalUpdaterName = app.externalUpdaterName
      {
        Text(
          String(
            format: NSLocalizedString(
              "ExternalUpdateActionWithAppName",
              comment: "Explanatory label below an external update button"
            ),
            externalUpdaterName
          )
        )
        .font(.system(size: NSFont.systemFontSize(for: .mini)))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
      }
    }
    .frame(width: VisualMetrics.detailUpdateButtonWidth, height: VisualMetrics.detailIconSize)
  }
}

@MainActor
enum UpdateActionVisualStyle {
  static let backgroundColor = NSColor(
    srgbRed: 0.9488552213,
    green: 0.9487094283,
    blue: 0.9693081975,
    alpha: 1
  )
  static let highlightedBackgroundColor = NSColor(
    srgbRed: 0.7995074391,
    green: 0.8113409281,
    blue: 0.8403512836,
    alpha: 1
  )
  static let capsuleHorizontalInset: CGFloat = 0.25
  static let progressDiameter: CGFloat = 20
  static let progressLineWidth: CGFloat = 2.5
  static let pauseBarSize = CGSize(width: 2, height: 8)
  static let pauseBarSpacing: CGFloat = 2
}

private struct UpdateActionControl: View {
  let appName: String
  let presentation: UpdateActionPresentation
  let pausesAnimations: Bool
  let performAction: () -> Void

  @ViewBuilder
  var body: some View {
    switch presentation {
    case .update:
      UpdateActionCapsuleButton(
        content: .title(NSLocalizedString("UpdateAction", comment: "Action to update an app")),
        accessibilityLabel: "Update \(appName)",
        performAction: performAction
      )
    case .open:
      UpdateActionCapsuleButton(
        content: .title(NSLocalizedString("OpenAction", comment: "Action to open an app")),
        accessibilityLabel: "Open \(appName)",
        performAction: performAction
      )
    case .waiting(let status):
      UpdateActionIndeterminateIndicator(pausesAnimations: pausesAnimations)
        .help(status)
        .accessibilityLabel(status)
    case .progress(let fraction, let status):
      Button {
        performAction()
      } label: {
        UpdateActionProgressIndicator(fraction: fraction)
      }
      .buttonStyle(.plain)
      .help(status)
      .accessibilityLabel(status)
      .accessibilityHint("Cancel update")
    case .failed:
      UpdateActionCapsuleButton(
        content: .image(
          NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: nil
          )),
        accessibilityLabel: NSLocalizedString(
          "ErrorButtonAccessibilityTitle",
          comment: "Description of button that opens an error dialogue"
        ),
        performAction: performAction
      )
    }
  }
}

/// Narrow public-AppKit drawing bridge for the established action capsule.
/// SwiftUI continues to own state and actions; AppKit is used only for the
/// reference title, symbol, pill, and pressed-state rasterization.
private struct UpdateActionCapsuleButton: NSViewRepresentable {
  enum Content {
    case title(String)
    case image(NSImage?)
  }

  let content: Content
  let accessibilityLabel: String
  let performAction: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(performAction: performAction)
  }

  func makeNSView(context: Context) -> CapsuleHostView {
    let button = PixelMatchedActionButton(frame: .zero)
    button.cell = PixelMatchedActionButtonCell()
    button.target = context.coordinator
    button.action = #selector(Coordinator.performAction(_:))
    button.isBordered = false
    button.contentTintColor = .controlAccentColor
    configure(button)
    return CapsuleHostView(button: button)
  }

  func updateNSView(_ hostView: CapsuleHostView, context: Context) {
    context.coordinator.performAction = performAction
    configure(hostView.button)
  }

  private func configure(_ button: PixelMatchedActionButton) {
    button.backgroundColor = UpdateActionVisualStyle.backgroundColor
    button.setAccessibilityLabel(accessibilityLabel)
    switch content {
    case .title(let title):
      button.title = title
      button.image = nil
    case .image(let image):
      button.title = ""
      button.image = image
    }
  }

  @MainActor
  final class CapsuleHostView: NSView {
    let button: PixelMatchedActionButton

    init(button: PixelMatchedActionButton) {
      self.button = button
      super.init(frame: .zero)
      addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
      super.layout()
      button.frame = bounds.insetBy(dx: UpdateActionVisualStyle.capsuleHorizontalInset, dy: 0)
    }
  }

  @MainActor
  final class Coordinator: NSObject {
    var performAction: () -> Void

    init(performAction: @escaping () -> Void) {
      self.performAction = performAction
    }

    @objc func performAction(_ sender: Any?) {
      performAction()
    }
  }
}

@MainActor
private final class PixelMatchedActionButton: NSButton {
  var backgroundColor = UpdateActionVisualStyle.backgroundColor {
    didSet { needsDisplay = true }
  }
}

private final class PixelMatchedActionButtonCell: NSButtonCell {
  override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
    super.highlight(flag, withFrame: cellFrame, in: controlView)
    guard let button = controlView as? PixelMatchedActionButton else { return }
    button.backgroundColor =
      flag
      ? UpdateActionVisualStyle.highlightedBackgroundColor
      : UpdateActionVisualStyle.backgroundColor
  }

  override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
    guard let button = controlView as? PixelMatchedActionButton else { return }
    let radius = cellFrame.height / 2
    button.backgroundColor.setFill()
    NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius).fill()
    super.drawInterior(withFrame: cellFrame, in: controlView)
  }

  override func drawTitle(
    _ title: NSAttributedString,
    withFrame frame: NSRect,
    in controlView: NSView
  ) -> NSRect {
    let string = NSMutableAttributedString(attributedString: title)
    let range = NSRange(location: 0, length: string.length)
    string.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
    let pointSize = font?.pointSize ?? NSFont.systemFontSize
    string.addAttribute(
      .font,
      value: NSFont.systemFont(ofSize: pointSize - 1, weight: .medium),
      range: range
    )
    var adjustedFrame = frame
    adjustedFrame.origin.y -= 1
    return super.drawTitle(string, withFrame: adjustedFrame, in: controlView)
  }

  override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
    var adjustedFrame = frame
    adjustedFrame.origin.y -= 1
    super.drawImage(image, withFrame: adjustedFrame, in: controlView)
  }
}

private struct UpdateActionIndeterminateIndicator: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let pausesAnimations: Bool

  var body: some View {
    TimelineView(.animation(paused: reduceMotion || pausesAnimations)) { context in
      Circle()
        .trim(from: 0, to: 0.75)
        .stroke(
          Color(nsColor: .tertiaryLabelColor),
          style: StrokeStyle(
            lineWidth: UpdateActionVisualStyle.progressLineWidth,
            lineCap: .round
          )
        )
        .rotationEffect(
          .degrees(
            reduceMotion || pausesAnimations
              ? 90 : context.date.timeIntervalSinceReferenceDate * 360
          ))
    }
    .frame(
      width: UpdateActionVisualStyle.progressDiameter,
      height: UpdateActionVisualStyle.progressDiameter
    )
  }
}

private struct UpdateActionProgressIndicator: View {
  let fraction: Double

  var body: some View {
    ZStack {
      Circle()
        .stroke(
          Color(nsColor: .tertiaryLabelColor),
          lineWidth: UpdateActionVisualStyle.progressLineWidth
        )
      Circle()
        .trim(from: 0, to: fraction)
        .stroke(
          Color(nsColor: .controlAccentColor),
          style: StrokeStyle(
            lineWidth: UpdateActionVisualStyle.progressLineWidth,
            lineCap: .round
          )
        )
        .rotationEffect(.degrees(-90))

      HStack(spacing: UpdateActionVisualStyle.pauseBarSpacing) {
        ForEach(0..<2, id: \.self) { _ in
          RoundedRectangle(cornerRadius: 1)
            .fill(Color(nsColor: .controlAccentColor))
            .frame(
              width: UpdateActionVisualStyle.pauseBarSize.width,
              height: UpdateActionVisualStyle.pauseBarSize.height
            )
        }
      }
    }
    .frame(
      width: UpdateActionVisualStyle.progressDiameter,
      height: UpdateActionVisualStyle.progressDiameter
    )
  }
}
