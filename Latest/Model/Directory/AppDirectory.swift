//
//  DirectoryObserver.swift
//  Latest
//
//  Created by Max Langer on 02.01.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import Cocoa

/// The folder listener listens for changes in the given directory and then runs the update checker on changes
class AppDirectory: @unchecked Sendable {
	
	/// The url on which the listener reacts to changes on
	let url : URL
	
	/// The bundles collected within this directory.
	var bundles: [App.Bundle] {
		collectionQueue.sync {
			collectedBundles
		}
	}

	private var collectedBundles = [App.Bundle]()
	
	typealias UpdateHandler = () -> Void
	typealias RefreshCompletion = @Sendable () -> Void
	
	/// The handler to be called once the directory contents change.
	let handler: UpdateHandler
	
	/// The queue on which updates to the collection are being performed.
	private let collectionQueue: DispatchQueue

	
	/// The file system listener
	private lazy var listener : DispatchSourceFileSystemObject? = {
		let descriptor = open((self.url as NSURL).fileSystemRepresentation, O_EVTONLY)
		guard descriptor != -1 else { return nil }
		
		let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
															   eventMask: .write)
		
		source.setEventHandler { [weak self] in
			self?.collectBundles()
		}
		source.setCancelHandler {
			close(descriptor)
		}
		
		return source
	}()
	
	/// Initializes the class and resumes the listener automatically
	init(
		url: URL,
		notifyOnInitialCollection: Bool = true,
		initialCollectionCompletion: RefreshCompletion? = nil,
		updateHandler: @escaping UpdateHandler
	) {
		self.url = url
		self.handler = updateHandler
		self.collectionQueue = DispatchQueue(label: "AppDirectoryCollectionQueue.\(url.path)")
		
		resumeTracking(
			notifyHandler: notifyOnInitialCollection,
			completion: initialCollectionCompletion
		)
	}
	
	deinit {
		listener?.cancel()
	}

	/// Forces the directory contents to be read from disk.
	func refresh(completion: RefreshCompletion? = nil) {
		collectBundles(notifyHandler: false, completion: completion)
	}
	
	/// Resumes tracking if it is not already running
	private func resumeTracking(notifyHandler: Bool, completion: RefreshCompletion?) {
		listener?.activate()
		collectBundles(notifyHandler: notifyHandler, completion: completion)
	}
	
	/// Triggers an update run
	private func collectBundles(notifyHandler: Bool = true, completion: RefreshCompletion? = nil) {
		collectionQueue.async {
			self.collectedBundles = BundleCollector.collectBundles(at: self.url)
			if notifyHandler {
				self.handler()
			}
			completion?()
		}
	}
	
}
