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
