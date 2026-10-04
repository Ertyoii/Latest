// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import SwiftUI
import XCTest

@testable import Latest

final class SidebarAppearanceTest: XCTestCase {
  @MainActor
  func testSidebarShowsLongInstalledVersionWithoutTruncationAtIdealWidth() async throws {
    try requireUITests()
    let app = makeTestApp(name: "Chrome", version: "151.0.7922.109")
    let expectedVersion = try XCTUnwrap(app.localizedVersionInformation?.current)
    let fixture = try await SidebarInputFixture.make(apps: [app], testCase: self)
    defer { fixture.window.close() }
    let bitmap = try await fixture.captureRow(for: app)
    let referenceBitmap = try nativeVersionReference(expectedVersion)
    var missingGlyphPixels = 0
    var glyphPixels = 0
    let backing = try XCTUnwrap(bitmap.colorAt(x: 600, y: 0)?.usingColorSpace(.deviceRGB))
      .redComponent
    for y in 62..<90 {
      for x in 116..<540 {
        let reference = try XCTUnwrap(
          referenceBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        guard reference.alphaComponent > 0.15 else { continue }
        glyphPixels += 1
        // Text and NSTextField may snap coverage to adjacent pixels. Require
        // every native glyph pixel to have matching ink within one pixel.
        var foundInk = false
        for dy in -1...1 {
          for dx in -1...1 {
            let actual = try XCTUnwrap(
              bitmap.colorAt(x: x + dx, y: y + dy)?.usingColorSpace(.deviceRGB))
            if backing - actual.redComponent > 0.08 { foundInk = true }
          }
        }
        if !foundInk { missingGlyphPixels += 1 }
      }
    }
    XCTAssertGreaterThan(
      glyphPixels, 100, "Native text reference must contain the complete version")
    XCTAssertEqual(
      missingGlyphPixels, 0,
      "The installed version must paint every glyph in the complete native reference")
  }

  @MainActor
  func testSidebarTextColorsFollowSelectionEmphasis() throws {
    try requireUITests()
    try runApplicationTest { try await self.checkSidebarTextColorsFollowSelectionEmphasis() }
  }

  @MainActor
  private func checkSidebarTextColorsFollowSelectionEmphasis() async throws {
    let app = makeTestApp(name: "Discord", version: "0.0.398", remoteVersion: "0.0.399")
    let search = SearchFocusController()
    let fixture = try await SidebarInputFixture.make(
      apps: [app], selected: app, searchFocusController: search, testCase: self)
    defer { fixture.window.close() }
    try await fixture.activate()
    try fixture.click(row: XCTUnwrap(fixture.model.snapshot.firstIndex(of: app)))
    for emphasized in [true, false] {
      if !emphasized {
        // Transfer actual focus within the same production scene. Calling
        // resignKey on a newly opened window did not establish this state.
        search.focus()
        let deadline = ContinuousClock.now + .seconds(1)
        while !(fixture.window.firstResponder is NSTextView) && ContinuousClock.now < deadline {
          try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(fixture.window.firstResponder is NSTextView, "Search must own keyboard focus")
      }
      try await Task.sleep(for: .milliseconds(100))
      let bitmap = try await fixture.captureRow(for: app)
      var expectedGlyphPixels = 0
      let backing = try XCTUnwrap(bitmap.colorAt(x: 440, y: 104)?.usingColorSpace(.sRGB))
      for y in 18..<46 {
        for x in 116..<220 {
          let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
          // The real system label is not absolute black. Check its contrast
          // with the selection fill in one color space, not device-RGB values.
          let contrast =
            emphasized
            ? color.redComponent - backing.redComponent
            : backing.redComponent - color.redComponent
          if contrast > 0.4 {
            expectedGlyphPixels += 1
          }
        }
      }
      if expectedGlyphPixels <= 50 {
        let attachment = XCTAttachment(
          image: NSImage(cgImage: try XCTUnwrap(bitmap.cgImage), size: bitmap.size))
        attachment.name = "production-row-emphasis-\(emphasized)"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
      XCTAssertGreaterThan(
        expectedGlyphPixels, 50, "Incorrect title color with emphasis=\(emphasized)")
    }
  }

  @MainActor
  private func nativeVersionReference(_ version: String) throws -> NSBitmapImageRep {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 308, height: 60))
    host.appearance = NSAppearance(named: .aqua)
    let reference = NSTextField(labelWithString: version)
    reference.font = NSFont.systemFont(ofSize: 11)
    reference.textColor = .secondaryLabelColor
    // NSTextField has 2pt of leading padding relative to the production Text.
    reference.frame = NSRect(x: 56, y: 15, width: 216, height: 14)
    host.addSubview(reference)
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 616, pixelsHigh: 120,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.frame.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return bitmap
  }
}
