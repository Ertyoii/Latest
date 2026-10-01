//  Fork contributions © 2026 ertyoii. First committed in this fork 2026-09-06.
//  Licensed under GPL-3.0; see LICENSE.md.

import Foundation
import XCTest

@testable import Latest

@MainActor
func isolatedAppListSettings(for testCase: XCTestCase) throws -> AppListSettings {
  let suiteName = "LatestTests.AppListSettings.\(UUID().uuidString)"
  let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  testCase.addTeardownBlock {
    defaults.removePersistentDomain(forName: suiteName)
  }

  let settings = AppListSettings(userDefaults: defaults)
  settings.sortOrder = .name
  settings.showInstalledUpdates = true
  settings.showIgnoredUpdates = true
  settings.includeUnsupportedApps = true
  settings.includeAppsWithLimitedSupport = true
  return settings
}

@MainActor
extension AppEnvironment {
  /// A test-only offline state used by deterministic geometry and interaction
  /// contracts. The runnable app and `--uat` always use `live()`.
  static func localUATFixture(settings: AppListSettings) -> AppEnvironment {
    let apps = LocalUATFixture.apps
    let viewModel = UpdatesListViewModel(
      snapshot: AppListSnapshot(withApps: apps, filterQuery: nil, settings: settings),
      settings: settings)
    viewModel.select(viewModel.snapshot.sections.first?.apps.first)
    return AppEnvironment(settings: settings, updatesListViewModel: viewModel)
  }
}
