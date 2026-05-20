//
//  UpdateQueue.swift
//  Latest
//
//  Created by Max Langer on 01.07.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import Foundation

/// The queue where update operations are scheduled on.
class UpdateQueue: OperationQueue, @unchecked Sendable {
	
	// MARK: - Initialization
	private override init() {
		super.init()
		
		self.maxConcurrentOperationCount = 3
	}
	
	/// The shared instance of the queue.
	static let shared = UpdateQueue()
	
	
	// MARK: - Public Methods
	
	/// The handler forwarding the current progress state.
	typealias ProgressHandler = (_: App.Bundle.Identifier) -> Void
	
	/// Cancels the update operation for the given app.
	func cancelUpdate(for identifier: App.Bundle.Identifier) {
		guard let operation = self.operation(for: identifier) else { return }
		operation.cancel()
	}
	
	/// Whether the queue contains an update operation for the given app.
	func contains(_ identifier: App.Bundle.Identifier) -> Bool {
		return self.operation(for: identifier) != nil
	}
	
	/// Returns the state for a given app.
	func state(for identifier: App.Bundle.Identifier) -> UpdateOperation.ProgressState {
		return self.operation(for: identifier)?.progressState ?? .none
	}
	
	override func addOperation(_ op: Operation) {
		// Abort if the operation is of an unknown type
		guard let operation = op as? UpdateOperation else {
			assertionFailure("Added unknown operation \(op.self) to update queue.")
			return
		}
		
		// Abort if the app is already in the queue
		if !self.contains(operation.appIdentifier) {
			super.addOperation(op)
			
			operation.progressHandler = { identifier in
				self.notifyObservers(for: identifier)
			}
		}
	}
	
	
	// MARK: - Observer Handling
	
	/// The handler for notifying observers about changes to the update state.
	typealias ObserverHandler = @MainActor (_: UpdateOperation.ProgressState) -> Void

	/// A mapping of observers associated with apps.
	@MainActor private var observers = [App.Bundle.Identifier: MainActorObserverRegistry<UpdateOperation.ProgressState>]()
	
	/// Adds the observer if it is not already registered.
	@MainActor
	func addObserver(_ observer: NSObject, to identifier: App.Bundle.Identifier, handler: @escaping ObserverHandler) {
		let observers = self.observers[identifier] ?? MainActorObserverRegistry()
		guard observers.add(observer, handler: handler) else { return }
		
		// Call handler immediately to propagate initial state
		handler(self.state(for: identifier))
		
		// Update observers
		self.observers[identifier] = observers
	}
	
	/// Removes the observer.
	func removeObserver(_ observer: NSObject, for identifier: App.Bundle.Identifier) {
		let observerIdentifier = ObjectIdentifier(observer)
		Task { @MainActor in
			self.observers[identifier]?.remove(observerIdentifier)
			if self.observers[identifier]?.isEmpty == true {
				self.observers.removeValue(forKey: identifier)
			}
		}
	}
		
	/// Notifies observers about state changes.
	private func notifyObservers(for identifier: App.Bundle.Identifier) {
		let state = self.state(for: identifier)
		
		Task { @MainActor in
			self.observers[identifier]?.notify(with: state)
		}
	}
	
	
	// MARK: - Helper
	
	/// Returns the operation for the given app.
	private func operation(for identifier: App.Bundle.Identifier) -> UpdateOperation? {
		guard let updateOperations = self.operations as? [UpdateOperation] else {
			fatalError("Unknown operations in update queue")
		}
				
		return updateOperations.first(where: { $0.appIdentifier == identifier })
	}
		
}
