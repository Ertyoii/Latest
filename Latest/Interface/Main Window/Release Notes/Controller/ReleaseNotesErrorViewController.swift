//
//  ReleaseNotesErrorViewController.swift
//  Latest
//
//  Created by Max Langer on 12.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import Cocoa

/// The controller presenting errors to the user
class ReleaseNotesErrorViewController: NSViewController {

    /// The textField holding the error title
    @IBOutlet private weak var titleTextField: NSTextField!
    
    /// The textField holding the error description
    @IBOutlet private weak var descriptionTextField: NSTextField!

	override func loadView() {
		let view = NSView()
		let stackView = NSStackView()
		stackView.orientation = .vertical
		stackView.alignment = .centerX
		stackView.spacing = 8
		stackView.translatesAutoresizingMaskIntoConstraints = false

		let titleTextField = NSTextField(labelWithString: "")
		titleTextField.alignment = .center
		titleTextField.font = .preferredFont(forTextStyle: .headline)
		titleTextField.lineBreakMode = .byWordWrapping
		titleTextField.maximumNumberOfLines = 0

		let descriptionTextField = NSTextField(labelWithString: "")
		descriptionTextField.alignment = .center
		descriptionTextField.lineBreakMode = .byWordWrapping
		descriptionTextField.maximumNumberOfLines = 0

		stackView.addArrangedSubview(titleTextField)
		stackView.addArrangedSubview(descriptionTextField)
		view.addSubview(stackView)
		NSLayoutConstraint.activate([
			stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
			stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
			stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
		])

		self.titleTextField = titleTextField
		self.descriptionTextField = descriptionTextField
		self.view = view
	}
 
    /// Updates the description of the error
    func show(_ error: Error) {
		titleTextField.stringValue = ""
		descriptionTextField.stringValue = ""

		if let localizedError = error as? LocalizedError, let failureReason = localizedError.failureReason {
			titleTextField.stringValue = localizedError.localizedDescription
			descriptionTextField.stringValue = failureReason
		} else {
			descriptionTextField.stringValue = error.localizedDescription
		}
    }
    
}

extension ReleaseNotesErrorViewController: ReleaseNotesContentProtocol {
    
    typealias ReleaseNotesContentController = ReleaseNotesErrorViewController

	static func makeController() -> ReleaseNotesErrorViewController {
		ReleaseNotesErrorViewController()
	}
    
}
