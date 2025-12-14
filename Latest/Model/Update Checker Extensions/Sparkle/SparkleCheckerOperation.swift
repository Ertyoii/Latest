//
//  MacAppStoreUpdateCheckerOperation.swift
//  Latest
//
//  Created by Max Langer on 03.10.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import Cocoa
import Foundation

/// The operation for checking for updates for a Sparkle app.
class SparkleUpdateCheckerOperation: StatefulOperation, UpdateCheckerOperation, @unchecked Sendable {
	
	// MARK: - Update Check
	
	static func canPerformUpdateCheck(forAppAt url: URL) -> Bool {
		// Can check for updates if a feed URL is available for the given app
		return Self.feedURL(from: url) != nil
	}

	static var sourceType: App.Source {
		return .sparkle
	}
	
	required init(with app: App.Bundle, repository: UpdateRepository?, completionBlock: @escaping UpdateCheckerCompletionBlock) {
		self.app = app
		self.url = Self.feedURL(from: app.fileURL)
		
		super.init()

		self.completionBlock = {
			if self.isCancelled {
				completionBlock(.failure(CancellationError()))
				return
			}

			if let update = self.update {
				completionBlock(.success(update))
			} else {
				completionBlock(.failure(self.error ?? LatestError.updateInfoUnavailable))
			}
		}
	}
	
	/// Returns the Sparkle feed url for the app at the given URL, if available.
	private static func feedURL(from appURL: URL) -> URL? {
		guard let bundle = Bundle(path: appURL.path) else { return nil }
		return Sparke.feedURL(from: bundle)
	}

	/// The bundle to be checked for updates.
	private let app: App.Bundle
	
	/// The url to check for updates.
	private let url: URL?
	
	/// The update fetched during the checking operation.
	fileprivate var update: App.Update?
	
	private var task: URLSessionDataTask?
	private func finishIfNeeded(with error: Error? = nil) {
		guard !self.isFinished else { return }
		self.task = nil

		if let error {
			super.finish(with: error)
		} else {
			super.finish()
		}
	}

	
	// MARK: - Operation
	
	override func execute() {
		guard let url else {
			finishIfNeeded(with: LatestError.updateInfoUnavailable)
			return
		}

		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
		let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
			guard let self else { return }

			if self.isCancelled {
				self.finishIfNeeded(with: CancellationError())
				return
			}
			
			if let error {
				self.finishIfNeeded(with: error)
				return
			}
			
			guard let data, !data.isEmpty else {
				self.finishIfNeeded(with: LatestError.updateInfoUnavailable)
				return
			}
			
			do {
				let item = try SparkleAppcastParser.parseFirstItem(from: data)
				
				let version = Version(versionNumber: item.shortVersionString, buildNumber: item.version)
				let minimumOSVersion = try item.minimumSystemVersion.flatMap(OperatingSystemVersion.init(string:))
				
				var releaseNotes: App.Update.ReleaseNotes? = nil
				if let html = item.descriptionHTML, !html.isEmpty {
					releaseNotes = .html(string: html)
				} else if let url = item.releaseNotesURL {
					releaseNotes = .url(url: url)
				}
				
				self.update = App.Update(
					app: self.app,
					remoteVersion: version,
					minimumOSVersion: minimumOSVersion,
					source: .sparkle,
					date: item.pubDate,
					releaseNotes: releaseNotes,
					updateAction: .builtIn(block: { app in
						UpdateQueue.shared.addOperation(SparkleUpdateOperation(bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier))
					})
				)
				
				self.finishIfNeeded()
			} catch {
				self.finishIfNeeded(with: error)
			}
		}
		
		self.task = task
		task.resume()
	}
	
	override func cancel() {
		super.cancel()
		self.task?.cancel()
		self.finishIfNeeded(with: CancellationError())
	}
}

private struct SparkleAppcastItem {
	var version: String?
	var shortVersionString: String?
	var minimumSystemVersion: String?
	var descriptionHTML: String?
	var releaseNotesURL: URL?
	var pubDate: Date?
}

