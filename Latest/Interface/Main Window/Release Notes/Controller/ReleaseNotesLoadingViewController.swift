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
    // Outlets
    @IBOutlet var activityIndicator: NSProgressIndicator!
    @IBOutlet var horizontalConstraint: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()

        activityIndicator.startAnimation(nil)
    }
}

extension ReleaseNotesLoadingViewController: ReleaseNotesContentProtocol {
    typealias ReleaseNotesContentController = ReleaseNotesLoadingViewController

    static var StoryboardIdentifier: String {
        "ReleaseNotesLoadingViewControllerIdentifier"
    }
}
