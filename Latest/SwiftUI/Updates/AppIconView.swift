//
//  AppIconView.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppIconLoader: ObservableObject {
	@Published private(set) var image: NSImage?
	private var appIdentifier: App.Bundle.Identifier?

	func loadIcon(for app: App) {
		guard appIdentifier != app.identifier || image == nil else { return }
		appIdentifier = app.identifier
		IconCache.shared.icon(for: app) { [weak self] image in
			guard self?.appIdentifier == app.identifier else { return }
			self?.image = image
		}
	}
}

struct AppIconView: View {
	let app: App
	let size: CGFloat
	@StateObject private var loader = AppIconLoader()

	var body: some View {
		Group {
			if let image = loader.image {
				Image(nsImage: image)
					.resizable()
			} else {
				Image(nsImage: NSWorkspace.shared.icon(forFile: app.fileURL.path))
					.resizable()
			}
		}
		.aspectRatio(contentMode: .fit)
		.frame(width: size, height: size)
		.onAppear {
			loader.loadIcon(for: app)
		}
		.onChange(of: app.identifier) { _, _ in
			loader.loadIcon(for: app)
		}
	}
}
