//
//  Observable.swift
//  Latest
//
//  Created by Max Langer on 20.01.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import Foundation

/// A uniquely identifiable observer.
protocol Observer: Identifiable where ID == UUID {}

/// A main-actor observable object.
@MainActor
protocol Observable: AnyObject {
	
	/// The handler called when an observation is notified.
	typealias ObservationHandler = @MainActor () -> Void
	
	/// The list of observers.
	var observers: [UUID: ObservationHandler] { get set }

	/// Adds the observer with the given handler to the list of observers.
	func add(_ observer: any Observer, handler: @escaping ObservationHandler)
	
	/// Removes the given observer from the list.
	func remove(_ observer: any Observer)
	
	/// Notifies the observers of an observation.
	func notify()
		
}

extension Observable {
	
	func add(_ observer: any Observer, handler: @escaping ObservationHandler) {
		observers[observer.id] = handler
	}
	
	func remove(_ observer: any Observer) {
		observers.removeValue(forKey: observer.id)
	}
	
	func notify() {
		observers.forEach({ $1() })
	}
	
}

/// Stores object-bound observers and guarantees notification on the main actor.
@MainActor
final class MainActorObserverRegistry<Value> {

	/// The handler called when observers are notified.
	typealias Handler = @MainActor (Value) -> Void

	private var handlers = [ObjectIdentifier: Handler]()

	/// Whether the registry currently has no observers.
	var isEmpty: Bool {
		handlers.isEmpty
	}

	/// Adds the observer if it is not already registered.
	@discardableResult
	func add(_ observer: NSObject, handler: @escaping Handler) -> Bool {
		add(ObjectIdentifier(observer), handler: handler)
	}

	/// Adds or replaces the observer identifier.
	@discardableResult
	func add(_ identifier: ObjectIdentifier, handler: @escaping Handler) -> Bool {
		let isNewObserver = handlers[identifier] == nil
		handlers[identifier] = handler
		return isNewObserver
	}

	/// Removes the given observer.
	func remove(_ observer: NSObject) {
		remove(ObjectIdentifier(observer))
	}

	/// Removes the given observer identifier.
	func remove(_ identifier: ObjectIdentifier) {
		handlers.removeValue(forKey: identifier)
	}

	/// Notifies all registered observers with the given value.
	func notify(with value: Value) {
		handlers.values.forEach { handler in
			handler(value)
		}
	}

}
