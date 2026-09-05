import Foundation
import AppKit

extension ReleaseNotesMarkup {
	static func usesSourceSpecificTextExtraction(for url: URL) -> Bool {
		guard let host = url.host?.lowercased() else { return false }
		return host.contains("chromereleases.googleblog.com") ||
			host.contains("navicat.com") ||
			host.contains("zed.dev") ||
			host.contains("zoom.com")
	}

	static func relevantChangelogText(fromHTML html: String, version: String?, pageURL: URL, allowFirstSectionFallback: Bool) -> String? {
		if let relevantText = Self.navicatMacReleaseText(fromHTML: html, version: version, pageURL: pageURL) {
			return relevantText
		}

		if let relevantText = Self.zedReleaseText(fromHTML: html, version: version, pageURL: pageURL) {
			return relevantText
		}

		if let relevantText = Self.zoomReleaseText(fromHTML: html, version: version, pageURL: pageURL) {
			return relevantText
		}

		if let relevantText = Self.chromeDesktopReleaseText(fromHTML: html, version: version, pageURL: pageURL) {
			return relevantText
		}
		if pageURL.host?.localizedCaseInsensitiveContains("chromereleases.googleblog.com") == true {
			return nil
		}

		let preferredSuffix = pageURL.host?.localizedCaseInsensitiveContains("obsidian.md") == true ? "Desktop" : nil
		guard let text = Self.plainText(fromHTML: html),
			  let relevantText = Self.relevantText(from: text, version: version, allowFirstSectionFallback: allowFirstSectionFallback, preferredSuffix: preferredSuffix),
			  Self.isUsefulReleaseNotesText(relevantText, relevantVersion: version) else {
			return nil
		}

		return relevantText
	}
}

// Stable facade for source routing and existing clients.
extension ReleaseNotesMarkup {
	static func zedReleaseText(fromHTML html: String, version: String?, pageURL: URL) -> String? {
		ZedReleaseNotesExtractor.zedReleaseText(fromHTML: html, version: version, pageURL: pageURL)
	}

	static func isUsefulZedReleaseArticleText(_ text: String) -> Bool {
		ZedReleaseNotesExtractor.isUsefulZedReleaseArticleText(text)
	}

	static func zoomReleaseText(fromHTML html: String, version: String?, pageURL: URL) -> String? {
		ZoomReleaseNotesExtractor.zoomReleaseText(fromHTML: html, version: version, pageURL: pageURL)
	}

	static func navicatMacReleaseText(fromHTML html: String, version: String?, pageURL: URL) -> String? {
		NavicatReleaseNotesExtractor.navicatMacReleaseText(fromHTML: html, version: version, pageURL: pageURL)
	}

	static func chromeDesktopReleaseText(fromHTML html: String, version: String?, pageURL: URL) -> String? {
		ChromeReleaseNotesExtractor.chromeDesktopReleaseText(fromHTML: html, version: version, pageURL: pageURL)
	}
}
