//
//  GeneralSettingsView.swift
//  Latest
//
//  Created by Codex on 03.06.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

struct GeneralSettingsView: View {
	@ObservedObject var viewModel: SettingsViewModel

	var body: some View {
		ZStack(alignment: .topLeading) {
			settingsGrid
				.frame(width: 400, height: 120, alignment: .topLeading)
				.offset(x: 20, y: 20)

			if viewModel.showsInstallHelperBanner {
				installHelperBanner
					.frame(width: 400, height: 59, alignment: .topLeading)
					.offset(x: 20, y: 150)
			}
		}
		.frame(width: 440, height: 219, alignment: .topLeading)
		.onAppear {
			viewModel.refreshInstallHelperAvailability()
		}
	}

	private var settingsGrid: some View {
		ZStack(alignment: .topLeading) {
			Text("Include:")
				.font(.system(size: NSFont.systemFontSize))
				.frame(width: 52, height: 16, alignment: .trailing)
				.offset(x: -2, y: 0)

			SettingsCheckboxRepresentable(
				title: "Apps with limited support",
				isOn: limitedSupportBinding
			)
			.frame(width: 346, height: 16, alignment: .leading)
			.offset(x: 54, y: 0)

			Text("List apps with limited support. Update information may be outdated or inaccurate, and updates cannot be performed directly in Latest.")
				.font(.system(size: NSFont.smallSystemFontSize))
				.foregroundColor(Color(nsColor: .secondaryLabelColor))
				.fixedSize(horizontal: false, vertical: true)
				.frame(width: 330, height: 56, alignment: .topLeading)
				.offset(x: 72, y: 22)

			SettingsCheckboxRepresentable(
				title: "Unsupported apps",
				isOn: unsupportedAppsBinding
			)
			.frame(width: 346, height: 16, alignment: .leading)
			.offset(x: 54, y: 84)

			Text("Show apps without any available update information.")
				.font(.system(size: NSFont.smallSystemFontSize))
				.foregroundColor(Color(nsColor: .secondaryLabelColor))
				.frame(width: 330, height: 14, alignment: .topLeading)
				.offset(x: 72, y: 106)
		}
	}

	private var installHelperBanner: some View {
		InstallHelperBannerRepresentable {
			viewModel.registerInstallHelper()
		}
	}

	private var limitedSupportBinding: Binding<Bool> {
		Binding(
			get: { viewModel.includeAppsWithLimitedSupport },
			set: { viewModel.includeAppsWithLimitedSupport = $0 }
		)
	}

	private var unsupportedAppsBinding: Binding<Bool> {
		Binding(
			get: { viewModel.includeUnsupportedApps },
			set: { viewModel.includeUnsupportedApps = $0 }
		)
	}
}

private struct InstallHelperBannerRepresentable: NSViewRepresentable {
	let onEnable: () -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(onEnable: onEnable)
	}

	func makeNSView(context: Context) -> NSView {
		let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 59))

		let separator = NSBox()
		separator.boxType = .separator
		separator.translatesAutoresizingMaskIntoConstraints = false

		let label = NSTextField(wrappingLabelWithString: "Enable a helper program to update App Store apps within Latest.")
		label.isSelectable = true
		label.font = .systemFont(ofSize: NSFont.systemFontSize)
		label.textColor = .labelColor
		label.translatesAutoresizingMaskIntoConstraints = false

		let button = NSButton(title: "Enable", target: context.coordinator, action: #selector(Coordinator.enable(_:)))
		button.bezelStyle = .rounded
		button.translatesAutoresizingMaskIntoConstraints = false

		view.addSubview(separator)
		view.addSubview(label)
		view.addSubview(button)

		NSLayoutConstraint.activate([
			separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			separator.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
			separator.heightAnchor.constraint(equalToConstant: 5),

			label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -2),
			label.topAnchor.constraint(equalTo: view.topAnchor, constant: 19),
			label.widthAnchor.constraint(equalToConstant: 319),
			label.heightAnchor.constraint(equalToConstant: 30),

			button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 335),
			button.topAnchor.constraint(equalTo: view.topAnchor, constant: 19),
			button.widthAnchor.constraint(equalToConstant: 65),
			button.heightAnchor.constraint(equalToConstant: 30)
		])

		return view
	}

	func updateNSView(_ view: NSView, context: Context) {
		context.coordinator.onEnable = onEnable
	}

	final class Coordinator: NSObject {
		var onEnable: () -> Void

		init(onEnable: @escaping () -> Void) {
			self.onEnable = onEnable
		}

		@MainActor
		@objc func enable(_ sender: NSButton) {
			onEnable()
		}
	}
}

private struct SettingsCheckboxRepresentable: NSViewRepresentable {
	let title: String
	@Binding var isOn: Bool

	func makeCoordinator() -> Coordinator {
		Coordinator(isOn: $isOn)
	}

	func makeNSView(context: Context) -> NSButton {
		let button = NSButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.toggle(_:)))
		button.font = .systemFont(ofSize: NSFont.systemFontSize)
		button.setContentHuggingPriority(.required, for: .horizontal)
		button.setContentCompressionResistancePriority(.required, for: .horizontal)
		return button
	}

	func updateNSView(_ button: NSButton, context: Context) {
		context.coordinator.isOn = $isOn
		button.title = title
		button.state = isOn ? .on : .off
	}

	final class Coordinator: NSObject {
		var isOn: Binding<Bool>

		init(isOn: Binding<Bool>) {
			self.isOn = isOn
		}

		@MainActor
		@objc func toggle(_ sender: NSButton) {
			isOn.wrappedValue = sender.state == .on
		}
	}
}
