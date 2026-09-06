//
//  MigrationInteractionContractTest.swift
//  Latest Tests
//
//  Created by ertyoii on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//
//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-08-01.
//  Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import XCTest

@testable import Latest

final class MigrationInteractionContractTest: XCTestCase {
  func testApplicationAppearanceResolvesStoredPreference() {
    XCTAssertNil(ApplicationAppearance.system.appKitAppearanceName)
    XCTAssertEqual(ApplicationAppearance.light.appKitAppearanceName, .aqua)
    XCTAssertEqual(ApplicationAppearance.dark.appKitAppearanceName, .darkAqua)
    XCTAssertEqual(ApplicationAppearance.resolve("dark"), .dark)
    XCTAssertEqual(ApplicationAppearance.resolve("invalid"), .system)
    XCTAssertEqual(ApplicationAppearance.allCases.map(\.title), ["System", "Light", "Dark"])
  }

  @MainActor
  func testApplicationAppearanceCanReturnFromDarkToSystem() {
    let application = NSApplication.shared
    let originalAppearance = application.appearance
    defer { application.appearance = originalAppearance }

    ApplicationAppearance.dark.apply(to: application)
    XCTAssertEqual(application.appearance?.name, .darkAqua)

    ApplicationAppearance.system.apply(to: application)
    XCTAssertNil(application.appearance)
  }

  @MainActor
  func testGeneralSettingsContentMakesRoomForAppearanceSelector() {
    XCTAssertEqual(SettingsViewModel.Tab.general.contentSize, CGSize(width: 440, height: 255))
  }

