//
//  AppListSnapshot.swift
//  Latest
//
//  Created by Max Langer on 08.01.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

/// Describes the contents of the app list.
///
/// This structure supports the following states:
/// - All apps with updates available
/// - All installed apps, separated from the ones with updates through sections
/// - A filtered list of apps based on a given filter string
@MainActor
struct AppListSnapshot {
	
	/// The query after which apps can be filtered
	let filterQuery: String?
	
	/// The apps from which the content is created
	let apps: [App]
	
	/// Initializes the snapshot with the given list of apps and filter query.
	init(withApps apps: [App], filterQuery: String?) {
		self.filterQuery = filterQuery
		self.apps = apps
		let entries = Self.generateEntries(from: apps, filterQuery: filterQuery)
		self.entries = entries
		self.entryIndexesByAppIdentifier = Self.entryIndexesByAppIdentifier(entries)
		self.appIdentifiers = Set(apps.map(\.identifier))
	}
	
	/// Returns a new snapshot containing an updated filter query.
	func updated(with filterQuery: String?) -> AppListSnapshot {
		return AppListSnapshot(withApps: self.apps, filterQuery: filterQuery)
	}
	
	/// Returns an updated snapshot.
	func updated() -> AppListSnapshot {
		return AppListSnapshot(withApps: self.apps, filterQuery: self.filterQuery)
	}
	
	/// The user-facable, sorted and filtered list of apps and sections. Observers of the data store will be notified, when this list changes.
	let entries: [Entry]

	private let entryIndexesByAppIdentifier: [App.Bundle.Identifier: Int]

	private let appIdentifiers: Set<App.Bundle.Identifier>
	
	/// Sorts and filters all available apps based on the given filter criteria.
	private static func generateEntries(from apps: [App], filterQuery: String?) -> [Entry] {
		let settings = AppListSettings.shared
		let showInstalledUpdates = settings.showInstalledUpdates
		let showIgnoredUpdates = settings.showIgnoredUpdates
		let includeUnsupportedApps = settings.includeUnsupportedApps
		let includeAppsWithLimitedSupport = settings.includeAppsWithLimitedSupport
		let sortOrder = settings.sortOrder

		// Mutable copy
		var visibleApps = apps
		
		visibleApps = visibleApps.filter { app in
			// Apply filter query
			if let filterQuery = filterQuery, !app.name.localizedCaseInsensitiveContains(filterQuery) {
				return false
			}

			// Filter installed updates
			if !showInstalledUpdates && !(app.updateAvailable || app.isIgnored) {
				return false
			}
						
			// Filter ignored apps
			if !showIgnoredUpdates && app.isIgnored {
				return false
			}

			// Filter unsupported apps
			if !includeUnsupportedApps && !app.supported {
				return false
			}
			
			// Filter apps not using the builtin updater
			if !includeAppsWithLimitedSupport && app.updateAvailable && !app.usesBuiltInUpdater {
				return false
			}
			
			return true
		}
		
		// Sort apps based on setting
		let filteredApps: [App]
		switch sortOrder {
		case .updateDate:
			filteredApps = visibleApps.sorted { app1, app2 in
				app1.updateDate > app2.updateDate
			}
		case .name:
			filteredApps = visibleApps
				.map { (app: $0, name: $0.name.lowercased()) }
				.sorted { $0.name < $1.name }
				.map(\.app)
		}
		
		var availableUpdates = [Entry]()
		var installedUpdates = [Entry]()
		var ignoredUpdates = [Entry]()

		filteredApps.forEach { app in
			let entry = Entry.app(app)
			if app.isIgnored {
				ignoredUpdates.append(entry)
			} else if app.updateAvailable {
				availableUpdates.append(entry)
			} else {
				installedUpdates.append(entry)
			}
		}
		installedUpdates.sort { entry1, entry2 in
			guard case .app(let app1) = entry1, case .app(let app2) = entry2 else {
				return false
			}

			if app1.bundle.modificationDate == app2.bundle.modificationDate {
				return app1.name.lowercased() < app2.name.lowercased()
			}

			return app1.bundle.modificationDate > app2.bundle.modificationDate
		}

		var entries = [Entry]()
		entries.reserveCapacity(filteredApps.count + 3)
		Self.appendSection(
			availableUpdates,
			section: Self.updatableAppsSection(withCount: availableUpdates.count),
			to: &entries
		)
		Self.appendSection(
			installedUpdates,
			section: Self.updatedAppsSection(withCount: installedUpdates.count),
			to: &entries
		)
		Self.appendSection(
			ignoredUpdates,
			section: Self.ignoredAppsSection(withCount: ignoredUpdates.count),
			to: &entries
		)
		return entries
	}
	

