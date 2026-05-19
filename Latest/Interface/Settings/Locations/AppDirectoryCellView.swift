//
//  AppDirectoryCellView.swift
//  Latest
//
//  Created by Max Langer on 29.02.24.
//  Copyright © 2024 Max Langer. All rights reserved.
//

import Cocoa

/// View that holds a single location checked for updates.
@MainActor
class AppDirectoryCellView: NSTableCellView {
	
	/// The label holding the path of the directory.
	@IBOutlet private weak var titleLabel: NSTextField!
	
	/// The image view displaying the directories icon.
	@IBOutlet private weak var iconImageView: NSImageView!
	
	/// The label holding the app count for this directory.
	@IBOutlet private weak var appCountLabel: NSTextField!
	
	/// The activity indicator shown while the apps are being counted.
	@IBOutlet private weak var activityIndicator: NSProgressIndicator!
	
	/// The URL to be displayed by the cell.
	var url: URL? {
		didSet {
			guard url != oldValue else { return }
			
			appCountTask?.cancel()
			isReachable = (try? url?.checkResourceIsReachable()) == true
			setUpView()
		}
	}
	
	var isReachable: Bool = false

	private var appCountTask: Task<Void, Never>?
	
	private func setUpView() {
		guard let url else {
			titleLabel.stringValue = ""
			iconImageView.image = nil
			appCountLabel.isHidden = true
			return
		}
		
		// Title
		titleLabel.stringValue = url.relativePath
		titleLabel.textColor = tintColor
		
		// Image
		iconImageView.image = icon
		
		// App Count
		activityIndicator.startAnimation(nil)
		appCountLabel.isHidden = true
		appCountTask = Task {
			let count = await Task.detached(priority: .utility) {
				BundleCollector.collectBundles(at: url).count
			}.value

			guard !Task.isCancelled, self.url == url else { return }

			self.appCountLabel.isHidden = false
			self.activityIndicator.stopAnimation(nil)
			self.appCountLabel.stringValue = NumberFormatter.localizedString(from: NSNumber(value: count), number: .none)
		}
	}
	
	private var tintColor: NSColor {
		isReachable ? .labelColor : .secondaryLabelColor
	}
	
	private var icon: NSImage {
		if isReachable {
			guard let url else { return NSImage() }
			return NSWorkspace.shared.icon(forFile: url.relativePath)
		}
		
		return NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "")!
	}
}