  @MainActor
  func testLocalUATFixtureIsOfflinePopulatedAndSelected() {
    let environment = AppEnvironment.localUATFixture()
    let apps = environment.updatesListViewModel.snapshot.apps
    XCTAssertEqual(apps.count, 18)
    XCTAssertEqual(
      environment.updatesListViewModel.selectedApp?.name,
      environment.updatesListViewModel.snapshot.sections.first?.apps.first?.name
    )
    XCTAssertTrue(apps.allSatisfy { $0.releaseNotes != nil })
    XCTAssertTrue(apps.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
    XCTAssertEqual(
      Set(apps.map(\.fileURL)).count, apps.count, "UAT must exercise distinct real app icons")
  }

  @MainActor
  func testUpdateProgressAggregatesOverlappingBatches() {
    let service = UpdateCheckingService()
    let coordinator = UpdateCheckCoordinator()

    service.updateCheckerDidStartScanningForApps(coordinator)
    service.updateChecker(coordinator, didStartCheckingApps: 4, generation: 1)
    service.updateChecker(coordinator, didStartCheckingApps: 1, generation: 1)

    XCTAssertTrue(service.isRunning)
    XCTAssertFalse(service.isIndeterminate)
    XCTAssertEqual(service.totalApps, 5)

    service.updateCheckerDidFinishCheckingForUpdates(coordinator, generation: 1)
    XCTAssertTrue(service.isRunning)

    service.updateCheckerDidFinishCheckingForUpdates(coordinator, generation: 1)
    XCTAssertFalse(service.isRunning)
  }

  @MainActor
  func testReplacementBatchDiscardsProgressForCancelledGeneration() {
    let service = UpdateCheckingService()
    let coordinator = UpdateCheckCoordinator()

    service.updateCheckerDidStartScanningForApps(coordinator)
    service.updateChecker(coordinator, didStartCheckingApps: 38, generation: 1)
    service.updateChecker(coordinator, didCheckApp: makeApp(name: "Checked", version: "1"))

    service.updateChecker(coordinator, didStartCheckingApps: 1, generation: 2)

    XCTAssertTrue(service.isRunning)
    XCTAssertEqual(service.checkedApps, 0)
    XCTAssertEqual(service.totalApps, 1)

    service.updateCheckerDidFinishCheckingForUpdates(coordinator, generation: 1)
    XCTAssertTrue(service.isRunning)

    service.updateCheckerDidFinishCheckingForUpdates(coordinator, generation: 2)
    XCTAssertFalse(service.isRunning)
  }

  @MainActor
  func testNativeLocationsTableOwnsSelectionAndRowSemantics() throws {
    let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    let unavailableURL = URL(fileURLWithPath: "/Volumes/Unavailable Apps", isDirectory: true)
    let selection = SelectionBox()
    let view = DirectoryLocationsTable(
      urls: [applicationsURL, unavailableURL],
      selection: Binding(
        get: { selection.url },
        set: { selection.url = $0 }
      ),
      loadDetails: { url in
        DirectoryLocationDetails(
          isReachable: url == applicationsURL,
          appCount: url == applicationsURL ? 38 : 0
        )
      }
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
    let window = NSWindow(
      contentRect: hostingView.bounds,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = hostingView
    window.makeKeyAndOrderFront(nil)
    window.layoutIfNeeded()
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

    let tableView = try XCTUnwrap(hostingView.descendant(of: NSTableView.self))
    XCTAssertEqual(tableView.numberOfRows, 2)
    tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    XCTAssertEqual(selection.url, unavailableURL)

    XCTAssertEqual(
      DirectoryLocationPresentation.accessibilityLabel(
        for: applicationsURL,
        details: DirectoryLocationDetails(isReachable: true, appCount: 38)
      ),
      "/Applications, 38 applications"
    )
    XCTAssertEqual(
      DirectoryLocationPresentation.accessibilityLabel(
        for: unavailableURL,
        details: DirectoryLocationDetails(isReachable: false, appCount: 0)
      ),
      "/Volumes/Unavailable Apps, unavailable, 0 applications"
    )
  }

  @MainActor
  func testCommandFPublishesSystemSidebarSearchFocusRequest() {
    let focusController = SearchFocusController()
    let viewModel = UpdatesListViewModel()
    let commands = AppCommands(
      updateCheckingService: UpdateCheckingService(),
      updatesListViewModel: viewModel,
      searchFocusController: focusController
    )
    commands.focusSearch()
    guard case .focus = focusController.request else {
      return XCTFail("Expected Command-F to publish a focus request")
    }
  }

  @MainActor
  func testExplicitSearchResignPublishesANewFocusRequest() {
    let focusController = SearchFocusController()
    focusController.focus()
    let focusRequest = focusController.request

    focusController.resignFocus()
    XCTAssertNotEqual(focusController.request, focusRequest)
    guard case .resign = focusController.request else {
      return XCTFail("Expected an explicit resign request")
    }
  }

  @MainActor
  func testShippingTableArrowMovementSkipsSectionHeaders() throws {
    let (window, table, viewModel) = try makeShippingSidebar()
    defer { window.close() }
    let appRows = viewModel.snapshot.entries.indices.filter {
      if case .app = viewModel.snapshot.entries[$0] { return true }
      return false
    }
    XCTAssertEqual(appRows.count, 2)
    table.selectRowIndexes(IndexSet(integer: appRows[0]), byExtendingSelection: false)
    func pressArrow(keyCode: UInt16, character: String) throws {
      let event = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
          timestamp: 0, windowNumber: window.windowNumber, context: nil,
          characters: character, charactersIgnoringModifiers: character,
          isARepeat: false, keyCode: keyCode
        ))
      table.keyDown(with: event)
    }
    window.makeFirstResponder(table)
    try pressArrow(keyCode: 125, character: "\u{F701}")
    XCTAssertEqual(table.selectedRow, appRows[1])
    XCTAssertEqual(
      viewModel.selectedApp?.identifier, viewModel.snapshot.sections.last?.apps.first?.identifier)
    try pressArrow(keyCode: 126, character: "\u{F700}")
    XCTAssertEqual(table.selectedRow, appRows[0])
  }

  @MainActor
  func testIdentifierSelectionUsesStableApplicationURLs() {
    let first = makeApp(name: "Discord", version: "1", remoteVersion: "2")
    let second = makeApp(name: "Cursor", version: "3", remoteVersion: "4")
    let viewModel = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: [first, second], filterQuery: nil)
    )