	// MARK: - Accessors
	
	/// Returns the app at the given index, if any.
	func app(at index: Int) -> App? {
		if case .app(let app) = self.entries[index] {
			return app
		}
		
		return nil
	}
	
	func firstIndex(of app: App) -> Int? {
		entryIndexesByAppIdentifier[app.identifier]
	}
	
	func contains(_ app: App) -> Bool {
		return appIdentifiers.contains(app.identifier)
	}
	
	/// Returns whether there is a section at the given index
	func isSectionHeader(at index: Int) -> Bool {
		if case .section(_) = self.entries[index] {
			return true
		}
		
		return false
	}
	
	
	// MARK: - Section Builder
	
	private static func updatableAppsSection(withCount numberOfApps: Int) -> Section {
		let title = NSLocalizedString("AvailableUpdatesSection", comment: "Table Section Header for available updates")
		let shortTitle = NSLocalizedString("AvailableSection", comment: "Touch Bar section title for available updates")
		return Section(title: title, shortTitle: shortTitle, numberOfApps: numberOfApps)
	}
	
	private static func updatedAppsSection(withCount numberOfApps: Int) -> Section {
		let title = NSLocalizedString("InstalledAppsSection", comment: "Table Section Header for already installed apps")
		let shortTitle = NSLocalizedString("InstalledSection", comment: "Touch Bar section title for installed apps")
		return Section(title: title, shortTitle: shortTitle, numberOfApps: numberOfApps)
	}

	private static func ignoredAppsSection(withCount numberOfApps: Int) -> Section {
		let title = NSLocalizedString("IgnoredAppsSection", comment: "Table Section Header for ignored apps")
		let shortTitle = NSLocalizedString("IgnoredSection", comment: "Touch Bar section title for ignored apps")
		return Section(title: title, shortTitle: shortTitle, numberOfApps: numberOfApps)
	}

	private static func appendSection(_ sectionEntries: [Entry], section: Section, to entries: inout [Entry]) {
		guard !sectionEntries.isEmpty else { return }
		entries.append(.section(section))
		entries.append(contentsOf: sectionEntries)
	}

	private static func entryIndexesByAppIdentifier(_ entries: [Entry]) -> [App.Bundle.Identifier: Int] {
		entries.enumerated().reduce(into: [App.Bundle.Identifier: Int]()) { indexes, element in
			guard case .app(let app) = element.element else { return }
			indexes[app.identifier] = indexes[app.identifier] ?? element.offset
		}
	}

}

extension AppListSnapshot {
	
	/// Defines one entry in the filtered update.
	enum Entry: Equatable, Hashable {
		
		/// Represents one app in the list.
		case app(App)
		
		/// Represents one section header in the list.
		case section(Section)
		
		func isSimilar(to entry: Entry) -> Bool {
			switch self {
			case .app(let app):
				if case .app(let other) = entry {
					return app.identifier == other.identifier
				}
			case .section(let section):
				if case .section(let other) = entry {
					return section.title == other.title
				}
			}
			
			return false
		}
		
	}
	
	/// A section used for grouping multiple results.
	struct Section: Equatable, Hashable {
		
		/// The title of the section.
		let title: String
		
		/// A shorter representation of the sections title.
		let shortTitle: String
		
		/// The number of apps this section encloses.
		let numberOfApps: Int
		
		
		// MARK: - Protocol Overrides
		
		/// Exclude the number of apps from the function
		static func ==(lhs: Section, rhs: Section) -> Bool {
			return lhs.title == rhs.title && lhs.numberOfApps == rhs.numberOfApps
		}
		
		/// Exclude the number of apps from the function
		func hash(into hasher: inout Hasher) {
			hasher.combine(title)
		}
		
	}
}
