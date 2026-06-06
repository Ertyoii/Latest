//
//  Sparkle.swift
//  Latest
//
//  Created by Max Langer on 23.04.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import Foundation

struct Sparke {
	
	/// Returns the Sparkle feed url for the app at the given URL, if available.
	static func feedURL(from bundle: Bundle) -> URL? {
		guard let information = bundle.infoDictionary, let identifier = bundle.bundleIdentifier else {
			return nil
		}

		return feedURL(from: information, bundleIdentifier: identifier, bundleURL: bundle.bundleURL)
	}

	/// Returns the Sparkle feed URL from already-loaded bundle metadata.
	static func feedURL(from information: [String: Any], bundleIdentifier: String, bundleURL: URL) -> URL? {
		if let urlString = information["SUFeedURL"] as? String, let feedURL = URL(string: urlString.unquoted)  {
			return feedURL
		} else { // Maybe the app is built using DevMate
			// Check for the DevMate framework
			let frameworksURL = bundleURL.appendingPathComponent("Contents").appendingPathComponent("Frameworks")
			guard FileManager.default.fileExists(atPath: frameworksURL.path) else {
				return nil
			}
			
			let frameworks = try? FileManager.default.contentsOfDirectory(atPath: frameworksURL.path)
			if !(frameworks?.contains(where: { $0.contains("DevMateKit") }) ?? false) {
				return nil
			}
			
			// The app uses Devmate, so lets get the appcast from their servers
			guard var feedURL = URL(string: "https://updates.devmate.com") else {
				return nil
			}
			
			feedURL.appendPathComponent(bundleIdentifier)
			feedURL.appendPathExtension("xml")
			
			return feedURL
		}
	}
	
}

fileprivate extension String {
	
	/// Returns the string with quotation marks trimmed.
	var unquoted: String {
		return NSString(string: self).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
	}
	
}
