//
//  DisplayLink.swift
//
//  Created by Max Langer on 23.05.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Foundation
import QuartzCore
#if os(macOS)
import AppKit
#endif

/// Cross-platform convenience for accessing a DisplayLink.
@MainActor
final class DisplayLink: NSObject {

	/// The amount of time the display link should be running. If  set to `nil`, the display link runs indefinitely.
	private(set) var duration : Double?
	
	/// An optional completion handler called after the display link stopped animating.
	var completionHandler : (@MainActor () -> Void)?
	
	/// The current  animation progress. Only useful if a duration has been set.
	private(set) var progress : Double = 0

	private var displayLink: CADisplayLink?

	/// Frames used to calculate the animation progress
	private var _currentFrame : Double = 0
	private var _frames : Double = 0

	/// The callback called for each animation step.
	private(set) var callback : (@MainActor (_ progress: Double) -> Void)!

	private var fallbackTimer: Timer?

	
	// MARK: - Initialization
	
	/// Initializes the display link with the given duration and callback.
	init(duration: Double?, callback: @escaping @MainActor (_ progress: Double) -> Void) {
		super.init()

		self.duration = duration
		self.callback = callback

		#if os(macOS)
		if let screen = NSScreen.main ?? NSScreen.screens.first {
			self.displayLink = screen.displayLink(target: self, selector: #selector(DisplayLink.displayTick(_:)))
		}
		#else
		self.displayLink = CADisplayLink(target: self, selector: #selector(DisplayLink.displayTick(_:)))
		#endif
		self.displayLink?.add(to: .current, forMode: .common)
		self.displayLink?.isPaused = true
	}

	isolated deinit {
		invalidate()
	}


	// MARK: - Animation

	@objc private func displayTick(_ displayLink: CADisplayLink) {
		self.advanceFrame(frameDuration: displayLink.duration > 0 ? displayLink.duration : 1 / 60.0)
	}

	@objc private func timerTick(_ timer: Timer) {
		self.advanceFrame(frameDuration: 1 / 60.0)
	}

	private func advanceFrame(frameDuration: Double) {
		if let duration = self.duration {
			self._frames = duration / (1 / 60.0)
		} else {
			self._frames = 1
		}

		self._currentFrame += frameDuration / (1 / 60.0)

		// The display link and fallback timer are installed on the main run loop.
		self.progress = self._currentFrame / self._frames
		if self.duration != nil, self.progress >= 1 {
			self.completionHandler?()
			self.stop()
		}

		self.callback(self.progress)
	}

	
	// MARK: - Actions
	
	/// Starts the display link.
	func start() {
		self._currentFrame = 0
		if let displayLink {
			displayLink.isPaused = false
		} else {
			let timer = Timer(
				timeInterval: 1 / 60.0,
				target: self,
				selector: #selector(timerTick(_:)),
				userInfo: nil,
				repeats: true
			)
			self.fallbackTimer = timer
			RunLoop.current.add(timer, forMode: .common)
		}
	}

	/// Stops the display link.
	func stop() {
		displayLink?.isPaused = true
		fallbackTimer?.invalidate()
		fallbackTimer = nil
	}

	/// Invalidates the display link permanently.
	func invalidate() {
		displayLink?.invalidate()
		displayLink = nil
		fallbackTimer?.invalidate()
		fallbackTimer = nil
	}

	/// Whether the display link is currently running.
	var isRunning : Bool {
		if let displayLink {
			return !displayLink.isPaused
		}
		return fallbackTimer != nil
	}

}
