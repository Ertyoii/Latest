//
//  Observable.swift
//  Latest
//
//  Created by Max Langer on 20.01.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import Foundation

/// Produces bounded async state feeds and automatically removes terminated consumers.
@MainActor
final class MainActorAsyncStreamRegistry<Value: Sendable> {
	private var continuations = [UUID: AsyncStream<Value>.Continuation]()

	func stream(initialValue: Value) -> AsyncStream<Value> {
		let identifier = UUID()
		let (stream, continuation) = AsyncStream.makeStream(
			of: Value.self,
			bufferingPolicy: .bufferingNewest(1)
		)
		continuations[identifier] = continuation
		continuation.yield(initialValue)
		continuation.onTermination = { [weak self] _ in
			Task { @MainActor [weak self] in
				self?.continuations.removeValue(forKey: identifier)
			}
		}
		return stream
	}

	func yield(_ value: Value) {
		for continuation in continuations.values {
			continuation.yield(value)
		}
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
