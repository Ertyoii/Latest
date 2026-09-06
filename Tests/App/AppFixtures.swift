//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-09-06.
//  Licensed under GPL-3.0; see LICENSE.md.

import Foundation

@testable import Latest

@MainActor
extension AppEnvironment {
  /// A test-only offline state used by deterministic geometry and interaction
  /// contracts. The runnable app and `--uat` always use `live()`.
  static func localUATFixture() -> AppEnvironment {
    let apps = LocalUATFixture.apps
    let viewModel = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: apps, filterQuery: nil))
    viewModel.select(viewModel.snapshot.sections.first?.apps.first)
    return AppEnvironment(updatesListViewModel: viewModel)
  }
}

enum LocalUATFixture {
  /// Stable real bundle paths keep deterministic test renders tied to actual
  /// icon assets. This fixture is never selected by the runnable app.
  static let apps: [App] = [
    ("Notes", "26.4", "26.5", "/System/Applications/Notes.app"),
    ("Terminal", "2.14", "2.15", "/System/Applications/Utilities/Terminal.app"),
    ("TextEdit", "1.19", "1.20", "/System/Applications/TextEdit.app"),
    ("Calculator", "11.0", "11.1", "/System/Applications/Calculator.app"),
    ("Calendar", "15.0", "15.1", "/System/Applications/Calendar.app"),
    ("Contacts", "14.0", "14.1", "/System/Applications/Contacts.app"),
    ("Freeform", "4.0", "4.1", "/System/Applications/Freeform.app"),
    ("Home", "10.0", "10.1", "/System/Applications/Home.app"),
    ("Mail", "16.0", "16.1", "/System/Applications/Mail.app"),
    ("Maps", "4.0", "4.1", "/System/Applications/Maps.app"),
    ("Messages", "14.0", "14.1", "/System/Applications/Messages.app"),
    ("Music", "1.5", "1.6", "/System/Applications/Music.app"),
    ("Photo Booth", "13.0", "13.1", "/System/Applications/Photo Booth.app"),
    ("Photos", "10.0", "10.1", "/System/Applications/Photos.app"),
    ("Podcasts", "1.1", "1.2", "/System/Applications/Podcasts.app"),
    ("Preview", "11.0", "11.1", "/System/Applications/Preview.app"),
    ("Reminders", "7.0", "7.1", "/System/Applications/Reminders.app"),
    ("Shortcuts", "7.0", "7.1", "/System/Applications/Shortcuts.app"),
  ].enumerated().map { index, fixture in
    let fileURL = URL(fileURLWithPath: fixture.3, isDirectory: true)
    let bundle = App.Bundle(
      version: Version(versionNumber: fixture.1, buildNumber: nil),
      name: fixture.0,
      bundleIdentifier: Bundle(url: fileURL)?.bundleIdentifier ?? "com.example.latest-uat.\(index)",
      fileURL: fileURL,
      source: .sparkle,
      modificationDate: Date(timeIntervalSince1970: 1_750_000_000 - Double(index * 86_400))
    )
    let update = App.Update(
      app: bundle,
      remoteVersion: Version(versionNumber: fixture.2, buildNumber: nil),
      minimumOSVersion: nil,
      source: .sparkle,
      date: Date(timeIntervalSince1970: 1_750_000_000 - Double(index * 86_400)),
      releaseNotes: .html(
        string: """
          <h2>Version \(fixture.2)</h2>
          <p>Offline acceptance fixture for \(fixture.0).</p>
          <ul><li>Improved update discovery performance.</li><li>Modernized the macOS interface.</li></ul>
          """),
      updateAction: .builtIn { _ in }
    )
    return App(bundle: bundle, update: .success(update), isIgnored: false)
  }
}
