//
//  MigrationVisualRegressionTest.swift
//  Latest Tests
//
//  Created by Codex on 19.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import SwiftUI
import XCTest
@testable import Latest

final class MigrationVisualRegressionTest: XCTestCase {
	@MainActor
	func testMigrationGalleryGeometryContracts() {
		let defaultSize = MigrationGalleryMetrics.defaultWindowSize
		let sidebar = MigrationGalleryMetrics.sidebarFrame(in: defaultSize)
		let detail = MigrationGalleryMetrics.detailFrame(in: defaultSize)

		XCTAssertEqual(defaultSize, CGSize(width: 768, height: 516))
		XCTAssertEqual(sidebar.width, VisualMetrics.sidebarIdealWidth)
		XCTAssertEqual(sidebar.height, defaultSize.height)
		XCTAssertEqual(detail.minX, sidebar.maxX)
		XCTAssertEqual(detail.maxX, defaultSize.width)
		XCTAssertEqual(MigrationGalleryMetrics.detailHeaderHeight, VisualMetrics.detailHeaderHeight)
		XCTAssertEqual(MigrationGalleryMetrics.appRowHeight, VisualMetrics.appRowHeight)
		XCTAssertEqual(MigrationGalleryMetrics.locationsContentSize, CGSize(width: 440, height: 296))
		XCTAssertEqual(MigrationGalleryMetrics.locationsTableSize, CGSize(width: 400, height: 200))
		XCTAssertEqual(MigrationGalleryMetrics.sidebarFixtureSize.width, VisualMetrics.sidebarIdealWidth)
	}

	@MainActor
	func testMigrationGalleryRenderedRegions() throws {
		guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 else {
			throw XCTSkip("Visual baselines are scoped to the macOS 26 renderer.")
		}

		for scenario in MigrationGalleryScenario.regressionCases {
			try XCTContext.runActivity(named: scenario.id) { _ in
				let rendered = try MigrationGalleryRenderer.render(scenario)
				try MigrationGalleryRenderer.assertMatchesBaseline(rendered, scenario: scenario, testCase: self)
			}
		}
	}
}

@MainActor
private enum MigrationGalleryRenderer {
	private static let recordBaselines = ProcessInfo.processInfo.environment["LATEST_RECORD_VISUAL_BASELINES"] == "1"
		|| FileManager.default.fileExists(atPath: "/tmp/latest-record-visual-baselines")
	private static let baselineDirectory = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.appendingPathComponent("VisualBaselines", isDirectory: true)
		.appendingPathComponent("macos-26", isDirectory: true)

	static func render(_ scenario: MigrationGalleryScenario) throws -> NSBitmapImageRep {
		let rootView = MigrationGalleryView(scenario: scenario)
		let hostingView = NSHostingView(rootView: rootView)
		hostingView.frame = CGRect(origin: .zero, size: scenario.size)

		let window = NSWindow(
			contentRect: CGRect(origin: .zero, size: scenario.size),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(
			named: scenario.colorScheme == .dark ? .darkAqua : .aqua
		)
		window.contentView = hostingView
		window.layoutIfNeeded()
		hostingView.layoutSubtreeIfNeeded()
		if case .sidebar(.legacyTable) = scenario.surface,
		   let tableView = hostingView.descendant(of: NSTableView.self) {
			for row in 0..<tableView.numberOfRows {
				_ = tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
			}
			tableView.layoutSubtreeIfNeeded()
		}

		let settleDuration: TimeInterval
		if case .sidebar = scenario.surface {
			settleDuration = 0.2
		} else {
			settleDuration = 0.05
		}
		RunLoop.main.run(until: Date(timeIntervalSinceNow: settleDuration))
		window.layoutIfNeeded()
		hostingView.layoutSubtreeIfNeeded()

		guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
			throw VisualRegressionError.couldNotCreateBitmap
		}
		hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
		return bitmap
	}

	static func assertMatchesBaseline(
		_ rendered: NSBitmapImageRep,
		scenario: MigrationGalleryScenario,
		testCase: XCTestCase
	) throws {
		let baselineURL = baselineDirectory.appendingPathComponent("\(scenario.id).png")
		guard let png = rendered.representation(using: .png, properties: [:]) else {
			throw VisualRegressionError.couldNotEncodePNG
		}

		if recordBaselines {
			try FileManager.default.createDirectory(
				at: baselineDirectory,
				withIntermediateDirectories: true
			)
			try png.write(to: baselineURL, options: .atomic)
			return
		}

		guard let baselineData = try? Data(contentsOf: baselineURL),
			  let baseline = NSBitmapImageRep(data: baselineData) else {
			XCTFail(
				"Missing visual baseline \(baselineURL.path). Record with LATEST_RECORD_VISUAL_BASELINES=1 ./script/test.sh"
			)
			return
		}

		let comparison = try compare(
			baseline: baseline,
			actual: rendered,
			regions: comparisonRegions(for: scenario)
		)

		guard !comparison.passed else { return }
		let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
		attachment.name = "\(scenario.id)-actual"
		attachment.lifetime = .keepAlways
		testCase.add(attachment)
		XCTFail(
			String(
				format: "Visual regression in %@: %.3f%% pixels exceeded tolerance, RMS %.3f (limits %.3f%% / %.3f)",
				scenario.id,
				comparison.changedFraction * 100,
				comparison.rms,
				comparison.changedFractionLimit * 100,
				comparison.rmsLimit
			)
		)
	}

