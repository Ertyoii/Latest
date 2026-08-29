#!/usr/bin/env swift

import AppKit
import Foundation

private struct Comparison {
	let pixelCount: Int
	let exactChangedPixels: Int
	let toleranceChangedPixels: Int
	let rms: Double
	let maxChannelDelta: Int
}

private enum ParityError: Error, CustomStringConvertible {
	case invalidArguments
	case noImages(URL)
	case missingActual(URL)
	case unreadableImage(URL)
	case dimensionMismatch(String, CGSize, CGSize)
	case couldNotCreateContext(URL)

	var description: String {
		switch self {
		case .invalidArguments:
			"usage: report_visual_parity.swift BASELINE_DIRECTORY ACTUAL_DIRECTORY"
		case .noImages(let directory):
			"No PNG references found in \(directory.path)"
		case .missingActual(let url):
			"Missing rendered image \(url.path)"
		case .unreadableImage(let url):
			"Could not decode \(url.path)"
		case .dimensionMismatch(let name, let expected, let actual):
			"\(name) dimensions differ: expected \(expected), actual \(actual)"
		case .couldNotCreateContext(let url):
			"Could not create RGBA context for \(url.path)"
		}
	}
}

private func rgbaBytes(from url: URL) throws -> (bytes: [UInt8], size: CGSize) {
	guard let data = try? Data(contentsOf: url),
		  let bitmap = NSBitmapImageRep(data: data),
		  let image = bitmap.cgImage else {
		throw ParityError.unreadableImage(url)
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
		throw ParityError.couldNotCreateContext(url)
	}
	context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
	return (bytes, CGSize(width: width, height: height))
}

private func compare(reference: URL, actual: URL) throws -> Comparison {
	let expected = try rgbaBytes(from: reference)
	let observed = try rgbaBytes(from: actual)
	guard expected.size == observed.size else {
		throw ParityError.dimensionMismatch(
			reference.lastPathComponent,
			expected.size,
			observed.size
		)
	}

	let pixelCount = Int(expected.size.width * expected.size.height)
	let channelTolerance = 12
	var exactChangedPixels = 0
	var toleranceChangedPixels = 0
	var squaredError = 0.0
	var maxChannelDelta = 0

	for pixel in 0..<pixelCount {
		let offset = pixel * 4
		var exactChanged = false
		var toleranceChanged = false
		for channel in 0..<4 {
			let delta = abs(Int(expected.bytes[offset + channel]) - Int(observed.bytes[offset + channel]))
			exactChanged = exactChanged || delta > 0
			maxChannelDelta = max(maxChannelDelta, delta)
			if channel < 3 {
				toleranceChanged = toleranceChanged || delta > channelTolerance
				squaredError += Double(delta * delta)
			}
		}
		if exactChanged { exactChangedPixels += 1 }
		if toleranceChanged { toleranceChangedPixels += 1 }
	}

	let rms = pixelCount == 0 ? 0 : sqrt(squaredError / Double(pixelCount * 3))
	return Comparison(
		pixelCount: pixelCount,
		exactChangedPixels: exactChangedPixels,
		toleranceChangedPixels: toleranceChangedPixels,
		rms: rms,
		maxChannelDelta: maxChannelDelta
	)
}

do {
	guard CommandLine.arguments.count == 3 else { throw ParityError.invalidArguments }
	let referenceDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
	let actualDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
	let references = try FileManager.default.contentsOfDirectory(
		at: referenceDirectory,
		includingPropertiesForKeys: nil
	)
		.filter { $0.pathExtension.lowercased() == "png" }
		.sorted { $0.lastPathComponent < $1.lastPathComponent }
	guard !references.isEmpty else { throw ParityError.noImages(referenceDirectory) }

	var comparedImages = 0
	var exactImages = 0
	for reference in references {
		let actual = actualDirectory.appendingPathComponent(reference.lastPathComponent)
		guard FileManager.default.fileExists(atPath: actual.path) else { continue }
		let result = try compare(reference: reference, actual: actual)
		let exactPercent = Double(result.exactChangedPixels) / Double(result.pixelCount) * 100
		let tolerancePercent = Double(result.toleranceChangedPixels) / Double(result.pixelCount) * 100
		print(String(
			format: "%@ exact=%d/%d (%.6f%%) tolerance=%.6f%% rms=%.6f max-channel-delta=%d",
			reference.lastPathComponent,
			result.exactChangedPixels,
			result.pixelCount,
			exactPercent,
			tolerancePercent,
			result.rms,
			result.maxChannelDelta
		))
		comparedImages += 1
		if result.exactChangedPixels == 0 { exactImages += 1 }
	}

	guard comparedImages > 0 else { throw ParityError.noImages(actualDirectory) }
	print("Compared \(comparedImages) image pairs; \(exactImages) were byte-for-byte pixel identical after RGBA decoding.")
} catch {
	FileHandle.standardError.write(Data("\(error)\n".utf8))
	exit(1)
}
