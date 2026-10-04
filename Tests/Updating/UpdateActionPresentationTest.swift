// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import XCTest

@testable import Latest

final class UpdateActionPresentationTest: XCTestCase {
  @MainActor
  func testUpdateActionPresentationCoversEveryOperationState() {
    let updatable = makeTestApp(name: "Discord", version: "1", remoteVersion: "2")
    let installed = makeTestApp(name: "Cursor", version: "3")

    XCTAssertEqual(UpdateActionPresentation.make(for: updatable, progressState: .none), .update)
    XCTAssertEqual(UpdateActionPresentation.make(for: installed, progressState: .none), .open)
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .pending))
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .initializing))
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .installing))
    XCTAssertEqual(
      UpdateActionPresentation.make(for: updatable, progressState: .waitingForQuit),
      .retryTermination)
    assertWaiting(UpdateActionPresentation.make(for: updatable, progressState: .cancelling))

    guard
      case .progress(let downloadFraction, let downloadStatus, let downloadCancellable) =
        UpdateActionPresentation.make(
          for: updatable,
          progressState: .downloading(loadedSize: 25, totalSize: 100)
        )
    else {
      return XCTFail("Expected the download state to produce determinate progress.")
    }
    XCTAssertEqual(downloadFraction, 0.1875, accuracy: 0.0001)
    XCTAssertFalse(downloadStatus.isEmpty)
    XCTAssertTrue(downloadCancellable)

    guard
      case .progress(let extractionFraction, let extractionStatus, let extractionCancellable) =
        UpdateActionPresentation.make(
          for: updatable,
          progressState: .extracting(progress: 0.5)
        )
    else {
      return XCTFail("Expected the extraction state to produce determinate progress.")
    }
    XCTAssertEqual(extractionFraction, 0.875, accuracy: 0.0001)
    XCTAssertFalse(extractionStatus.isEmpty)
    XCTAssertTrue(extractionCancellable)
    XCTAssertEqual(
      UpdateActionPresentation.make(
        for: updatable, progressState: .extracting(progress: 0.5, cancellable: false)),
      .progress(fraction: extractionFraction, status: extractionStatus, cancellable: false))

    let error = NSError(
      domain: "LatestTests", code: 7,
      userInfo: [
        NSLocalizedDescriptionKey: "The update failed"
      ])
    XCTAssertEqual(
      UpdateActionPresentation.make(for: updatable, progressState: .error(error)),
      .failed("The update failed")
    )
  }

  private func assertWaiting(
    _ presentation: UpdateActionPresentation,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard case .waiting(let status) = presentation else {
      return XCTFail("Expected a waiting presentation.", file: file, line: line)
    }
    XCTAssertFalse(status.isEmpty, file: file, line: line)
  }
}
