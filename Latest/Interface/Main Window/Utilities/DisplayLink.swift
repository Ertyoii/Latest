//
//  DisplayLink.swift
//
//  Created by Max Langer on 23.05.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Foundation
import QuartzCore

/// Cross-platform convenience for accessing a DisplayLink.
final class DisplayLink: NSObject, @unchecked Sendable {

    /// The amount of time the display link should be running. `nil` makes it indefinite.
    private let duration: Double?

    /// Optional completion handler called after the animation finishes.
    var completionHandler: (() -> Void)?

    /// The current animation progress.
    private(set) var progress: Double = 0

    /// Timer driving the animation updates.
    private var timer: Timer?

    /// Callback invoked every tick.
    private(set) var callback: ((_ progress: Double) -> Void)!

    /// Tracking timestamps for duration calculations.
    private var startTime: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval = 0


    // MARK: - Initialization

    /// Initializes the display link with a duration and callback.
    init(duration: Double?, callback: @escaping ((_ progress: Double) -> Void)) {
        self.duration = duration
        self.callback = callback
        super.init()
    }


    // MARK: - Animation

    @objc private func displayTick(_ timer: Timer) {
        let now = CACurrentMediaTime()
        let delta = now - self.lastTimestamp
        self.lastTimestamp = now

        if let duration = self.duration {
            let elapsed = now - self.startTime
            self.progress = min(1, elapsed / duration)
        } else {
            self.progress += delta * 60
        }

        self.callback(self.progress)

        if self.duration != nil && self.progress >= 1 {
            self.completionHandler?()
            self.stop()
        }
    }


    // MARK: - Actions

    /// Starts the animation loop.
    func start() {
        self.stop()

        let now = CACurrentMediaTime()
        self.startTime = now
        self.lastTimestamp = now
        self.progress = 0

        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(displayTick(_:)), userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Stops the animation loop.
    func stop() {
        self.timer?.invalidate()
        self.timer = nil
    }

    /// Whether the display link is actively running.
    var isRunning: Bool {
        self.timer != nil
    }

}
