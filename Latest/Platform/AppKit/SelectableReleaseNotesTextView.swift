//
//  SelectableReleaseNotesTextView.swift
//  Latest
//
//  Created by Codex on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI

enum ReleaseNotesTextFormatter {
	static func format(_ attributedString: NSAttributedString) -> NSAttributedString {
		let string = NSMutableAttributedString(attributedString: attributedString)
		string.mutableString.replaceOccurrences(
			of: "\t",
			with: " ",
			options: [],
			range: NSRange(location: 0, length: string.length)
		)

		let textRange = NSRange(location: 0, length: string.length)
		let defaultFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
		string.removeAttribute(.foregroundColor, range: textRange)
		string.addAttribute(.foregroundColor, value: NSColor.labelColor, range: textRange)
		string.removeAttribute(.backgroundColor, range: textRange)
		string.removeAttribute(.shadow, range: textRange)
		string.removeAttribute(.font, range: textRange)
		string.addAttribute(.font, value: defaultFont, range: textRange)

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.alignment = .left
		paragraphStyle.firstLineHeadIndent = 0
		paragraphStyle.headIndent = 0
		paragraphStyle.tabStops = []
		string.removeAttribute(.paragraphStyle, range: textRange)
		string.addAttribute(.paragraphStyle, value: paragraphStyle, range: textRange)

		attributedString.enumerateAttribute(.font, in: textRange) { fontObject, range, _ in
			guard let font = fontObject as? NSFont else { return }
			let descriptor = defaultFont.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits)
			if let replacement = NSFont(descriptor: descriptor, size: defaultFont.pointSize) {
				string.addAttribute(.font, value: replacement, range: range)
			}
		}

		return string
	}
}

struct SelectableReleaseNotesTextView: NSViewRepresentable {
	let text: NSAttributedString

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeNSView(context: Context) -> NSScrollView {
		let scrollView = NSScrollView()
		scrollView.drawsBackground = false
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.automaticallyAdjustsContentInsets = false
		scrollView.contentInsets = NSEdgeInsets(
			top: VisualMetrics.releaseNotesTextInset,
			left: VisualMetrics.releaseNotesTextInset,
			bottom: VisualMetrics.releaseNotesTextInset,
			right: VisualMetrics.releaseNotesTextInset
		)
		scrollView.scrollerInsets = NSEdgeInsets(
			top: -VisualMetrics.releaseNotesTextInset,
			left: -VisualMetrics.releaseNotesTextInset,
			bottom: -VisualMetrics.releaseNotesTextInset,
			right: -VisualMetrics.releaseNotesTextInset
		)

		let textView = NSTextView()
		textView.drawsBackground = false
		textView.isEditable = false
		textView.isSelectable = true
		textView.allowsUndo = false
		textView.isRichText = true
		textView.importsGraphics = false
		textView.textContainerInset = .zero
		textView.textContainer?.widthTracksTextView = true
		textView.textContainer?.containerSize = NSSize(
			width: scrollView.contentSize.width,
			height: CGFloat.greatestFiniteMagnitude
		)
		textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
		textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.autoresizingMask = [.width]
		textView.setAccessibilityIdentifier("release-notes.text")
		textView.setAccessibilityLabel("Release Notes")

		scrollView.documentView = textView
		context.coordinator.textView = textView
		context.coordinator.apply(text)
		return scrollView
	}

	func updateNSView(_ scrollView: NSScrollView, context: Context) {
		context.coordinator.apply(text)
	}

	@MainActor
	final class Coordinator {
		weak var textView: NSTextView?
		private var displayedText: NSAttributedString?

		func apply(_ text: NSAttributedString) {
			guard displayedText !== text else { return }
			displayedText = text
			let formatted = ReleaseNotesTextFormatter.format(text)
			textView?.textStorage?.setAttributedString(formatted)
			textView?.setSelectedRange(NSRange(location: 0, length: 0))
			textView?.scrollRangeToVisible(NSRange(location: 0, length: 0))
		}
	}
}
