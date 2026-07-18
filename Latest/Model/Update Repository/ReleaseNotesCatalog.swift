//
//  ReleaseNotesCatalog.swift
//  Latest
//
//  Created by Codex on 18.07.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import CryptoKit
import Foundation

struct ReleaseNotesSourceDefinition: Codable, Equatable, Sendable {
	enum Kind: String, Codable, Sendable {
		case changelog
		case github
		case none
	}

	enum VersionPrefix: String, Codable, Sendable {
		case exact
		case majorMinor
		case none
	}

	enum Capability: String, Codable, CaseIterable, Sendable {
		case bundledFallback
		case changelogHTML
		case disabled
		case exactVersion
		case githubReleaseAPI
		case latestSectionFallback
		case majorMinorVersion
	}

	let keys: [String]
	let homebrewTokens: [String]
	let kind: Kind
	let urlTemplate: String?
	let versionPrefix: VersionPrefix?
	let knownFallbackKey: String?
	let allowsLatestFallback: Bool?
	let capabilities: Set<Capability>

	private enum CodingKeys: String, CodingKey {
		case keys
		case homebrewTokens
		case kind
		case urlTemplate
		case versionPrefix
		case knownFallbackKey
		case allowsLatestFallback
		case capabilities
	}

	init(
		keys: [String],
		homebrewTokens: [String],
		kind: Kind,
		urlTemplate: String?,
		versionPrefix: VersionPrefix?,
		knownFallbackKey: String?,
		allowsLatestFallback: Bool?,
		capabilities: Set<Capability>? = nil
	) {
		self.keys = keys
		self.homebrewTokens = homebrewTokens
		self.kind = kind
		self.urlTemplate = urlTemplate
		self.versionPrefix = versionPrefix
		self.knownFallbackKey = knownFallbackKey
		self.allowsLatestFallback = allowsLatestFallback
		self.capabilities = capabilities ?? Self.legacyCapabilities(
			kind: kind,
			versionPrefix: versionPrefix,
			knownFallbackKey: knownFallbackKey,
			allowsLatestFallback: allowsLatestFallback
		)
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		keys = try container.decodeIfPresent([String].self, forKey: .keys) ?? []
		homebrewTokens = try container.decodeIfPresent([String].self, forKey: .homebrewTokens) ?? []
		kind = try container.decode(Kind.self, forKey: .kind)
		urlTemplate = try container.decodeIfPresent(String.self, forKey: .urlTemplate)
		versionPrefix = try container.decodeIfPresent(VersionPrefix.self, forKey: .versionPrefix)
		knownFallbackKey = try container.decodeIfPresent(String.self, forKey: .knownFallbackKey)
		allowsLatestFallback = try container.decodeIfPresent(Bool.self, forKey: .allowsLatestFallback)
		capabilities = try container.decodeIfPresent(Set<Capability>.self, forKey: .capabilities) ??
			Self.legacyCapabilities(
				kind: kind,
				versionPrefix: versionPrefix,
				knownFallbackKey: knownFallbackKey,
				allowsLatestFallback: allowsLatestFallback
			)
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(keys, forKey: .keys)
		try container.encode(homebrewTokens, forKey: .homebrewTokens)
		try container.encode(kind, forKey: .kind)
		try container.encodeIfPresent(urlTemplate, forKey: .urlTemplate)
		try container.encodeIfPresent(versionPrefix, forKey: .versionPrefix)
		try container.encodeIfPresent(knownFallbackKey, forKey: .knownFallbackKey)
		try container.encodeIfPresent(allowsLatestFallback, forKey: .allowsLatestFallback)
		try container.encode(capabilities.sorted { $0.rawValue < $1.rawValue }, forKey: .capabilities)
	}

	private static func legacyCapabilities(
		kind: Kind,
		versionPrefix: VersionPrefix?,
		knownFallbackKey: String?,
		allowsLatestFallback: Bool?
	) -> Set<Capability> {
		var result = Set<Capability>()
		switch kind {
		case .changelog:
			result.insert(.changelogHTML)
		case .github:
			result.insert(.githubReleaseAPI)
		case .none:
			result.insert(.disabled)
		}

		switch versionPrefix ?? .none {
		case .exact:
			result.insert(.exactVersion)
		case .majorMinor:
			result.insert(.majorMinorVersion)
		case .none:
			break
		}
		if knownFallbackKey != nil {
			result.insert(.bundledFallback)
		}
		if allowsLatestFallback == true {
			result.insert(.latestSectionFallback)
		}
		return result
	}
}

struct ReleaseNotesCatalogDocument: Codable, Equatable, Sendable {
	static let supportedSchemaVersion = 1

	let schemaVersion: Int
	let definitions: [ReleaseNotesSourceDefinition]
}

