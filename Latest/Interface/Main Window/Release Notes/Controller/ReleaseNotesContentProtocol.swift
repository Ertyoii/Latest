//
//  ReleaseNotesContentProtocol.swift
//  Latest
//
//  Created by Max Langer on 12.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import AppKit

/// This protocol manages the instantiation of release-notes content controllers.
@MainActor
protocol ReleaseNotesContentProtocol {
    
    /// The type of the viewController
    associatedtype ReleaseNotesContentController: NSViewController
    
    /// Creates a release-notes content controller.
    static func makeController() -> ReleaseNotesContentController
    
}
