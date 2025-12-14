//
//  HomebrewCheckerOperation.swift
//  Latest
//
//  Created by Max Langer on 12.03.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import Cocoa

/// The operation for checking for updates via Homebrew.
class HomebrewCheckerOperation: StatefulOperation, UpdateCheckerOperation, @unchecked Sendable {
	
	static var sourceType: App.Source {
		return .none
	}
	
	/// The bundle to be checked for updates.
	private let bundle: App.Bundle
	
	/// The update fetched during the checking operation.
	fileprivate var update: App.Update?
	
	private let repository: UpdateRepository?
	private let updateCheckerCompletionBlock: UpdateCheckerCompletionBlock
	
	static func canPerformUpdateCheck(forAppAt url: URL) -> Bool {
		return true
	}
		
	required init(with bundle: App.Bundle, repository: UpdateRepository?, completionBlock: @escaping UpdateCheckerCompletionBlock) {
		self.bundle =  bundle
		self.repository = repository
		self.updateCheckerCompletionBlock = completionBlock
		
		super.init()
		
		self.completionBlock = { [weak self] in
			guard let self else { return }

			if let update = self.update {
				self.updateCheckerCompletionBlock(.success(update))
			} else {
				self.updateCheckerCompletionBlock(.failure(self.error ?? LatestError.updateInfoUnavailable))
			}
		}
	}
	
	
	// MARK: - Operation

	override func execute() {
		guard let repository else {
			self.finish()
			return
		}
		
		repository.updateInfo(for: bundle) { bundle, entry in
			defer { self.finish() }
			guard let entry else { return }
			
			let actionLabel = App.Source.homebrew.sourceName ?? "Homebrew"
			let releaseNotes = entry.releaseNotesURL.map { App.Update.ReleaseNotes.url(url: $0) }
			self.update = App.Update(
				app: bundle,
				remoteVersion: entry.version,
				minimumOSVersion: entry.minimumOSVersion,
				source: .homebrew,
				date: nil,
				releaseNotes: releaseNotes,
				updateAction: .external(label: actionLabel, block: { _ in
					NSWorkspace.shared.open(entry.caskPageURL)
				})
			)
		}
	}
	
}