enum ReleaseNotesCatalogValidationError: Error, Equatable {
	case duplicateKey(String)
	case empty
	case invalidCapabilityCombination
	case invalidKey
	case invalidSchemaVersion(Int)
	case invalidURLTemplate
	case tooManyDefinitions
}

enum ReleaseNotesCatalogCodec {
	static let maximumDefinitionCount = 2_048

	static func decodeBundled(_ data: Data) throws -> ReleaseNotesCatalogDocument {
		let decoder = JSONDecoder()
		let document: ReleaseNotesCatalogDocument
		if let decodedDocument = try? decoder.decode(ReleaseNotesCatalogDocument.self, from: data) {
			document = decodedDocument
		} else {
			let definitions = try decoder.decode([ReleaseNotesSourceDefinition].self, from: data)
			document = ReleaseNotesCatalogDocument(
				schemaVersion: ReleaseNotesCatalogDocument.supportedSchemaVersion,
				definitions: definitions
			)
		}
		try validate(document)
		return document
	}

	static func decodeRemotePayload(_ data: Data) throws -> ReleaseNotesCatalogDocument {
		let document = try JSONDecoder().decode(ReleaseNotesCatalogDocument.self, from: data)
		try validate(document)
		return document
	}

	static func validate(_ document: ReleaseNotesCatalogDocument) throws {
		guard document.schemaVersion == ReleaseNotesCatalogDocument.supportedSchemaVersion else {
			throw ReleaseNotesCatalogValidationError.invalidSchemaVersion(document.schemaVersion)
		}
		guard !document.definitions.isEmpty else {
			throw ReleaseNotesCatalogValidationError.empty
		}
		guard document.definitions.count <= maximumDefinitionCount else {
			throw ReleaseNotesCatalogValidationError.tooManyDefinitions
		}

		var definitionIndexByKey = [String: Int]()
		for (index, definition) in document.definitions.enumerated() {
			let sourceKeys = Set((definition.keys + definition.homebrewTokens).map(normalizedKey))
			guard !sourceKeys.isEmpty, !sourceKeys.contains("") else {
				throw ReleaseNotesCatalogValidationError.invalidKey
			}
			for key in sourceKeys {
				if let owner = definitionIndexByKey[key], owner != index {
					throw ReleaseNotesCatalogValidationError.duplicateKey(key)
				}
				definitionIndexByKey[key] = index
			}

			let contentCapabilities: Set<ReleaseNotesSourceDefinition.Capability> = [
				.changelogHTML, .githubReleaseAPI, .disabled
			]
			guard definition.capabilities.intersection(contentCapabilities).count == 1 else {
				throw ReleaseNotesCatalogValidationError.invalidCapabilityCombination
			}
			if definition.capabilities.contains(.disabled) {
				guard definition.urlTemplate == nil else {
					throw ReleaseNotesCatalogValidationError.invalidCapabilityCombination
				}
			} else {
				guard let template = definition.urlTemplate,
				      isSafeURLTemplate(template) else {
					throw ReleaseNotesCatalogValidationError.invalidURLTemplate
				}
			}
			guard !(definition.capabilities.contains(.exactVersion) &&
				definition.capabilities.contains(.majorMinorVersion)) else {
				throw ReleaseNotesCatalogValidationError.invalidCapabilityCombination
			}
		}
	}

	private static func normalizedKey(_ value: String) -> String {
		value.lowercased().filter { $0.isLetter || $0.isNumber }
	}

	private static func isSafeURLTemplate(_ template: String) -> Bool {
		guard template.count <= 2_048,
		      template.lowercased().hasPrefix("https://") else {
			return false
		}
		let expanded = template
			.replacingOccurrences(of: "{version}", with: "1.2.3")
			.replacingOccurrences(of: "{version-dashes}", with: "1-2-3")
			.replacingOccurrences(of: "{major-minor}", with: "1.2")
			.replacingOccurrences(of: "{major-minor-dashes}", with: "1-2")
			.replacingOccurrences(of: "{major-minor-underscores}", with: "1_2")
		guard let components = URLComponents(string: expanded),
		      components.scheme?.lowercased() == "https",
		      components.host != nil,
		      components.user == nil,
		      components.password == nil else {
			return false
		}
		return true
	}
}

struct SignedReleaseNotesCatalogEnvelope: Codable, Equatable, Sendable {
	static let supportedSchemaVersion = 1

	let schemaVersion: Int
	let payload: Data
	let signature: Data
}

protocol ReleaseNotesCatalogHTTPDataLoading: Sendable {
	func load(_ request: URLRequest) async throws -> ReleaseNotesFetchResponse
}

struct URLSessionReleaseNotesCatalogDataLoader: ReleaseNotesCatalogHTTPDataLoading {
	let session: URLSession

	init(session: URLSession = .shared) {
		self.session = session
	}

