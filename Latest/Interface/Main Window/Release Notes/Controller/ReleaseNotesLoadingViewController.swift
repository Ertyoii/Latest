//
//  ReleaseNotesLoadingViewController.swift
//  Latest
//
//  Created by Max Langer on 12.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import Cocoa

/// The controller presenting a small activity indicator, showing the user that release notes are currently loading
class ReleaseNotesLoadingViewController: NSViewController {
    
    @IBOutlet weak var activityIndicator: NSProgressIndicator!

	override func loadView() {
		let view = NSView()
		let activityIndicator = NSProgressIndicator()
		activityIndicator.controlSize = .regular
		activityIndicator.style = .spinning
		activityIndicator.translatesAutoresizingMaskIntoConstraints = false

		view.addSubview(activityIndicator)
		NSLayoutConstraint.activate([
			activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
		])

		self.activityIndicator = activityIndicator
		self.view = view
	}
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.activityIndicator.startAnimation(nil)
    }
	
}

extension ReleaseNotesLoadingViewController: ReleaseNotesContentProtocol {
    
    typealias ReleaseNotesContentController = ReleaseNotesLoadingViewController

	static func makeController() -> ReleaseNotesLoadingViewController {
		ReleaseNotesLoadingViewController()
	}
    
}