private enum SparkleAppcastParser {
	static func parseFirstItem(from data: Data) throws -> SparkleAppcastItem {
		let parser = XMLParser(data: data)
		let delegate = Delegate()
		parser.delegate = delegate
		
		let success = parser.parse()
		if let item = delegate.firstItem {
			return item
		}
		
		if !success {
			throw parser.parserError ?? LatestError.updateInfoUnavailable
		}
		
		throw LatestError.updateInfoUnavailable
	}
	
	private final class Delegate: NSObject, XMLParserDelegate {
		private(set) var firstItem: SparkleAppcastItem?
		
		private var currentElement: String?
		private var currentText = ""
		private var isInsideItem = false
		
		private var pendingItem = SparkleAppcastItem()
		private var releaseNotesCandidates: [(lang: String?, url: URL)] = []
		
		func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
			currentElement = qName ?? elementName
			currentText = ""
			
			if elementName == "item" {
				isInsideItem = true
				pendingItem = SparkleAppcastItem()
				releaseNotesCandidates = []
				return
			}
			
			guard isInsideItem else { return }
			
			if elementName == "enclosure" {
				// Sparkle stores versions on the enclosure.
				pendingItem.version = attributeDict["sparkle:version"] ?? pendingItem.version
				pendingItem.shortVersionString = attributeDict["sparkle:shortVersionString"] ?? pendingItem.shortVersionString
				pendingItem.minimumSystemVersion = attributeDict["sparkle:minimumSystemVersion"] ?? pendingItem.minimumSystemVersion
			}
			
			if elementName == "releaseNotesLink" || (qName?.hasSuffix(":releaseNotesLink") ?? false) {
				// Collect candidates; we select after finishing the item.
				if let urlString = attributeDict["href"], let url = URL(string: urlString) {
					releaseNotesCandidates.append((lang: attributeDict["xml:lang"], url: url))
				}
			}
		}
		
		func parser(_ parser: XMLParser, foundCharacters string: String) {
			currentText += string
		}
		
		func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
			defer {
				currentElement = nil
				currentText = ""
			}
			
			if elementName == "item" {
				isInsideItem = false
				if pendingItem.releaseNotesURL == nil {
					pendingItem.releaseNotesURL = chooseReleaseNotesURL(from: releaseNotesCandidates)
				}
				firstItem = pendingItem
				parser.abortParsing()
				return
			}
			
			guard isInsideItem else { return }
			
			let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !value.isEmpty else { return }
			
			switch elementName {
			case "description":
				pendingItem.descriptionHTML = value
			case "pubDate":
				pendingItem.pubDate = RFC822DateParser.formatter.date(from: value)
			case "minimumSystemVersion":
				pendingItem.minimumSystemVersion = value
			case "releaseNotesLink":
				// Some feeds use element text instead of href.
				if let url = URL(string: value) {
					releaseNotesCandidates.append((lang: nil, url: url))
				}
			default:
				// Handle namespaced elements by suffix.
				if (qName ?? "").hasSuffix(":minimumSystemVersion") {
					pendingItem.minimumSystemVersion = value
				} else if (qName ?? "").hasSuffix(":releaseNotesLink"), let url = URL(string: value) {
					releaseNotesCandidates.append((lang: nil, url: url))
				}
			}
		}
		
		private func chooseReleaseNotesURL(from candidates: [(lang: String?, url: URL)]) -> URL? {
			guard !candidates.isEmpty else { return nil }
			
			let preferredLang = Locale.current.languageCode
			if let preferredLang, let match = candidates.first(where: { $0.lang == preferredLang }) {
				return match.url
			}
			
			if let match = candidates.first(where: { $0.lang == "en" }) {
				return match.url
			}
			
			return candidates.first?.url
		}
	}
}

private enum RFC822DateParser {
	static let formatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
		return formatter
	}()
}
