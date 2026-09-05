import Foundation

/// Encapsulates different states that may be active during the update process.
enum UpdateProgressState: Sendable {
	/// No update is occurring at the moment.
	case none

	/// The update is currently waiting to be executed. This may happen due to external constraints like the Mac App Store update queue.
	case pending

	/// The download is currently initializing. This may be fetching update information from a server.
	case initializing

	/// The new version is currently downloading. Loaded size defines the already downloaded bytes. Total size defines the final size of the download.
	case downloading(loadedSize: Int64, totalSize: Int64)

	/// The update is being extracted. The extraction progress is given.
	case extracting(progress: Double)

	/// The update is currently installing.
	case installing

	/// An error occurred during updating.
	case error(Error)

	/// The update is currently being cancelled.
	case cancelling
}

struct AppUpdateStateChange: Sendable {
	let identifier: App.Bundle.Identifier
	let state: UpdateProgressState
}

typealias UpdateStateFeed = (current: UpdateProgressState, changes: AsyncStream<UpdateProgressState>)
typealias UpdateStateObserver = @MainActor (UpdateProgressState) -> Void


/// Feature-facing update boundary. State observation stays on the main actor;
/// queue lookups and actions are safe from any caller.
protocol AppUpdating: AnyObject, Sendable {
	func isUpdating(_ app: App) -> Bool
	func update(_ app: App, isBulkUpdate: Bool)
	func cancel(_ app: App)
	func state(for identifier: App.Bundle.Identifier) -> UpdateProgressState
	@MainActor func states(for identifier: App.Bundle.Identifier) -> AsyncStream<UpdateProgressState>
	@MainActor func stateChanges(for identifier: App.Bundle.Identifier) -> UpdateStateFeed
	@MainActor func stateChanges() -> AsyncStream<AppUpdateStateChange>
	@MainActor func addObserver(_ observer: NSObject, to identifier: App.Bundle.Identifier, handler: @escaping UpdateStateObserver)
	func removeObserver(_ observer: NSObject, for identifier: App.Bundle.Identifier)
}

extension AppUpdating {
	func update(_ app: App) { update(app, isBulkUpdate: false) }
}

/// The live adapter owns the queue dependency. Domain models contain only update
/// metadata and source-provided actions; they never query global service state.
final class AppUpdateService: AppUpdating {
	static let shared = AppUpdateService(queue: .shared)
	private let queue: UpdateQueue

	init(queue: UpdateQueue) { self.queue = queue }

	func isUpdating(_ app: App) -> Bool { queue.contains(app.identifier) }
	func update(_ app: App, isBulkUpdate: Bool) {
		guard app.updateAvailable, !isUpdating(app) else { return }
		app.updateAction?.perform(with: app.bundle, isBulkUpdate: isBulkUpdate)
	}
	func cancel(_ app: App) { queue.cancelUpdate(for: app.identifier) }
	func state(for identifier: App.Bundle.Identifier) -> UpdateProgressState { queue.state(for: identifier) }
	@MainActor func states(for identifier: App.Bundle.Identifier) -> AsyncStream<UpdateProgressState> { queue.states(for: identifier) }
	@MainActor func stateChanges(for identifier: App.Bundle.Identifier) -> UpdateStateFeed { queue.stateChanges(for: identifier) }
	@MainActor func stateChanges() -> AsyncStream<AppUpdateStateChange> { queue.stateChanges() }
	@MainActor func addObserver(_ observer: NSObject, to identifier: App.Bundle.Identifier, handler: @escaping UpdateStateObserver) { queue.addObserver(observer, to: identifier, handler: handler) }
	func removeObserver(_ observer: NSObject, for identifier: App.Bundle.Identifier) { queue.removeObserver(observer, for: identifier) }
}
