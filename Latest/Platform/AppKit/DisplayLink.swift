//
//  DisplayLink.swift
//
//  Created by Max Langer on 23.05.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Foundation
import QuartzCore
import AppKit

/// Animation clock for the update button.
@MainActor
final class DisplayLink: NSObject {

	/// The amount of time the display link should be running. If  set to `nil`, the display link runs indefinitely.
	private let duration: Double?
	
	/// The current  animation progress. Only useful if a duration has been set.
	private(set) var progress : Double = 0

	private var displayLink: CADisplayLink?

	private var elapsedTime: Double = 0

	/// The callback called for each animation step.
	private let callback: @MainActor (Double) -> Void

	private var fallbackTimer: Timer?

	
	// MARK: - Initialization
	
	/// Initializes the display link with the given duration and callback.
	init(duration: Double?, callback: @escaping @MainActor (_ progress: Double) -> Void) {
		self.duration = duration
		self.callback = callback
		super.init()

		if let screen = NSScreen.main ?? NSScreen.screens.first {
			self.displayLink = screen.displayLink(target: self, selector: #selector(DisplayLink.displayTick(_:)))
		}
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
		elapsedTime += frameDuration
		// Indefinite animations expose elapsed 60-Hz frames to the spinner.
		progress = elapsedTime / (duration ?? (1 / 60.0))
		if duration != nil, progress >= 1 {
			stop()
		}

		self.callback(self.progress)
	}

	
	// MARK: - Actions
	
	/// Starts the display link.
	func start() {
		self.elapsedTime = 0
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
