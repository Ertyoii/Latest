//
//  ReleaseNotesContentViewController.swift
//  Latest
//
//  Created by Max Langer on 12.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import Cocoa

/// The controller displaying the actual release notes
class ReleaseNotesTextViewController: NSViewController {

	/// The inset of the text
	let contentInset: CGFloat = 14
	
    /// The view displaying the release notes
    @IBOutlet var textView: NSTextView!

	override func loadView() {
		let scrollView = NSScrollView()
		scrollView.drawsBackground = false
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true

		let textView = NSTextView()
		textView.drawsBackground = false
		textView.isEditable = false
		textView.isSelectable = true
		textView.textContainerInset = .zero
		textView.textContainer?.widthTracksTextView = true
		textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
		textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
		textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.autoresizingMask = [.width]

		scrollView.documentView = textView
		self.textView = textView
		self.view = scrollView
	}
    
    /// Updates the view with the given release notes
    func set(_ string: NSAttributedString) {
        // Format the release notes
        let text = self.format(string)
        
        self.textView.textStorage?.setAttributedString(text)
    }
    
    /// Updates the text views scroll insets
    func updateInsets(with inset: CGFloat) {
        let scrollView = self.textView.enclosingScrollView
        
        scrollView?.automaticallyAdjustsContentInsets = false
        scrollView?.contentInsets = NSEdgeInsetsMake(inset + contentInset, contentInset, contentInset, contentInset)
		scrollView?.scrollerInsets = NSEdgeInsetsMake(-contentInset, -contentInset, -contentInset, -contentInset)
        
        self.view.layout()
        scrollView?.documentView?.scroll(CGPoint(x: 0, y: -inset * 2))
    }
    
    // MARK: - Private Methods
    
    /**
     This method modifies the release notes to make them look uniform.
     All custom fonts and font sizes are removed for a more unified look. Specific styles like bold or italic parts as well as links are preserved.
     - parameter attributedString: The string to be formatted
     - returns: The formatted string
     */
    private func format(_ attributedString: NSAttributedString) -> NSAttributedString {
        let string = NSMutableAttributedString(attributedString: attributedString)
		string.mutableString.replaceOccurrences(of: "\t", with: " ", options: [], range: NSMakeRange(0, string.length))

        let textRange = NSMakeRange(0, attributedString.length)
        let defaultFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        
        // Fix foreground color
        string.removeAttribute(.foregroundColor, range: textRange)
        string.addAttribute(.foregroundColor, value: NSColor.labelColor, range: textRange)
		
		// Remove background color
		string.removeAttribute(.backgroundColor, range: textRange)
        
		// Remove shadows
		string.removeAttribute(.shadow, range: textRange)
		
        // Reset font
        string.removeAttribute(.font, range: textRange)
        string.addAttribute(.font, value: defaultFont, range: textRange)

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.alignment = .left
		paragraphStyle.firstLineHeadIndent = 0
		paragraphStyle.headIndent = 0
		paragraphStyle.tabStops = []
		string.removeAttribute(.paragraphStyle, range: textRange)
		string.addAttribute(.paragraphStyle, value: paragraphStyle, range: textRange)
        
        // Copy traits like italic and bold
        attributedString.enumerateAttribute(NSAttributedString.Key.font, in: textRange, options: .reverse) { (fontObject, range, stopPointer) in
            guard let font = fontObject as? NSFont else { return }
            
            let traits = font.fontDescriptor.symbolicTraits
            let fontDescriptor = defaultFont.fontDescriptor.withSymbolicTraits(traits)
			if let font = NSFont(descriptor: fontDescriptor, size: defaultFont.pointSize) {
				string.addAttribute(.font, value: font, range: range)
			}
        }
        
        return string
    }
    
}

extension ReleaseNotesTextViewController: ReleaseNotesContentProtocol {
    
    typealias ReleaseNotesContentController = ReleaseNotesTextViewController

	static func makeController() -> ReleaseNotesTextViewController {
		ReleaseNotesTextViewController()
	}
    
}
