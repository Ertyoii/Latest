//
//  LaunchMode.swift
//  Latest
//
//  Created by Codex on 31.05.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation

enum LaunchMode {
	static let swiftUIMainWindowDefaultsKey = "UseSwiftUIMainWindow"
	private static let swiftUIMainWindowArgument = "--swiftui-main-window"

	static var useSwiftUIMainWindow: Bool {
		UserDefaults.standard.bool(forKey: swiftUIMainWindowDefaultsKey)
			|| ProcessInfo.processInfo.arguments.contains(swiftUIMainWindowArgument)
	}
}
