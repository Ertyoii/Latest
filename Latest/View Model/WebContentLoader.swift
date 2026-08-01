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
		let webView = activeWebView
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
		guard let webView else { return }
		webView.stopLoading()
		webView.evaluateJavaScript("window.__latestMutationObserver?.disconnect(); clearTimeout(window.__latestMutationTimer);")
		webView.navigationDelegate = nil
		webView.configuration.userContentController.removeScriptMessageHandler(forName: "updateHandler")
		self.webView = nil
	}


	// MARK: - Accessors

	/// The web view actually loading the web contents.
	///
	/// Required for some websites that use scripts to populate the sites contents.
	private var webView: WKWebView?

	private var activeWebView: WKWebView {
		if let webView {
			return webView
		}

		let config = WKWebViewConfiguration()
		config.websiteDataStore = .nonPersistent()

		// Setup observation script
		let source = """
			if (window.__latestMutationObserver) {
				window.__latestMutationObserver.disconnect();
			}
			window.__latestScheduleUpdate = function() {
				clearTimeout(window.__latestMutationTimer);
				window.__latestMutationTimer = setTimeout(function() {
					window.webkit.messageHandlers.updateHandler.postMessage("contentsUpdated");
				}, 120);
			};
			window.__latestMutationObserver = new MutationObserver(function() {
				window.__latestScheduleUpdate();
			});

			window.__latestMutationObserver.observe(document.documentElement || document, { childList: true, subtree: true });
			window.__latestScheduleUpdate();
			"""

		let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
		config.userContentController.addUserScript(script)
		config.userContentController.add(self, name: "updateHandler")

		// Setup web view
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.navigationDelegate = self

		self.webView = webView
		return webView
	}

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
		guard loadID == currentLoadID, let webView else { return }

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
