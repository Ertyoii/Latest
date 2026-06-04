//
//  SupportStatusInfoViewController.swift
//  Latest
//
//  Created by Max Langer on 15.02.25.
//  Copyright © 2025 Max Langer. All rights reserved.
//

import Cocoa

/// View explaining the support state of the given app.
class SupportStatusInfoViewController: NSViewController {

	private static let issueURL = URL(string: "https://github.com/mangerlahn/Latest/issues")
	private static let compactContentSize = NSSize(width: 325, height: 98)
	private static let fullSupportContentSize = NSSize(width: 325, height: 132)
	private static let contentWidth: CGFloat = 300
	
	/// The app for which the support state is explained.
	var app: App? {
		didSet {
			guard isViewLoaded else { return }
			updateUI()
		}
	}

	static func makeController(app: App?) -> SupportStatusInfoViewController {
		let controller = SupportStatusInfoViewController()
		controller.app = app
		return controller
	}

	// MARK: - Interface
	
	private let statusImageView = NSImageView()
	private let titleLabel = NSTextField(labelWithString: "")
	private let descriptionLabel = NSTextField(labelWithString: "")
	private var widthConstraint: NSLayoutConstraint?
	private var heightConstraint: NSLayoutConstraint?
	
	private lazy var reportIssueButton: NSButton = {
		let title = NSLocalizedString(
			"pNJ-Hl-Qxz.title",
			tableName: "Main",
			value: "Report Issue…",
			comment: "Button title in the support status popover."
		)
		let button = NSButton(title: title, target: self, action: #selector(reportIssue(_:)))
		button.bezelStyle = .rounded
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}()

	override func loadView() {
		let metrics = Self.layoutMetrics(for: app?.source.supportState)
		let rootView = NSView(frame: NSRect(origin: .zero, size: metrics.contentSize))
		rootView.translatesAutoresizingMaskIntoConstraints = false

		statusImageView.imageScaling = .scaleProportionallyDown
		statusImageView.translatesAutoresizingMaskIntoConstraints = false

		titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
		titleLabel.lineBreakMode = .byClipping
		titleLabel.drawsBackground = false
		titleLabel.translatesAutoresizingMaskIntoConstraints = false

		descriptionLabel.lineBreakMode = .byWordWrapping
		descriptionLabel.maximumNumberOfLines = metrics.maximumDescriptionLines
		descriptionLabel.drawsBackground = false
		descriptionLabel.cell?.wraps = true
		descriptionLabel.cell?.isScrollable = false
		descriptionLabel.setContentCompressionResistancePriority(.required, for: .vertical)
		descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

		let labelStack = NSStackView(views: [titleLabel, descriptionLabel])
		labelStack.orientation = .vertical
		labelStack.alignment = .leading
		labelStack.spacing = 5
		labelStack.translatesAutoresizingMaskIntoConstraints = false

		let infoStack = NSStackView(views: [statusImageView, labelStack])
		infoStack.orientation = .horizontal
		infoStack.alignment = .top
		infoStack.spacing = 8
		infoStack.translatesAutoresizingMaskIntoConstraints = false

		let mainStack = NSStackView(views: [infoStack, reportIssueButton])
		mainStack.orientation = .vertical
		mainStack.alignment = .trailing
		mainStack.spacing = 10
		mainStack.detachesHiddenViews = true
		mainStack.translatesAutoresizingMaskIntoConstraints = false

		rootView.addSubview(mainStack)

		let widthConstraint = rootView.widthAnchor.constraint(equalToConstant: metrics.contentSize.width)
		let heightConstraint = rootView.heightAnchor.constraint(equalToConstant: metrics.contentSize.height)
		self.widthConstraint = widthConstraint
		self.heightConstraint = heightConstraint

		NSLayoutConstraint.activate([
			widthConstraint,
			heightConstraint,
			statusImageView.widthAnchor.constraint(equalToConstant: 16),
			statusImageView.heightAnchor.constraint(equalToConstant: 16),
			infoStack.widthAnchor.constraint(equalToConstant: Self.contentWidth),
			mainStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 12),
			mainStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 5),
			mainStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -15),
			mainStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -15)
		])

		view = rootView
		preferredContentSize = metrics.contentSize
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		updateUI()
	}
	
	private func updateUI() {
		guard let app else { return }
		let supportState = app.source.supportState
		let metrics = Self.layoutMetrics(for: supportState)
		
		widthConstraint?.constant = metrics.contentSize.width
		heightConstraint?.constant = metrics.contentSize.height
		preferredContentSize = metrics.contentSize
		view.frame.size = metrics.contentSize
		descriptionLabel.maximumNumberOfLines = metrics.maximumDescriptionLines
		statusImageView.image = supportState.statusImage
		titleLabel.stringValue = supportState.label
		
		switch supportState {
		case .none:
			descriptionLabel.stringValue = NSLocalizedString("NoSupportDescription", comment: "Description for apps without support.")
			reportIssueButton.isHidden = true
		case .limited:
			descriptionLabel.stringValue = NSLocalizedString("LimitedSupportDescription", comment: "Description for apps with limited support.")
			reportIssueButton.isHidden = true
		case .full:
			descriptionLabel.stringValue = NSLocalizedString("FullSupportDescription", comment: "Description for apps with full support.")
			reportIssueButton.isHidden = false
		}
	}
	
	// MARK: - Actions
	
	/// Opens the issue page on GitHub.
	@IBAction func reportIssue(_ sender: NSButton) {
		guard let url = Self.issueURL else { return }
		NSWorkspace.shared.open(url)
	}
}

private extension SupportStatusInfoViewController {
	struct LayoutMetrics {
		let contentSize: NSSize
		let maximumDescriptionLines: Int
	}

	static func layoutMetrics(for supportState: App.Source.SupportState?) -> LayoutMetrics {
		switch supportState {
		case .some(.full):
			LayoutMetrics(contentSize: fullSupportContentSize, maximumDescriptionLines: 3)
		case .some(.limited), .some(.none), nil:
			LayoutMetrics(contentSize: compactContentSize, maximumDescriptionLines: 3)
		}
	}
}
