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
		let loadID = UUID()
		currentLoadID = loadID
		currentUpdateHandler = contentUpdateHandler
		webView.stopLoading()
		currentNavigation = webView.load(URLRequest(url: url))
	}

	/// Cancels any active load and suppresses delayed content updates.
	func cancel() {
		pendingContentUpdateTask?.cancel()
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

	/// Forwards the current page contents to the caller of the load method.
	private func notifyContentUpdate(for loadID: UUID) {
		guard loadID == currentLoadID else { return }

		webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { html, error in
			Task { @MainActor in
				guard loadID == self.currentLoadID else { return }

				if let html = html as? String, !html.isEmpty {
					self.currentUpdateHandler?(.success(html))
				} else if let error = error {
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

}

extension WebContentLoader: WKScriptMessageHandler {

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		guard message.name == "updateHandler" else { return }
		scheduleContentUpdate()
	}

}