	func load(_ request: URLRequest) async throws -> ReleaseNotesFetchResponse {
		let (data, response) = try await session.data(for: request)
		return ReleaseNotesFetchResponse(data: data, response: response)
	}
}

enum ReleaseNotesCatalogRemoteRejection: Error, Equatable, Sendable {
	case disabled
	case http
	case invalidCatalog
	case invalidConfiguration
	case invalidEnvelopeSchema
	case invalidSignature
	case network
	case oversized
}

enum ReleaseNotesCatalogOrigin: Equatable, Sendable {
	case remote
	case bundledFallback(ReleaseNotesCatalogRemoteRejection)
}

struct LoadedReleaseNotesCatalog: Equatable, Sendable {
	let document: ReleaseNotesCatalogDocument
	let origin: ReleaseNotesCatalogOrigin
}

struct SignedReleaseNotesCatalogClient: Sendable {
	struct Configuration: Sendable {
		let isEnabled: Bool
		let remoteURL: URL?
		let publicKey: Data?
		let maximumEnvelopeSize: Int

		static let disabled = Configuration(
			isEnabled: false,
			remoteURL: nil,
			publicKey: nil,
			maximumEnvelopeSize: 1 * 1_024 * 1_024
		)
	}

	private let configuration: Configuration
	private let bundledCatalogData: Data
	private let loader: any ReleaseNotesCatalogHTTPDataLoading

	init(
		configuration: Configuration,
		bundledCatalogData: Data,
		loader: any ReleaseNotesCatalogHTTPDataLoading = URLSessionReleaseNotesCatalogDataLoader()
	) {
		self.configuration = configuration
		self.bundledCatalogData = bundledCatalogData
		self.loader = loader
	}

	func load() async throws -> LoadedReleaseNotesCatalog {
		let fallback = try ReleaseNotesCatalogCodec.decodeBundled(bundledCatalogData)
		guard configuration.isEnabled else {
			return LoadedReleaseNotesCatalog(document: fallback, origin: .bundledFallback(.disabled))
		}

		do {
			let remote = try await loadRemote()
			return LoadedReleaseNotesCatalog(document: remote, origin: .remote)
		} catch let rejection as ReleaseNotesCatalogRemoteRejection {
			return LoadedReleaseNotesCatalog(document: fallback, origin: .bundledFallback(rejection))
		} catch {
			return LoadedReleaseNotesCatalog(document: fallback, origin: .bundledFallback(.network))
		}
	}

	private func loadRemote() async throws -> ReleaseNotesCatalogDocument {
		guard let remoteURL = configuration.remoteURL,
		      remoteURL.scheme?.lowercased() == "https",
		      let publicKeyData = configuration.publicKey else {
			throw ReleaseNotesCatalogRemoteRejection.invalidConfiguration
		}

		let request = URLRequest(
			url: remoteURL,
			cachePolicy: .reloadRevalidatingCacheData,
			timeoutInterval: 10
		)
		let response: ReleaseNotesFetchResponse
		do {
			response = try await loader.load(request)
		} catch {
			throw ReleaseNotesCatalogRemoteRejection.network
		}
		guard let httpResponse = response.response as? HTTPURLResponse,
		      (200..<300).contains(httpResponse.statusCode) else {
			throw ReleaseNotesCatalogRemoteRejection.http
		}
		guard response.data.count <= configuration.maximumEnvelopeSize,
		      httpResponse.expectedContentLength <= Int64(configuration.maximumEnvelopeSize) else {
			throw ReleaseNotesCatalogRemoteRejection.oversized
		}

		let envelope: SignedReleaseNotesCatalogEnvelope
		do {
			envelope = try JSONDecoder().decode(SignedReleaseNotesCatalogEnvelope.self, from: response.data)
		} catch {
			throw ReleaseNotesCatalogRemoteRejection.invalidCatalog
		}
		guard envelope.schemaVersion == SignedReleaseNotesCatalogEnvelope.supportedSchemaVersion else {
			throw ReleaseNotesCatalogRemoteRejection.invalidEnvelopeSchema
		}
		guard envelope.payload.count <= configuration.maximumEnvelopeSize else {
			throw ReleaseNotesCatalogRemoteRejection.oversized
		}

		let publicKey: Curve25519.Signing.PublicKey
		do {
			publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
		} catch {
			throw ReleaseNotesCatalogRemoteRejection.invalidConfiguration
		}
		guard publicKey.isValidSignature(envelope.signature, for: envelope.payload) else {
			throw ReleaseNotesCatalogRemoteRejection.invalidSignature
		}

		do {
			return try ReleaseNotesCatalogCodec.decodeRemotePayload(envelope.payload)
		} catch {
			throw ReleaseNotesCatalogRemoteRejection.invalidCatalog
		}
	}
}