    viewModel.select(identifier: second.identifier)
    XCTAssertEqual(viewModel.selectedApp?.identifier, second.identifier)
    viewModel.select(identifier: URL(fileURLWithPath: "/Applications/Missing.app"))
    XCTAssertNil(viewModel.selectedApp)
  }

  @MainActor
  func testContextMenuPrefersClickedRowAndFallsBackToSelection() throws {
    let selectedApp = makeApp(name: "Discord", version: "1", remoteVersion: "2")
    let clickedApp = makeApp(name: "Cursor", version: "3")
    let snapshot = AppListSnapshot(withApps: [selectedApp, clickedApp], filterQuery: nil)
    let policy = SidebarInteractionPolicy(entries: snapshot.entries)
    let selectedRow = try XCTUnwrap(snapshot.firstIndex(of: selectedApp))
    let clickedRow = try XCTUnwrap(snapshot.firstIndex(of: clickedApp))
    let sectionRow = try XCTUnwrap(
      snapshot.entries.indices.first(where: policy.isSectionHeader(row:)))

    XCTAssertTrue(policy.targetApp(clickedRow: clickedRow, selectedRow: selectedRow) === clickedApp)
    XCTAssertTrue(
      policy.targetApp(clickedRow: sectionRow, selectedRow: selectedRow) === selectedApp)
    XCTAssertTrue(policy.targetApp(clickedRow: -1, selectedRow: selectedRow) === selectedApp)
  }

  @MainActor
  func testSwipeActionsPreserveAvailabilityRules() throws {
    let updatable = makeApp(name: "Discord", version: "1", remoteVersion: "2")
    let installed = makeApp(name: "Cursor", version: "3")
    let snapshot = AppListSnapshot(withApps: [updatable, installed], filterQuery: nil)
    let policy = SidebarInteractionPolicy(entries: snapshot.entries)
    let updatableRow = try XCTUnwrap(snapshot.firstIndex(of: updatable))
    let installedRow = try XCTUnwrap(snapshot.firstIndex(of: installed))
    let leadingActions: [SidebarInteractionPolicy.Action] = [.open, .revealInFinder]
    let trailingUpdateActions: [SidebarInteractionPolicy.Action] = [.update]

    XCTAssertEqual(policy.swipeActions(for: updatableRow, edge: .leading), leadingActions)
    XCTAssertEqual(policy.swipeActions(for: updatableRow, edge: .trailing), trailingUpdateActions)
    XCTAssertEqual(policy.swipeActions(for: installedRow, edge: .trailing), [])
  }

  @MainActor
  func testSidebarRowBuildsACombinedVoiceOverLabel() {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let app = makeApp(
      name: "Discord",
      version: "1",
      remoteVersion: "2",
      date: Date(timeIntervalSince1970: 1_750_000_000)
    )

    let label = SidebarInteractionPolicy.accessibilityLabel(for: app, dateFormatter: formatter)
    XCTAssertTrue(label.contains("Discord"))
    XCTAssertTrue(label.contains("1"))
    XCTAssertTrue(label.contains("2"))
    XCTAssertTrue(label.contains("2025-06-15"))
    XCTAssertTrue(label.contains(NSLocalizedString("UpdateAction", comment: "")))
  }

  @MainActor
  func testStartupActivatesReleaseNotesCatalogBeforeInitialUpdateCheck() async {
    var events = [String]()
    await AppStartupSequence.run(
      refreshCatalog: {
        events.append("catalog")
        await Task.yield()
        events.append("catalog-ready")
      },
      checkForUpdates: {
        events.append("check")
      }
    )

    XCTAssertEqual(events, ["catalog", "catalog-ready", "check"])
  }

  @MainActor
  func testReleaseNotesTextPreservesRichTextSelectionCopyAndAccessibility() throws {
    let source = NSMutableAttributedString(string: "Bold link\tbody\nSecond paragraph")
    let fullRange = NSRange(location: 0, length: source.length)
    let linkRange = (source.string as NSString).range(of: "link")
    let originalParagraphStyle = NSMutableParagraphStyle()
    originalParagraphStyle.firstLineHeadIndent = 32
    originalParagraphStyle.headIndent = 24
    originalParagraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: 48)]
    source.addAttributes(
      [
        .font: NSFont.boldSystemFont(ofSize: 22),
        .backgroundColor: NSColor.systemYellow,
        .shadow: NSShadow(),
        .paragraphStyle: originalParagraphStyle,
      ], range: fullRange)
    source.addAttribute(.link, value: URL(string: "https://example.com/release")!, range: linkRange)

    let formatted = ReleaseNotesTextFormatter.format(source)
    XCTAssertEqual(formatted.string, "Bold link body\nSecond paragraph")
    XCTAssertEqual(
      formatted.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL,
      URL(string: "https://example.com/release")
    )
    let formattedFont = try XCTUnwrap(
      formatted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )
    XCTAssertTrue(formattedFont.fontDescriptor.symbolicTraits.contains(.bold))
    XCTAssertEqual(formattedFont.pointSize, NSFont.systemFontSize)
    XCTAssertNil(formatted.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    XCTAssertNil(formatted.attribute(.shadow, at: 0, effectiveRange: nil))
    let paragraphStyle = try XCTUnwrap(
      formatted.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    )
    XCTAssertEqual(paragraphStyle.alignment, .left)
    XCTAssertEqual(paragraphStyle.firstLineHeadIndent, 0)
    XCTAssertEqual(paragraphStyle.headIndent, 0)
    XCTAssertTrue(paragraphStyle.tabStops.isEmpty)

    let hostingView = NSHostingView(rootView: SelectableReleaseNotesTextView(text: source))
    hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 280)
    let window = NSWindow(
      contentRect: hostingView.bounds,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = hostingView
    window.layoutIfNeeded()
    hostingView.layoutSubtreeIfNeeded()
    XCTAssertNotNil(hostingView.descendant(of: NSScrollView.self))
    let textView = try XCTUnwrap(hostingView.descendant(of: NSTextView.self))
    XCTAssertTrue(textView.isSelectable)
    XCTAssertFalse(textView.isEditable)
    XCTAssertEqual(textView.string, formatted.string)
    XCTAssertEqual(
      textView.textStorage?.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL,
      URL(string: "https://example.com/release")
    )
  }

  @MainActor
  func testUpdateActionPresentationCoversEveryOperationState() {
    let updatable = makeApp(name: "Discord", version: "1", remoteVersion: "2")
    let installed = makeApp(name: "Cursor", version: "3")

    XCTAssertEqual(UpdateActionPresentation.make(for: updatable, progressState: .none), .update)
    XCTAssertEqual(UpdateActionPresentation.make(for: installed, progressState: .none), .open)
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .pending))
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .initializing))
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .installing))
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .cancelling))

    guard
      case .progress(let downloadFraction, let downloadStatus) = UpdateActionPresentation.make(
        for: updatable,
        progressState: .downloading(loadedSize: 25, totalSize: 100)
      )
    else {
      return XCTFail("Expected the download state to produce determinate progress.")
    }
    XCTAssertEqual(downloadFraction, 0.1875, accuracy: 0.0001)
    XCTAssertFalse(downloadStatus.isEmpty)

    guard
      case .progress(let extractionFraction, let extractionStatus) = UpdateActionPresentation.make(
        for: updatable,
        progressState: .extracting(progress: 0.5)
      )
    else {
      return XCTFail("Expected the extraction state to produce determinate progress.")
    }
    XCTAssertEqual(extractionFraction, 0.875, accuracy: 0.0001)
    XCTAssertFalse(extractionStatus.isEmpty)

    let error = NSError(
      domain: "LatestMigration", code: 7,
      userInfo: [
        NSLocalizedDescriptionKey: "The update failed"
      ])
    XCTAssertEqual(
      UpdateActionPresentation.make(for: updatable, progressState: .error(error)),
      .failed("The update failed")
    )
  }

  @MainActor
  func testDetailViewModelOwnsLoadingSuccessEmptyErrorAndStaleRequestStates() async throws {
    let provider = ReleaseNotesProviderProbe()
    let viewModel = ReleaseNotesDetailViewModel(releaseNotesProvider: provider)
    let firstApp = makeApp(name: "Discord", version: "1", remoteVersion: "2")
    let secondApp = makeApp(name: "Cursor", version: "3", remoteVersion: "4")

    viewModel.display(firstApp)
    XCTAssertEqual(provider.requests.count, 1)
    try await Task.sleep(for: .milliseconds(230))
    guard case .loading = viewModel.contentState else {
      return XCTFail("Expected delayed loading state.")
    }

    let firstText = NSAttributedString(string: "First release notes")
    provider.completeRequest(at: 0, with: .success(firstText))
    guard case .text(let displayedText) = viewModel.contentState else {
      return XCTFail("Expected release notes text.")
    }
    XCTAssertEqual(displayedText.string, firstText.string)

    viewModel.display(secondApp)
    XCTAssertEqual(provider.requests.count, 2)
    provider.completeRequest(at: 0, with: .success(NSAttributedString(string: "Stale text")))
    guard case .text(let textAfterStaleCompletion) = viewModel.contentState else {
      return XCTFail("A stale request must not replace the current detail state.")
    }
    XCTAssertEqual(textAfterStaleCompletion.string, firstText.string)

    provider.completeRequest(at: 1, with: .success(NSAttributedString(string: "  \n")))
    guard case .message(let emptyMessage) = viewModel.contentState else {
      return XCTFail("Expected an empty release note response to become an unavailable message.")
    }
    XCTAssertEqual(emptyMessage.description, LatestError.releaseNotesUnavailable.failureReason)

    let thirdApp = makeApp(name: "Zed", version: "5", remoteVersion: "6")
    viewModel.display(thirdApp)
    provider.completeRequest(at: 2, with: .failure(LatestError.updateInfoUnavailable))
    guard case .message(let errorMessage) = viewModel.contentState else {
      return XCTFail("Expected provider failures to become detail messages.")
    }
    XCTAssertEqual(errorMessage.title, LatestError.updateInfoUnavailable.localizedDescription)
    XCTAssertEqual(errorMessage.description, LatestError.updateInfoUnavailable.failureReason)

    viewModel.display(nil)
    guard case .message(let noSelectionMessage) = viewModel.contentState else {
      return XCTFail("Expected the no-selection message.")
    }
    XCTAssertEqual(noSelectionMessage, .noSelection)
  }

  @MainActor
  func testShippingMenuValidatesSelectedAppActions() throws {
    let (window, table, viewModel) = try makeShippingSidebar()
    defer { window.close() }
    let menu = try XCTUnwrap(table.menu)
    for (row, entry) in viewModel.snapshot.entries.enumerated() {
      guard case .app(let app) = entry else { continue }
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      menu.update()
      let updateItem = try XCTUnwrap(
        menu.items.first { $0.action == NSSelectorFromString("updateApp:") })
      let ignoreItem = try XCTUnwrap(
        menu.items.first { $0.action == NSSelectorFromString("ignoreApp:") })
      let unignoreItem = try XCTUnwrap(
        menu.items.first { $0.action == NSSelectorFromString("unignoreApp:") })
      XCTAssertEqual(updateItem.isEnabled, app.updateAvailable)
      XCTAssertEqual(ignoreItem.isHidden, app.isIgnored)
      XCTAssertEqual(unignoreItem.isHidden, !app.isIgnored)
    }
  }

  @MainActor
  private func makeShippingSidebar() throws -> (NSWindow, NSTableView, UpdatesListViewModel) {
    let apps = [
      makeApp(name: "Discord", version: "1", remoteVersion: "2"),
      makeApp(name: "Cursor", version: "3"),
    ]
    let viewModel = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: apps, filterQuery: nil))
    let host = NSHostingView(
      rootView: UpdatesSidebarView(
        viewModel: viewModel, searchFocusController: SearchFocusController()))
    host.frame = NSRect(x: 0, y: 0, width: VisualMetrics.sidebarIdealWidth, height: 420)
    let window = NSWindow(
      contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    let table = try XCTUnwrap(host.descendant(of: NSTableView.self))
    XCTAssertTrue(table is SwiftUIUpdateTableView)
    return (window, table, viewModel)
  }

  private func assertWaiting(
    _ presentation: UpdateActionPresentation,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard case .waiting(let status) = presentation else {
      return XCTFail("Expected a waiting presentation.", file: file, line: line)
    }
    XCTAssertFalse(status.isEmpty, file: file, line: line)
  }

  @MainActor
  private func makeApp(
    name: String,
    version: String,
    remoteVersion: String? = nil,
    date: Date = Date(timeIntervalSince1970: 1_750_000_000)
  ) -> Latest.App {
    let bundle = Latest.App.Bundle(
      version: Version(versionNumber: version, buildNumber: nil),
      name: name,
      bundleIdentifier: "com.example.\(name.lowercased())",
      fileURL: URL(fileURLWithPath: "/Applications/\(name).app"),
      source: .appStore
    )
    let update = Latest.App.Update(
      app: bundle,
      remoteVersion: Version(versionNumber: remoteVersion ?? version, buildNumber: nil),
      minimumOSVersion: nil,
      source: .appStore,
      date: date,
      releaseNotes: .html(string: "<p>Release notes</p>"),
      updateAction: .builtIn { _ in }
    )
    return Latest.App(bundle: bundle, update: .success(update), isIgnored: false)
  }
}

@MainActor
private final class SelectionBox {
  var url: URL?
}

@MainActor
private final class ReleaseNotesProviderProbe: ReleaseNotesProviding {
  private(set) var requests: [(app: Latest.App, completion: ReleaseNotesProvider.Completion)] = []

  func releaseNotes(
    for app: Latest.App,
    with completion: @escaping ReleaseNotesProvider.Completion
  ) {
    requests.append((app, completion))
  }

  func completeRequest(at index: Int, with result: ReleaseNotesProvider.ReleaseNotes) {
    requests[index].completion(result)
  }
}

extension NSView {
  fileprivate func descendant<ViewType: NSView>(of type: ViewType.Type) -> ViewType? {
    if let match = self as? ViewType {
      return match
    }
    return subviews.lazy.compactMap { $0.descendant(of: type) }.first
  }

  fileprivate func allDescendants() -> [NSView] {
    subviews + subviews.flatMap { $0.allDescendants() }
  }
}
