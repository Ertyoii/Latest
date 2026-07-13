//
//  ReleaseNotesDetailView.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

struct ReleaseNotesDetailView: View {
	@ObservedObject var updatesViewModel: UpdatesListViewModel

	var body: some View {
		LegacyReleaseNotesViewControllerRepresentable(app: updatesViewModel.selectedApp)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.transaction { transaction in
			transaction.animation = nil
			transaction.disablesAnimations = true
		}
	}
}

private struct LegacyReleaseNotesViewControllerRepresentable: NSViewControllerRepresentable {
	let app: App?

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeNSViewController(context: Context) -> ReleaseNotesViewController {
		let controller = ReleaseNotesViewController()
		_ = controller.view
		context.coordinator.display(app, in: controller)
		return controller
	}

	func updateNSViewController(_ controller: ReleaseNotesViewController, context: Context) {
		context.coordinator.display(app, in: controller)
	}

	@MainActor
	final class Coordinator {
		private var displayedKey: String?

		func display(_ app: App?, in controller: ReleaseNotesViewController) {
			let nextKey = app.map(Self.displayKey(for:))
			guard nextKey != displayedKey else { return }

			displayedKey = nextKey
			NSAnimationContext.runAnimationGroup { context in
				context.duration = 0
				context.allowsImplicitAnimation = false
				controller.display(releaseNotesFor: app)
			}
		}

		private static func displayKey(for app: App) -> String {
			let latestUpdateDate = app.latestUpdateDate?.timeIntervalSinceReferenceDate ?? -1
			let version = app.localizedVersionInformation?.combined(includeNew: app.updateAvailable) ?? ""
			let externalUpdater = app.externalUpdaterName ?? ""
			let supportState = app.source.supportState.compactLabel
			return [
				app.identifier.absoluteString,
				version,
				String(latestUpdateDate),
				externalUpdater,
				supportState
			].joined(separator: "|")
		}
	}
}
