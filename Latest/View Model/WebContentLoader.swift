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
	func load(from url: URL, contentUpdateHandler: @escaping @MainActor (Result<String, Error>) -> Void) {
		pendingContentUpdateTask?.cancel()
		loadTimeoutTask?.cancel()
		let loadID = UUID()
		currentLoadID = loadID
		currentUpdateHandler = contentUpdateHandler
		webView.stopLoading()
		currentNavigation = webView.load(URLRequest(url: url))
		scheduleLoadTimeout(for: loadID)
	}

	/// Cancels any active load and suppresses delayed content updates.
	func cancel() {
		pendingContentUpdateTask?.cancel()
		loadTimeoutTask?.cancel()
		currentLoadID = UUID()
		currentNavigation = nil
		currentUpdateHandler = nil
		webView.stopLoading()
	}


	// MARK: - Accessors

	/// The web view actually loading the web contents.
	///
	/// Required for some websites that use scripts to populate the sites contents.
	private lazy var webView: WKWebView = {
		let config = WKWebViewConfiguration()

		// Setup observation script
		let source = """
			if (window.__latestMutationObserver) {
				window.__latestMutationObserver.disconnect();
			}
			window.__latestMutationObserver = new MutationObserver(function(mutations) {
				window.webkit.messageHandlers.updateHandler.postMessage("contentsUpdated");
			});

			window.__latestMutationObserver.observe(document.documentElement || document, { childList: true, subtree: true });
		"""

		let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
		config.userContentController.addUserScript(script)
		config.userContentController.add(self, name: "updateHandler")

		// Setup web view
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.navigationDelegate = self

		// Ensure the web view renders with full performance.
		webView.configuration.preferences.inactiveSchedulingPolicy = .none

		return webView
	}()

	/// The current navigation object.
	private var currentNavigation: WKNavigation?

	/// The identifier for the most recent load.
	private var currentLoadID = UUID()

	/// The current update handler.
	private var currentUpdateHandler: (@MainActor (Result<String, Error>) -> Void)?

	/// Delayed content extraction work used to collapse mutation bursts.
	private var pendingContentUpdateTask: Task<Void, Never>?

	/// Timeout work for dynamic pages that never finish or never settle.
	private var loadTimeoutTask: Task<Void, Never>?


	// MARK: - Utilities

	/// Schedules a content update after the page has had a chance to settle.
	fileprivate func scheduleContentUpdate() {
		let loadID = currentLoadID
		pendingContentUpdateTask?.cancel()
		pendingContentUpdateTask = Task { @MainActor in
			try? await Task.sleep(nanoseconds: 150_000_000)
			guard !Task.isCancelled, loadID == self.currentLoadID else { return }
			self.notifyContentUpdate(for: loadID)
		}
	}

	private func scheduleLoadTimeout(for loadID: UUID) {
		loadTimeoutTask = Task { @MainActor in
			try? await Task.sleep(nanoseconds: 8_000_000_000)
			guard !Task.isCancelled, loadID == self.currentLoadID else { return }

			let handler = self.currentUpdateHandler
			self.cancel()
			handler?(.failure(WebContentLoaderError.timedOut))
		}
	}

	/// Forwards the current page contents to the caller of the load method.
	private func notifyContentUpdate(for loadID: UUID) {
		guard loadID == currentLoadID else { return }

		webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { html, error in
			Task { @MainActor in
				guard loadID == self.currentLoadID else { return }

				if let html = html as? String, !html.isEmpty {
					self.loadTimeoutTask?.cancel()
					self.currentUpdateHandler?(.success(html))
				} else if let error = error {
					self.loadTimeoutTask?.cancel()
					self.currentUpdateHandler?(.failure(error))
				}
			}
		}
	}

}

extension WebContentLoader: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard navigation == currentNavigation else { return }
		scheduleContentUpdate()
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		guard navigation == currentNavigation else { return }
		loadTimeoutTask?.cancel()
		currentUpdateHandler?(.failure(error))
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		guard navigation == currentNavigation else { return }
		loadTimeoutTask?.cancel()
		currentUpdateHandler?(.failure(error))
	}

}

extension WebContentLoader: WKScriptMessageHandler {

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		guard message.name == "updateHandler" else { return }
		scheduleContentUpdate()
	}

}

private enum WebContentLoaderError: Error {
	case timedOut
}
