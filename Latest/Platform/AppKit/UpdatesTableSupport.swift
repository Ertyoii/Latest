//
//  UpdatesTableSupport.swift
//  Latest
//
//  AppKit controls and menu handling used by UpdatesTableBridge.
//

import AppKit

@MainActor
final class SidebarTableMenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
	weak var tableView: NSTableView?
	private var viewModel: UpdatesListViewModel
	private var entries = [AppListSnapshot.Entry]()
	private(set) lazy var menu: NSMenu = makeMenu()

	init(viewModel: UpdatesListViewModel) {
		self.viewModel = viewModel
	}

	func update(viewModel: UpdatesListViewModel, entries: [AppListSnapshot.Entry]) {
		self.viewModel = viewModel
		self.entries = entries
	}

	func menuNeedsUpdate(_ menu: NSMenu) {
		let app = targetApp()
		menu.items.forEach { item in
			guard !item.isSeparatorItem else { return }
			item.representedObject = app
		}
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return true }
		guard let app = targetApp(for: menuItem) else { return false }

		switch action {
		case #selector(updateApp(_:)):
			menuItem.title = SidebarUpdateActionTitle.text(for: app)
			return app.updateAvailable && !app.isUpdating
		case #selector(openApp(_:)), #selector(revealInFinder(_:)):
			return true
		case #selector(ignoreApp(_:)):
			menuItem.isHidden = app.isIgnored
			return true
		case #selector(unignoreApp(_:)):
			menuItem.isHidden = !app.isIgnored
			return true
		default:
			return false
		}
	}

	@objc private func updateApp(_ sender: NSMenuItem?) {
		guard let app = targetApp(for: sender) else { return }
		viewModel.update(app)
	}

	@objc private func ignoreApp(_ sender: NSMenuItem?) {
		guard let app = targetApp(for: sender) else { return }
		viewModel.setIgnored(true, for: app)
	}

	@objc private func unignoreApp(_ sender: NSMenuItem?) {
		guard let app = targetApp(for: sender) else { return }
		viewModel.setIgnored(false, for: app)
	}

	@objc private func openApp(_ sender: NSMenuItem?) {
		guard let app = targetApp(for: sender) else { return }
		viewModel.open(app)
	}

	@objc private func revealInFinder(_ sender: NSMenuItem?) {
		guard let app = targetApp(for: sender) else { return }
		viewModel.revealInFinder(app)
	}

	private func makeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.delegate = self
		menu.autoenablesItems = true
		menu.addItem(menuItem(
			title: NSLocalizedString("UpdateAction", comment: "Action to update a given app."),
			image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil),
			action: #selector(updateApp(_:))
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("IgnoreAction", value: "Ignore", comment: "Action to ignore a given app."),
			image: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil),
			action: #selector(ignoreApp(_:))
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("UnignoreAction", value: "Don't Ignore", comment: "Action to stop ignoring a given app."),
			image: NSImage(named: "custom.app.dashed.slash"),
			action: #selector(unignoreApp(_:))
		))
		menu.addItem(.separator())
		menu.addItem(menuItem(
			title: NSLocalizedString("OpenAction", comment: "Action to open a given app."),
			image: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil),
			action: #selector(openApp(_:))
		))
		menu.addItem(menuItem(
			title: NSLocalizedString("RevealAction", comment: "Reveal in Finder Row action"),
			image: NSImage(systemSymbolName: "finder", accessibilityDescription: nil),
			action: #selector(revealInFinder(_:))
		))
		return menu
	}

	private func menuItem(title: String, image: NSImage?, action: Selector) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.target = self
		item.image = image
		return item
	}

	private func targetApp(for menuItem: NSMenuItem? = nil) -> App? {
		if let app = menuItem?.representedObject as? App {
			return app
		}
		guard let tableView else { return nil }
		return SidebarInteractionPolicy(entries: entries).targetApp(
			clickedRow: tableView.clickedRow,
			selectedRow: tableView.selectedRow
		)
	}
}

@MainActor
enum SidebarUpdateActionTitle {
	static func text(for app: App) -> String {
		if let externalUpdater = app.externalUpdaterName {
			return String(
				format: NSLocalizedString(
					"ExternalUpdateAction",
					comment: "Action to update a given app outside of Latest. The placeholder is the external updater."
				),
				externalUpdater
			)
		}

		return NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
	}
}

final class SwiftUIUpdateTableView: NSTableView {
	var onMouseDownRow: ((Int) -> Void)?

	override func menu(for event: NSEvent) -> NSMenu? {
		let clickedPoint = convert(event.locationInWindow, from: nil)
		let clickedRow = row(at: clickedPoint)
		guard clickedRow >= 0,
		      !(delegate?.tableView?(self, isGroupRow: clickedRow) ?? false) else {
			return nil
		}
		return super.menu(for: event)
	}

	override func layout() {
		super.layout()
		lockHorizontalGeometry()
	}

	override func setFrameOrigin(_ newOrigin: NSPoint) {
		super.setFrameOrigin(NSPoint(x: AppKitTableGeometry.leadingOffset, y: newOrigin.y))
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let clickedPoint = convert(event.locationInWindow, from: nil)
		let clickedRow = row(at: clickedPoint)
		if clickedRow >= 0, delegate?.tableView?(self, shouldSelectRow: clickedRow) ?? true {
			selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
			onMouseDownRow?(clickedRow)
		}
		super.mouseDown(with: event)
	}

	private func lockHorizontalGeometry() {
		guard let scrollView = enclosingScrollView else { return }
		let width = scrollView.contentSize.width
		if width > 0, abs(frame.width - width) > 0.5 {
			setFrameSize(NSSize(width: width, height: frame.height))
		}
		if frame.origin.x != AppKitTableGeometry.leadingOffset {
			setFrameOrigin(NSPoint(x: AppKitTableGeometry.leadingOffset, y: frame.origin.y))
		}
		if scrollView.contentView.bounds.origin.x != 0 {
			scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y))
			scrollView.reflectScrolledClipView(scrollView.contentView)
		}
	}
}

final class NoDrawingGroupRowView: NSTableRowView {
	override func drawBackground(in dirtyRect: NSRect) {}
}

final class LockedHorizontalScrollView: NSScrollView {
	override func scrollWheel(with event: NSEvent) {
		super.scrollWheel(with: event)
		guard contentView.bounds.origin.x != 0 else { return }
		contentView.bounds.origin.x = 0
		reflectScrolledClipView(contentView)
	}
}

final class LockedHorizontalClipView: NSClipView {
	override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
		var bounds = super.constrainBoundsRect(proposedBounds)
		bounds.origin.x = 0
		return bounds
	}

	override func scroll(to newOrigin: NSPoint) {
		let lockedOrigin = NSPoint(x: 0, y: newOrigin.y)
		guard bounds.origin.x != lockedOrigin.x || bounds.origin.y != lockedOrigin.y else { return }
		super.scroll(to: lockedOrigin)
	}
}
