import XCTest

@testable import Latest

@MainActor
final class SparkleUpdateOperationTest: XCTestCase {
  func testDownloadProgressCoalescesAndUsesLatestByteCounts() async {
    let operation = makeOperation()
    let published = expectation(description: "Latest download totals")
    operation.progressHandler = { [weak operation] _ in
      guard case .downloading(let received, let expected) = operation?.progressState else { return }
      XCTAssertEqual(received, 130)
      XCTAssertEqual(expected, 130)
      published.fulfill()
    }
    operation.showDownloadDidReceiveExpectedContentLength(100)
    operation.showDownloadDidReceiveData(ofLength: 60)
    operation.showDownloadDidReceiveData(ofLength: 70)
    await fulfillment(of: [published], timeout: 1)
    operation.finish()
  }

  func testPendingDownloadProgressCannotReplaceExtractionOrInstallation() async {
    let extracting = makeOperation()
    let installing = makeOperation()
    let staleDownload = expectation(description: "No download progress after phase transition")
    staleDownload.isInverted = true
    for operation in [extracting, installing] {
      operation.progressHandler = { [weak operation] _ in
        if case .downloading = operation?.progressState { staleDownload.fulfill() }
      }
      operation.showDownloadDidReceiveExpectedContentLength(100)
      operation.showDownloadDidReceiveData(ofLength: 100)
    }
    extracting.showDownloadDidStartExtractingUpdate()
    extracting.showExtractionReceivedProgress(0.5)
    installing.showInstallingUpdate(
      withApplicationTerminated: true, retryTerminatingApplication: {})

    await fulfillment(of: [staleDownload], timeout: 0.35)
    if case .extracting(let progress) = extracting.progressState {
      XCTAssertEqual(progress, 0.5)
    } else {
      XCTFail("Extraction must remain visible")
    }
    if case .installing = installing.progressState {
      // Installation must not regress to downloading.
    } else {
      XCTFail("Installation must remain visible")
    }
    extracting.finish()
    installing.finish()
  }

  func testCancellationFinishesAndCallsSparkleOnMainActor() async {
    let operation = makeOperation()
    let cancelled = expectation(description: "Sparkle cancellation callback")
    operation.showDownloadInitiated {
      XCTAssertTrue(Thread.isMainThread)
      cancelled.fulfill()
    }
    operation.showDownloadDidReceiveExpectedContentLength(100)
    await Task.detached { operation.cancel() }.value
    XCTAssertTrue(operation.isCancelled)
    XCTAssertTrue(operation.isFinished)
    await fulfillment(of: [cancelled], timeout: 1)
    if case .none = operation.progressState {
      // Completion clears progress synchronously, before actor cleanup.
    } else {
      XCTFail("Cancelled operation must clear its progress")
    }
  }

  private func makeOperation() -> SparkleUpdateOperation {
    SparkleUpdateOperation(
      bundleIdentifier: "test.sparkle", appIdentifier: URL(fileURLWithPath: "/tmp/Sparkle.app"))
  }
}
