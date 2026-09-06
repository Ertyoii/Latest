//
//  AppDependencyBoundaryTest.swift
//  Latest Tests
//
//  Copyright © 2026 Max Langer. All rights reserved.
//

import XCTest

@testable import Latest

@MainActor
final class AppDependencyBoundaryTest: XCTestCase {
  func testSnapshotUsesInjectedSettingsInsteadOfGlobalPreferences() throws {
    let (settings, defaults, suiteName) = try makeSettings()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    settings.includeUnsupportedApps = false

    let app = makeApp(source: .none)
    let hidden = AppListSnapshot(
      withApps: [app],
      filterQuery: nil,
      settings: settings
    )
    XCTAssertTrue(hidden.apps.isEmpty == false)
    XCTAssertTrue(hidden.sections.isEmpty)

    settings.includeUnsupportedApps = true
    let visible = hidden.updated()
    XCTAssertEqual(visible.sections.flatMap(\.apps), [app])
  }

  func testUpdatesViewModelRoutesWorkspaceAndStoreActionsThroughInjectedBoundaries() throws {
    let (settings, defaults, suiteName) = try makeSettings()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let app = makeApp(source: .sparkle)
    let provider = StubAppProvider(apps: [app])
    let workspace = StubApplicationWorkspace()
    let viewModel = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: [app], filterQuery: nil, settings: settings),
      settings: settings,
      appProvider: provider,
      workspace: workspace
    )

    viewModel.open(app)
    viewModel.revealInFinder(app)
    viewModel.setIgnored(true, for: app)

    XCTAssertEqual(workspace.openedApplicationURLs, [app.fileURL])
    XCTAssertEqual(workspace.revealedURLs, [[app.fileURL]])
    XCTAssertEqual(provider.ignoredChanges.count, 1)
    XCTAssertEqual(provider.ignoredChanges.first?.ignored, true)
    XCTAssertEqual(provider.ignoredChanges.first?.app, app)
  }

  func testCommandsUseInjectedPreferencesAndWorkspace() throws {
    let (settings, defaults, suiteName) = try makeSettings()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let workspace = StubApplicationWorkspace()
    let commands = AppCommands(
      updateCheckingService: StubUpdateCheckingCommands(),
      updatesListViewModel: UpdatesListViewModel(
        settings: settings,
        appProvider: StubAppProvider(apps: []),
        workspace: workspace
      ),
      searchFocusController: SearchFocusController(),
      settings: settings,
      workspace: workspace
    )

    commands.changeSortOrder(.name)
    commands.showInstalledUpdates.toggle()
    commands.visitWebsite()

    XCTAssertEqual(settings.sortOrder, .name)
    XCTAssertFalse(settings.showInstalledUpdates)
    XCTAssertEqual(workspace.openedURLs.map(\.absoluteString), ["https://max.codes/latest"])
  }

  private func makeSettings() throws -> (AppListSettings, UserDefaults, String) {
    let suiteName = "AppDependencyBoundaryTest.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return (AppListSettings(userDefaults: defaults), defaults, suiteName)
  }

  private func makeApp(source: App.Source) -> App {
    let bundle = App.Bundle(
      version: Version(versionNumber: "1.0", buildNumber: "1"),
      name: "Fixture",
      bundleIdentifier: "com.example.fixture",
      fileURL: URL(fileURLWithPath: "/Applications/Fixture.app", isDirectory: true),
      source: source,
      modificationDate: .distantPast
    )
    return App(bundle: bundle, update: nil, isIgnored: false)
  }
}

private final class StubAppProvider: AppProviding {
  struct IgnoredChange {
    let ignored: Bool
    let app: App
  }

  let apps: [App]
  private(set) var ignoredChanges = [IgnoredChange]()

  init(apps: [App]) {
    self.apps = apps
  }

  var updatableApps: [App] {
    apps.filter { $0.updateAvailable && $0.usesBuiltInUpdater && !$0.isIgnored }
  }

  func countOfAvailableUpdates(where condition: (App) -> Bool) -> Int {
    apps.filter { $0.updateAvailable && !$0.isIgnored && condition($0) }.count
  }

  @MainActor
  func updates() -> AsyncStream<[App]> {
    AsyncStream { continuation in
      continuation.yield(apps)
      continuation.finish()
    }
  }

  func setIgnoredState(_ ignored: Bool, for app: App) {
    ignoredChanges.append(IgnoredChange(ignored: ignored, app: app))
  }
}

@MainActor
private final class StubApplicationWorkspace: ApplicationWorkspace {
  private(set) var openedApplicationURLs = [URL]()
  private(set) var revealedURLs = [[URL]]()
  private(set) var openedURLs = [URL]()
  private(set) var badgeLabels = [String?]()

  func openApplication(at url: URL) {
    openedApplicationURLs.append(url)
  }

  func revealInFinder(_ urls: [URL]) {
    revealedURLs.append(urls)
  }

  func open(_ url: URL) {
    openedURLs.append(url)
  }

  func setDockBadge(_ label: String?) {
    badgeLabels.append(label)
  }
}

@MainActor
private final class StubUpdateCheckingCommands: UpdateCheckingCommandHandling {
  func checkForUpdates() {}
  func updateAll() {}
}
