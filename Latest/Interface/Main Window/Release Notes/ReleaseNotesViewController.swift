//
//  UpdateDetailsViewController.swift
//  Latest
//
//  Created by Max Langer on 26.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa
import WebKit

/// The container for release notes content
fileprivate enum ReleaseNotesContent {
	
	/// The possible values when loading release notes content
	enum ContentType {
		
		/// The release notes view should display a loading indicator.
		case loading
		
		/// The release notes should display an error.
		case error
		
		/// Release notes contents should be displayed.
		case text
		
		/// Whether the currently displayed content is scrollable.
		var isScrollable: Bool {
			switch self {
				case .loading, .error:
					return false
					
				case .text:
					return true
			}
		}
	}
    
    /// The loading screen, presenting an activity indicator
    case loading(ReleaseNotesLoadingViewController?)
    
    /// The error screen, explaining what went wrong
    case error(ReleaseNotesErrorViewController?)
    
    /// The actual content
    case text(ReleaseNotesTextViewController?)
    
	/// Exposes the view controller holding the release notes, if available.
    var textController: ReleaseNotesTextViewController? {
        switch self {
        case .text(let controller):
            return controller
        default:
            return nil
        }
    }
    
	/// Exposes the view controller indicating a loading action, if available.
	var loadingController: ReleaseNotesLoadingViewController? {
        switch self {
        case .loading(let controller):
            return controller
        default:
            return nil
        }
	}
	
	/// Exposes the view controller holding an error, if available.
    var errorController: ReleaseNotesErrorViewController? {
        switch self {
        case .error(let controller):
            return controller
        default:
            return nil
        }
    }
    
    /// Returns the current view controller
    var controller: NSViewController? {
        switch self {
        case .loading(let controller):
            return controller
        case .error(let controller):
            return controller
        case .text(let controller):
            return controller
        }
    }
}

/**
 This is a super rudimentary implementation of an release notes viewer.
 It can open urls or display HTML strings right away.
 */
class ReleaseNotesViewController: NSViewController {
    
    @IBOutlet weak var appInfoBackgroundView: NSVisualEffectView!
    @IBOutlet weak var appInfoContentView: NSStackView!
    
    @IBOutlet weak var updateButton: UpdateButton!
	@IBOutlet weak var externalUpdateLabel: NSTextField!
    
    @IBOutlet weak var appNameTextField: NSTextField!
    @IBOutlet weak var appDateTextField: NSTextField!
    @IBOutlet weak var appVersionTextField: NSTextField!
    @IBOutlet weak var appIconImageView: NSImageView!
	
	/// Button indicating the support state of a given app.
	@IBOutlet private weak var supportStateButton: NSButton!
	
	private let releaseNotesProvider = ReleaseNotesProvider()
	private var supportStatePopover: NSPopover?
	private var appInfoTopConstraint: NSLayoutConstraint?
	private var appInfoLabelCenterYConstraint: NSLayoutConstraint?
	private var loadingTimer: Timer?
	private var displayRequestID = UUID()
    
	/// The app currently presented
	private(set) var app: App? {
		didSet {
			// Forward app
			self.updateButton.app = self.app
		}
	}
    
    /// The current content presented on screen
    private var content: ReleaseNotesContent?

    // MARK: - View Lifecycle