	private static func comparisonRegions(for scenario: MigrationGalleryScenario) -> [CGRect] {
		let insetBounds = CGRect(origin: .zero, size: scenario.size).insetBy(dx: 2, dy: 2)
		switch scenario.surface {
		case .main:
			let sidebar = MigrationGalleryMetrics.sidebarFrame(in: scenario.size).insetBy(dx: 2, dy: 2)
			let detail = MigrationGalleryMetrics.detailFrame(in: scenario.size)
			let header = CGRect(
				x: detail.minX + 2,
				y: detail.maxY - MigrationGalleryMetrics.detailHeaderHeight,
				width: max(0, detail.width - 4),
				height: MigrationGalleryMetrics.detailHeaderHeight
			)
			let body = CGRect(
				x: detail.minX + 2,
				y: 2,
				width: max(0, detail.width - 4),
				height: max(0, detail.height - MigrationGalleryMetrics.detailHeaderHeight - 4)
			)
			return [sidebar, header, body]
		case .locations, .updateStateShelf, .toolbarStateShelf, .sidebar:
			return [insetBounds]
		}
	}

	private static func compare(
		baseline: NSBitmapImageRep,
		actual: NSBitmapImageRep,
		regions: [CGRect]
	) throws -> VisualComparison {
		guard baseline.pixelsWide == actual.pixelsWide,
			  baseline.pixelsHigh == actual.pixelsHigh else {
			throw VisualRegressionError.dimensionMismatch(
				expected: CGSize(width: baseline.pixelsWide, height: baseline.pixelsHigh),
				actual: CGSize(width: actual.pixelsWide, height: actual.pixelsHigh)
			)
		}

		let expected = try rgbaBytes(from: baseline)
		let observed = try rgbaBytes(from: actual)
		let scaleX = CGFloat(actual.pixelsWide) / actual.size.width
		let scaleY = CGFloat(actual.pixelsHigh) / actual.size.height
		let channelTolerance = 12
		var comparedPixels = 0
		var changedPixels = 0
		var squaredError = 0.0

		for region in regions {
			let pixelRegion = CGRect(
				x: region.minX * scaleX,
				y: region.minY * scaleY,
				width: region.width * scaleX,
				height: region.height * scaleY
			).integral
			let minX = max(0, Int(pixelRegion.minX))
			let maxX = min(actual.pixelsWide, Int(pixelRegion.maxX))
			let minY = max(0, Int(pixelRegion.minY))
			let maxY = min(actual.pixelsHigh, Int(pixelRegion.maxY))

			for y in minY..<maxY {
				for x in minX..<maxX {
					let offset = ((y * actual.pixelsWide) + x) * 4
					var pixelChanged = false
					for channel in 0..<3 {
						let delta = abs(Int(expected[offset + channel]) - Int(observed[offset + channel]))
						pixelChanged = pixelChanged || delta > channelTolerance
						squaredError += Double(delta * delta)
					}
					comparedPixels += 1
					if pixelChanged {
						changedPixels += 1
					}
				}
			}
		}

		let changedFraction = comparedPixels == 0 ? 0 : Double(changedPixels) / Double(comparedPixels)
		let rms = comparedPixels == 0 ? 0 : sqrt(squaredError / Double(comparedPixels * 3))
		let changedFractionLimit = 0.0125
		let rmsLimit = 3.5
		return VisualComparison(
			passed: changedFraction <= changedFractionLimit && rms <= rmsLimit,
			changedFraction: changedFraction,
			rms: rms,
			changedFractionLimit: changedFractionLimit,
			rmsLimit: rmsLimit
		)
	}

	private static func rgbaBytes(from bitmap: NSBitmapImageRep) throws -> [UInt8] {
		guard let image = bitmap.cgImage else {
			throw VisualRegressionError.couldNotReadPixels
		}
		let width = bitmap.pixelsWide
		let height = bitmap.pixelsHigh
		var bytes = [UInt8](repeating: 0, count: width * height * 4)
		guard let context = CGContext(
			data: &bytes,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else {
			throw VisualRegressionError.couldNotReadPixels
		}
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
		return bytes
	}
}

private extension NSView {
	func descendant<ViewType: NSView>(of type: ViewType.Type) -> ViewType? {
		if let match = self as? ViewType { return match }
		return subviews.lazy.compactMap { $0.descendant(of: type) }.first
	}
}

private struct VisualComparison {
	let passed: Bool
	let changedFraction: Double
	let rms: Double
	let changedFractionLimit: Double
	let rmsLimit: Double
}

private enum VisualRegressionError: LocalizedError {
	case couldNotCreateBitmap
	case couldNotEncodePNG
	case couldNotReadPixels
	case dimensionMismatch(expected: CGSize, actual: CGSize)

	var errorDescription: String? {
		switch self {
		case .couldNotCreateBitmap:
			"Could not create a bitmap for the migration gallery."
		case .couldNotEncodePNG:
			"Could not encode the migration gallery as PNG."
		case .couldNotReadPixels:
			"Could not normalize migration gallery pixels to RGBA."
		case .dimensionMismatch(let expected, let actual):
			"Visual dimensions differ: expected \(expected), actual \(actual)."
		}
	}
}
