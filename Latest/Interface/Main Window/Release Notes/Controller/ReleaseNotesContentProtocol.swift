//
//  ReleaseNotesContentProtocol.swift
//  Latest
//
//  Created by Max Langer on 12.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import AppKit

/// Storyboard identifiers for release-notes content controllers.
enum ReleaseNotesContentStoryboardIdentifier {
	static let loading = NSStoryboard.SceneIdentifier("ReleaseNotesLoadingViewControllerIdentifier")
	static let error = NSStoryboard.SceneIdentifier("ReleaseNotesErrorViewControllerIdentifier")
	static let text = NSStoryboard.SceneIdentifier("ReleaseNotesTextViewControllerIdentifier")
}

/// This protocol manages the instantiation of the content controllers
@MainActor
protocol ReleaseNotesContentProtocol {
    
    /// The type of the viewController
    associatedtype ReleaseNotesContentController: NSViewController
    
    /// The identifier from which the object is instantiated
    static var storyboardIdentifier: NSStoryboard.SceneIdentifier { get }
    
    /// The method loading the storyboard
    static func fromStoryboard() -> ReleaseNotesContentController?
    
}

extension ReleaseNotesContentProtocol {
    static func fromStoryboard() -> ReleaseNotesContentController? {
        let storyboard = NSStoryboard(name: .main, bundle: nil)
        
        return storyboard.instantiateController(withIdentifier: storyboardIdentifier) as? ReleaseNotesContentController
    }
}

private extension NSStoryboard.Name {
	static let main = NSStoryboard.Name("Main")
}
