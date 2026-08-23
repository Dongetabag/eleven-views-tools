// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Swift mirror of the ElevenViewsBridge v1 wire contract defined in
/// `docs/bridge/schemas/*.v1.schema.json`. These types are transport-agnostic:
/// the same `BridgeRequest` / `BridgeReceipt` cross the signed XPC channel
/// (`XPCBridgeListener`) and are exercised by the portable proof harness
/// (`Tools/bridge/bridge_ipc_proof.py`).

public enum BridgeScope: String, Codable, CaseIterable, Sendable {
    case read, capture, share, run, system
}

public enum BridgeOutcome: String, Codable, Sendable {
    case success
    case failed
    case denied
    case cancelled
    case needsPermission = "needs_permission"
    case needsApproval = "needs_approval"
}

/// Who is asking. The signed IPC layer fills `teamId` / `signingIdentifier`
/// from the *verified* code signature of the connecting process — callers can
/// never assert these themselves over the wire.
public struct BridgeCaller: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var teamId: String?
    public var signingIdentifier: String?

    public init(id: String, name: String, teamId: String? = nil, signingIdentifier: String? = nil) {
        self.id = id
        self.name = name
        self.teamId = teamId
        self.signingIdentifier = signingIdentifier
    }
}

public struct BridgeApproval: Codable, Equatable, Sendable {
    public enum GrantedBy: String, Codable, Sendable {
        case localUserAction = "local-user-action"
        case policy
    }

    public var token: String
    public var grantedBy: GrantedBy?
    public var grantedAt: String
    public var expiresAt: String?

    public init(token: String, grantedBy: GrantedBy? = nil, grantedAt: String, expiresAt: String? = nil) {
        self.token = token
        self.grantedBy = grantedBy
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
    }
}

public struct BridgeRequest: Codable, Sendable {
    public var schema: String
    public var requestId: String
    public var capability: String
    public var scope: BridgeScope
    public var parameters: [String: AnyCodable]?
    public var caller: BridgeCaller
    public var approval: BridgeApproval?
    public var requestedAt: String

    public static let schemaId = "elevenviews.bridge.request.v1"

    public init(requestId: String,
                capability: String,
                scope: BridgeScope,
                caller: BridgeCaller,
                parameters: [String: AnyCodable]? = nil,
                approval: BridgeApproval? = nil,
                requestedAt: String) {
        self.schema = Self.schemaId
        self.requestId = requestId
        self.capability = capability
        self.scope = scope
        self.caller = caller
        self.parameters = parameters
        self.approval = approval
        self.requestedAt = requestedAt
    }
}

public struct BridgeArtifact: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case file, text, json, image }
    public var kind: Kind
    public var path: String?
    public var mimeType: String?
    public var bytes: Int?
    public var sha256: String?
    public var description: String?
}

public struct BridgeError: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct BridgeHost: Codable, Sendable {
    public var app: String
    public var version: String
    public var registryVersion: Int?
    public init(app: String, version: String, registryVersion: Int? = nil) {
        self.app = app
        self.version = version
        self.registryVersion = registryVersion
    }
}

public struct BridgeReceipt: Codable, Sendable {
    public var schema: String
    public var receiptId: String
    public var requestId: String
    public var capability: String
    public var outcome: BridgeOutcome
    public var artifacts: [BridgeArtifact]?
    public var permissionsUsed: [String]
    public var error: BridgeError?
    public var startedAt: String
    public var completedAt: String
    public var host: BridgeHost

    public static let schemaId = "elevenviews.bridge.receipt.v1"

    public init(receiptId: String = UUID().uuidString,
                requestId: String,
                capability: String,
                outcome: BridgeOutcome,
                permissionsUsed: [String] = [],
                artifacts: [BridgeArtifact]? = nil,
                error: BridgeError? = nil,
                startedAt: String,
                completedAt: String,
                host: BridgeHost) {
        self.schema = Self.schemaId
        self.receiptId = receiptId
        self.requestId = requestId
        self.capability = capability
        self.outcome = outcome
        self.permissionsUsed = permissionsUsed
        self.artifacts = artifacts
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.host = host
    }
}

/// Minimal type-erased JSON value so `parameters` can round-trip arbitrary
/// capability arguments without pulling in a dependency.
public struct AnyCodable: Codable, Sendable {
    public let value: Sendable
    public init(_ value: Sendable) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = Optional<Int>.none as Sendable? ?? 0
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Sendable]: try container.encode(array.map(AnyCodable.init))
        case let dict as [String: Sendable]: try container.encode(dict.mapValues(AnyCodable.init))
        default: try container.encodeNil()
        }
    }
}