	override func loadView() {
		let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 452, height: 296))

		let headerView = NSVisualEffectView()
		headerView.wantsLayer = true
		headerView.blendingMode = .withinWindow
		headerView.material = .headerView
		headerView.state = .followsWindowActiveState
		headerView.translatesAutoresizingMaskIntoConstraints = false

		let contentStack = NSStackView()
		contentStack.orientation = .horizontal
		contentStack.alignment = .centerY
		contentStack.distribution = .fill
		contentStack.spacing = 5
		contentStack.detachesHiddenViews = true
		contentStack.translatesAutoresizingMaskIntoConstraints = false

		let iconImageView = NSImageView()
		iconImageView.wantsLayer = true
		iconImageView.imageScaling = .scaleProportionallyUpOrDown
		iconImageView.setContentHuggingPriority(.required, for: .horizontal)
		iconImageView.setContentHuggingPriority(.required, for: .vertical)
		iconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
		iconImageView.setContentCompressionResistancePriority(.required, for: .vertical)
		iconImageView.translatesAutoresizingMaskIntoConstraints = false

		let nameField = Self.makeLabel(font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
		nameField.wantsLayer = true

		let supportCell = SupportStatusButtonCell(textCell: "")
			supportCell.bezelStyle = .inline
			supportCell.imagePosition = .imageLeading
			supportCell.alignment = .left
			supportCell.isBordered = false
			supportCell.isScrollable = true
			supportCell.lineBreakMode = .byClipping
			supportCell.imageScaling = .scaleProportionallyDown
			supportCell.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)

		let supportButton = NSButton(title: "", target: nil, action: nil)
			supportButton.cell = supportCell
			supportButton.wantsLayer = true
			supportButton.bezelStyle = .inline
			supportButton.isBordered = false
			supportButton.alignment = .left
			supportButton.imagePosition = .imageLeading
			supportButton.imageScaling = .scaleProportionallyDown
		supportButton.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
		supportButton.setContentHuggingPriority(.required, for: .horizontal)
		supportButton.setContentCompressionResistancePriority(.required, for: .horizontal)
		supportButton.translatesAutoresizingMaskIntoConstraints = false

		let titleRow = NSView()
		titleRow.translatesAutoresizingMaskIntoConstraints = false
		titleRow.addSubview(nameField)
		titleRow.addSubview(supportButton)
		titleRow.setContentHuggingPriority(.required, for: .vertical)
		titleRow.setContentCompressionResistancePriority(.required, for: .vertical)

		let versionField = Self.makeLabel(font: .systemFont(ofSize: NSFont.systemFontSize(for: .small)), color: .secondaryLabelColor)
		versionField.wantsLayer = true

		let dateField = Self.makeLabel(font: .systemFont(ofSize: NSFont.systemFontSize(for: .small)), color: .secondaryLabelColor)
		dateField.wantsLayer = true

		let labelStack = NSStackView(views: [titleRow, versionField, dateField])
		labelStack.orientation = .vertical
		labelStack.alignment = .leading
		labelStack.spacing = 0
		labelStack.detachesHiddenViews = true
		labelStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
		labelStack.setContentHuggingPriority(.required, for: .vertical)
		labelStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		labelStack.setContentCompressionResistancePriority(.required, for: .vertical)
		labelStack.translatesAutoresizingMaskIntoConstraints = false

		let updateButton = UpdateButton(frame: .zero)
		updateButton.cell = UpdateButtonCell()
		updateButton.target = updateButton
		updateButton.action = #selector(UpdateButton.performAction(_:))
		updateButton.isBordered = false
		updateButton.contentTintColor = UpdateButton.Style.tintColor
		updateButton.showActionButton = true
		updateButton.translatesAutoresizingMaskIntoConstraints = false

		let externalUpdateLabel = Self.makeLabel(
			font: .systemFont(ofSize: NSFont.systemFontSize(for: .mini)),
			color: .labelColor
		)
		externalUpdateLabel.alignment = .center
		externalUpdateLabel.maximumNumberOfLines = 1
		externalUpdateLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
		externalUpdateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

		let actionContainer = NSView()
		actionContainer.setContentHuggingPriority(.required, for: .horizontal)
		actionContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
		actionContainer.setContentHuggingPriority(.required, for: .vertical)
		actionContainer.translatesAutoresizingMaskIntoConstraints = false
		actionContainer.addSubview(updateButton)
		actionContainer.addSubview(externalUpdateLabel)

		contentStack.addArrangedSubview(iconImageView)
		contentStack.addArrangedSubview(labelStack)
		contentStack.addArrangedSubview(actionContainer)

		let separator = NSBox()
		separator.boxType = .separator
		separator.translatesAutoresizingMaskIntoConstraints = false

		headerView.addSubview(contentStack)
		headerView.addSubview(separator)
		rootView.addSubview(headerView)

		let externalUpdateLabelCenterConstraint = externalUpdateLabel.centerXAnchor.constraint(equalTo: updateButton.centerXAnchor)
		externalUpdateLabelCenterConstraint.priority = .required
		let labelCenterYConstraint = labelStack.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor)

		NSLayoutConstraint.activate([
			headerView.topAnchor.constraint(equalTo: rootView.topAnchor),
			headerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
			headerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
			headerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),

			contentStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
			contentStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
			contentStack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -15),

			iconImageView.widthAnchor.constraint(equalToConstant: 64),
			iconImageView.heightAnchor.constraint(equalTo: iconImageView.widthAnchor),
			labelCenterYConstraint,
			labelStack.topAnchor.constraint(greaterThanOrEqualTo: iconImageView.topAnchor, constant: 2),
			labelStack.bottomAnchor.constraint(lessThanOrEqualTo: iconImageView.bottomAnchor, constant: -2),

			titleRow.heightAnchor.constraint(equalToConstant: 19),
			nameField.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
			nameField.topAnchor.constraint(equalTo: titleRow.topAnchor, constant: 1),
			nameField.heightAnchor.constraint(equalToConstant: 16),
			supportButton.leadingAnchor.constraint(equalTo: nameField.trailingAnchor, constant: 8),
			supportButton.topAnchor.constraint(equalTo: titleRow.topAnchor),
			supportButton.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),
			supportButton.heightAnchor.constraint(equalToConstant: 19),

			updateButton.widthAnchor.constraint(equalToConstant: 59),
			updateButton.heightAnchor.constraint(equalToConstant: 24),
			updateButton.topAnchor.constraint(equalTo: iconImageView.topAnchor, constant: 7),
			updateButton.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
			externalUpdateLabel.topAnchor.constraint(equalTo: updateButton.bottomAnchor, constant: 5),
			externalUpdateLabelCenterConstraint,
			externalUpdateLabel.bottomAnchor.constraint(equalTo: actionContainer.bottomAnchor),
			actionContainer.widthAnchor.constraint(equalTo: updateButton.widthAnchor),
			actionContainer.heightAnchor.constraint(equalToConstant: 40),

			separator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
			separator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor)
		])

		self.appInfoBackgroundView = headerView
		self.appInfoContentView = contentStack
		self.updateButton = updateButton
		self.externalUpdateLabel = externalUpdateLabel
		self.appNameTextField = nameField
		self.appDateTextField = dateField
		self.appVersionTextField = versionField
		self.appIconImageView = iconImageView
		self.supportStateButton = supportButton
		self.appInfoLabelCenterYConstraint = labelCenterYConstraint
		self.view = rootView
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		supportStateButton.target = self
		supportStateButton.action = #selector(showSupportStateInfo(_:))
	}
    
    override func viewWillAppear() {
        super.viewWillAppear()

		if appInfoTopConstraint == nil, let contentLayoutGuide = self.view.window?.contentLayoutGuide as? NSLayoutGuide {
			appInfoTopConstraint = self.appInfoContentView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor)
			appInfoTopConstraint?.isActive = true
		}

		self.setEmptyState()
	}
	
    
    
    // MARK: - Actions
    
    @objc func update(_ sender: NSButton) {
        self.app?.performUpdate()
    }
	
	@objc func cancelUpdate(_ sender: NSButton) {
		self.app?.cancelUpdate()
	}

	@objc private func showSupportStateInfo(_ sender: NSButton) {
		guard let app else { return }

		let controller = SupportStatusInfoViewController.makeController(app: app)
		let popover = NSPopover()
		popover.behavior = .transient
		popover.contentViewController = controller
		controller.loadViewIfNeeded()
		popover.contentSize = controller.preferredContentSize
		popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
		supportStatePopover = popover
	}
    
    
    // MARK: - Display Methods
    
    /**
     Loads the content of the URL and displays them
     - parameter content: The content to be displayed
     */
	func display(releaseNotesFor app: App?) {
		displayRequestID = UUID()
		let requestID = displayRequestID
		loadingTimer?.invalidate()
		loadingTimer = nil

		guard let app = app else {
			self.setEmptyState()
			return
		}
		
        self.display(app)

		// Delay the loading screen to avoid flickering
		loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
			Task { @MainActor in
				guard let self,
				      self.displayRequestID == requestID,
				      self.app?.identifier == app.identifier else { return }
				self.loadingTimer = nil
				self.loadContent(.loading)
			}
		}
		releaseNotesProvider.releaseNotes(for: app) { result in
			guard self.displayRequestID == requestID, self.app?.identifier == app.identifier else { return }
			self.loadingTimer?.invalidate()
			self.loadingTimer = nil

			switch result {
				case .success(let releaseNotes):
					self.update(with: releaseNotes)
				case .failure(let error):
					self.show(error)
			}
		}
    }
	
    
    // MARK: - User Interface Stuff
	
	/// Date formatter used to display the apps update date.
	private lazy var appDateFormatter: DateFormatter = {
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .long
		dateFormatter.timeStyle = .none
		
		return dateFormatter
	}()
    
    private func display(_ app: App) {
		// Update header
        self.appInfoBackgroundView.isHidden = false
        self.app = app
        self.appNameTextField.stringValue = app.name
        
		// Version Information
        if let versionInformation = app.localizedVersionInformation {
			self.appVersionTextField.stringValue = versionInformation.combined(includeNew: app.updateAvailable)
		}
		
		// Support state
		self.supportStateButton.isHidden = !(AppListSettings.shared.includeUnsupportedApps || AppListSettings.shared.includeAppsWithLimitedSupport)
		if !self.supportStateButton.isHidden {
			let supportStateTitle = app.source.supportState.compactLabel
			self.supportStateButton.title = supportStateTitle
			self.supportStateButton.attributedTitle = Self.makeSupportStateTitle(supportStateTitle)
			self.supportStateButton.image = app.source.supportState.statusImage
			self.supportStateButton.invalidateIntrinsicContentSize()
		}
		
		// Icon
		IconCache.shared.icon(for: app) { (image) in
			guard self.app?.identifier == app.identifier else { return }
			self.appIconImageView.image = image
		}
		
		// Date
		if let date = app.latestUpdateDate {
			self.appDateTextField.stringValue = appDateFormatter.string(from: date)
			self.appDateTextField.isHidden = false
			self.appInfoLabelCenterYConstraint?.constant = 0
		} else {
			self.appDateTextField.isHidden = true
			self.appInfoLabelCenterYConstraint?.constant = 7
		}
		
		// Update Action
		if app.updateAvailable, let name = app.externalUpdaterName {
			externalUpdateLabel.stringValue = String(format: NSLocalizedString("ExternalUpdateActionWithAppName", comment: "An explanatory text indicating where the update will be performed. The placeholder will be filled with the name of the external updater (App Store, App Name). The text will appear below the Update button, so that it reads: \"Update in XY\""), name)
		} else {
			externalUpdateLabel.stringValue = ""
		}
        
        
        self.updateInsets()
    }
	
	private func setEmptyState() {
		self.app = nil
		
		// Prepare for empty state
		let error = LatestError.custom(title: NSLocalizedString("NoAppSelectedTitle", comment: "Title of release notes empty state"),
									   description: NSLocalizedString("NoAppSelectedDescription", comment: "Description of release notes empty state"))
		self.show(error)

		self.appInfoBackgroundView.isHidden = true
	}
        
	private func loadContent(_ type: ReleaseNotesContent.ContentType) {
        // Remove the old content
        if let oldController = self.content?.controller {
            oldController.view.removeFromSuperview()
            oldController.removeFromParent()
        }
            
        self.initializeContent(of: type)
        
        guard let controller = self.content?.controller else { return }
        let view = controller.view
        
        self.addChild(controller)
        self.view.addSubview(view, positioned: .below, relativeTo: self.view.subviews.first)
        view.translatesAutoresizingMaskIntoConstraints = false
        
		let topAnchor = type.isScrollable || self.app == nil ? self.view.topAnchor : appInfoBackgroundView.bottomAnchor
		
        var constraints = [NSLayoutConstraint]()
        
        constraints.append(topAnchor.constraint(equalTo: view.topAnchor, constant: 0))
        constraints.append(self.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0))
        constraints.append(self.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0))
        constraints.append(self.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0))
        
        NSLayoutConstraint.activate(constraints)
		
		self.updateInsets()
    }
        
    private func initializeContent(of type: ReleaseNotesContent.ContentType) {
        switch type {
        case .loading:
            let controller = ReleaseNotesLoadingViewController.makeController()
            self.content = .loading(controller)
        case .error:
            let controller = ReleaseNotesErrorViewController.makeController()
            self.content = .error(controller)
        case .text:
            let controller = ReleaseNotesTextViewController.makeController()
            self.content = .text(controller)
        }
    }
    
    /// This method unwraps the data into a string, that is then formatted and displayed.
	///
	/// - parameter data: The data to be displayed. It has to be some text or HTML, other types of data will result in an error message displayed to the user
    private func update(with string: NSAttributedString) {
		guard !string.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			self.show(LatestError.releaseNotesUnavailable)
			return
		}

        self.loadContent(.text)
        self.content?.textController?.set(string)
        self.updateInsets()
    }
    
    /// Updates the top inset of the release notes scrollView
    private func updateInsets() {
        let inset = self.appInfoBackgroundView.frame.size.height
        self.content?.textController?.updateInsets(with: inset)
    }
    
    /// Switches the content to error and displays the localized error
	private func show(_ error: Error) {
        self.loadContent(.error)
        self.content?.errorController?.show(error)
    }
	
}

private extension ReleaseNotesViewController {
	static func makeLabel(font: NSFont, color: NSColor) -> NSTextField {
		let field = NSTextField(labelWithString: "")
		field.focusRingType = .none
		field.font = font
		field.textColor = color
		field.lineBreakMode = .byClipping
		field.translatesAutoresizingMaskIntoConstraints = false
		return field
	}

	static func makeSupportStateTitle(_ title: String) -> NSAttributedString {
		NSAttributedString(
			string: title,
			attributes: [
				.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
				.foregroundColor: NSColor.controlAccentColor
			]
		)
	}
}
