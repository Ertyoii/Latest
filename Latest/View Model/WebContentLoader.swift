//
//  WebContentLoader.swift
//  Latest
//
//  Created by Max Langer on 26.09.23.
//  Copyright © 2023 Max Langer. All rights reserved.
//

import WebKit

/// Object that loads websites for given URLs and returns their content as HTML.
@MainActor
class WebContentLoader: NSObject {
	
	/// Loads contents for the given URL.
	///
	/// The update handler may be called multiple times, if contents change. The caller is responsible for determining whether updates are still relevant.
	@available(*, deprecated, message: "Use `events(for:)` instead")
	func load(from url: URL, contentUpdateHandler: @escaping(Result<String, Error>) -> Void) {
		currentUpdateHandler = contentUpdateHandler
		currentNavigation = webView.load(URLRequest(url: url))
	}

	/// Returns a stream of HTML content updates for the given URL.
	func events(for url: URL) -> AsyncThrowingStream<String, Error> {
		return AsyncThrowingStream { continuation in
			self.currentContinuation = continuation
			self.currentNavigation = webView.load(URLRequest(url: url))
			
			// Handle cleanup when the stream is cancelled
			continuation.onTermination = { @Sendable [weak self] _ in
				Task { @MainActor [weak self] in
					self?.webView.stopLoading()
					self?.currentContinuation = nil
				}
			}
		}
	}


	// MARK: - Accessors
	
	/// The web view actually loading the web contents.
	///
	/// Required for some websites that use scripts to populate the sites contents.
	private lazy var webView: WKWebView = {
		let config = WKWebViewConfiguration()
		
		// Setup observation script
		let source = """
			let observer = new MutationObserver(function(mutations) {
			window.webkit.messageHandlers.updateHandler.postMessage("contentsUpdated");
			});
			
			observer.observe(document, { childList: true, subtree: true	});
		"""
		
		let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
		config.userContentController.addUserScript(script)
		config.userContentController.add(self, name: "updateHandler")
		
		// Setup web view
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.navigationDelegate = self
		
		// Ensure the web view renders with full performance
		webView.configuration.preferences.inactiveSchedulingPolicy = .none
		
		return webView
	}()
	
	/// The current navigation object.
	private var currentNavigation: WKNavigation?
	
	/// The current update handler.
	private var currentUpdateHandler: ((Result<String, Error>) -> Void)?
	
	/// The current async continuation.
	private var currentContinuation: AsyncThrowingStream<String, Error>.Continuation?
	
	/// The current update task to debounce events.
	private var currentUpdateTask: Task<Void, Error>?

	
	// MARK: - Utilities
	
	/// Forwards the current page contents to the caller of the load method.
	fileprivate func notifyContentUpdate() {
		currentUpdateTask?.cancel()
		
		currentUpdateTask = Task { @MainActor [weak self] in
			// Debounce updates to avoid flooding the main thread
			try await Task.sleep(nanoseconds: 200 * 1_000_000)
			
			self?.webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { html, error in
				// WebKit callbacks are already on the main thread, but explicit MainActor context is safe.
				if let html = html as? String, !html.isEmpty {
					self?.currentUpdateHandler?(.success(html))
					self?.currentContinuation?.yield(html)
				} else if let error = error {
					self?.currentUpdateHandler?(.failure(error))
					self?.currentContinuation?.finish(throwing: error)
				}
			}
		}
	}
	
}

extension WebContentLoader: WKNavigationDelegate {
	
	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard navigation == currentNavigation else { return }
		notifyContentUpdate()
	}
	
}

extension WebContentLoader: WKScriptMessageHandler {
	
	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		guard message.name == "updateHandler" else { return }
		notifyContentUpdate()
	}
	
}
