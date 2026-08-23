// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Swift models for the `ElevenViewsBridge` v1 receipt contract
/// (`docs/bridge/schemas/bridge-receipt.v1.schema.json`).
///
/// Everything here is pure Foundation with no IOKit / AppKit dependency, so the
/// standalone unit-test harness (`./build.sh --test`) can encode a receipt and
/// assert it matches the shipped JSON schema without launching the app. The
/// live readings that fill a receipt live in `SystemSnapshotReader`.
enum Bridge {
    /// Stable capability ids from the generated registry. Never renamed once
    /// shipped; they are the same strings the registry allowlists.
    enum Capability {
        static let systemSnapshot = "system.snapshot"
    }

    /// Mirrors the `outcome` enum in the receipt schema.
    enum Outcome: String, Codable {
        case success
        case failed
        case denied
        case cancelled
        case needsPermission = "needs_permission"
        case needsApproval = "needs_approval"
    }

    /// Mirrors `AppPermission`'s raw values, restricted to the set the receipt
    /// schema accepts in `permissionsUsed`.
    enum Permission: String, Codable {
        case accessibility, screenRecording, fullDiskAccess, filesAndFolders, notifications
        case automationFinder, automationTerminal, audioCapture, microphone, camera, appManagement
    }
}

/// One thing a capability produced. For `system.snapshot` this is a single
/// inline JSON artifact that never touches disk.
struct BridgeArtifact: Codable, Equatable {
    enum Kind: String, Codable { case file, text, json, image }

    var kind: Kind
    var path: String?
    var mimeType: String?
    var bytes: Int?
    var sha256: String?
    /// Inline payload for small text/json artifacts. Kept as a concrete type so
    /// the encoder stays deterministic; generalise only when a second inline
    /// shape appears.
    var inline: SystemSnapshotPayload?
    var description: String?
}

struct BridgeError: Codable, Equatable {
    var code: String
    var message: String
}

struct BridgeApproval: Codable, Equatable {
    var token: String
    var grantedBy: String?
}

struct BridgeHost: Codable, Equatable {
    var app: String
    var version: String
    var registryVersion: Int?

    /// The running app's identity. `registryVersion` is pinned to the v1
    /// registry this build ships against.
    static var current: BridgeHost {
        BridgeHost(app: AppInfo.name, version: AppInfo.version, registryVersion: 1)
    }
}

/// The `elevenviews.bridge.receipt.v1` record. Every bridge request yields
/// exactly one receipt, keyed back to the request by `requestId`.
struct BridgeReceipt: Codable, Equatable {
    static let schemaIdentifier = "elevenviews.bridge.receipt.v1"

    var schema: String
    var receiptId: UUID
    var requestId: UUID
    var capability: String
    var outcome: Bridge.Outcome
    var artifacts: [BridgeArtifact]
    var permissionsUsed: [Bridge.Permission]
    var approval: BridgeApproval?
    var error: BridgeError?
    var startedAt: Date
    var completedAt: Date
    var host: BridgeHost

    private enum CodingKeys: String, CodingKey {
        case schema, receiptId, requestId, capability, outcome, artifacts
        case permissionsUsed, approval, error, startedAt, completedAt, host
    }

    /// Explicit encoding so `approval`/`error` serialize as JSON `null` (as in
    /// the shipped examples) rather than being dropped, and so timestamps use
    /// the ISO-8601 form the schema's `date-time` format expects.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(receiptId.uuidString.lowercased(), forKey: .receiptId)
        try c.encode(requestId.uuidString.lowercased(), forKey: .requestId)
        try c.encode(capability, forKey: .capability)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(artifacts, forKey: .artifacts)
        try c.encode(permissionsUsed, forKey: .permissionsUsed)
        try c.encode(approval, forKey: .approval) // encodes null when nil
        try c.encode(error, forKey: .error)
        try c.encode(BridgeDateFormat.string(from: startedAt), forKey: .startedAt)
        try c.encode(BridgeDateFormat.string(from: completedAt), forKey: .completedAt)
        try c.encode(host, forKey: .host)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(String.self, forKey: .schema)
        receiptId = try BridgeReceipt.decodeUUID(c, .receiptId)
        requestId = try BridgeReceipt.decodeUUID(c, .requestId)
        capability = try c.decode(String.self, forKey: .capability)
        outcome = try c.decode(Bridge.Outcome.self, forKey: .outcome)
        artifacts = try c.decodeIfPresent([BridgeArtifact].self, forKey: .artifacts) ?? []
        permissionsUsed = try c.decode([Bridge.Permission].self, forKey: .permissionsUsed)
        approval = try c.decodeIfPresent(BridgeApproval.self, forKey: .approval)
        error = try c.decodeIfPresent(BridgeError.self, forKey: .error)
        startedAt = try BridgeReceipt.decodeDate(c, .startedAt)
        completedAt = try BridgeReceipt.decodeDate(c, .completedAt)
        host = try c.decode(BridgeHost.self, forKey: .host)
    }

    init(receiptId: UUID = UUID(),
         requestId: UUID,
         capability: String,
         outcome: Bridge.Outcome,
         artifacts: [BridgeArtifact] = [],
         permissionsUsed: [Bridge.Permission] = [],
         approval: BridgeApproval? = nil,
         error: BridgeError? = nil,
         startedAt: Date,
         completedAt: Date,
         host: BridgeHost = .current) {
        self.schema = BridgeReceipt.schemaIdentifier
        self.receiptId = receiptId
        self.requestId = requestId
        self.capability = capability
        self.outcome = outcome
        self.artifacts = artifacts
        self.permissionsUsed = permissionsUsed
        self.approval = approval
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.host = host
    }

    private static func decodeUUID(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> UUID {
        let raw = try c.decode(String.self, forKey: key)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "not a UUID: \(raw)")
        }
        return uuid
    }

    private static func decodeDate(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Date {
        let raw = try c.decode(String.self, forKey: key)
        guard let date = BridgeDateFormat.date(from: raw) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "not an ISO-8601 date: \(raw)")
        }
        return date
    }

    /// Deterministic JSON bytes for the receipt (sorted keys), suitable for the
    /// IPC layer and for golden-file tests.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    func jsonString() throws -> String {
        String(decoding: try jsonData(), as: UTF8.self)
    }

    /// One-line human summary used as the App Intent's spoken/typed result.
    var summaryLine: String {
        switch outcome {
        case .success:
            if let snapshot = artifacts.first?.inline {
                return snapshot.summaryLine
            }
            return "System snapshot captured."
        default:
            let reason = error?.message ?? outcome.rawValue
            return "System snapshot \(outcome.rawValue): \(reason)"
        }
    }
}

/// The inline JSON body returned for `system.snapshot`. Bytes are unsigned; the
/// CPU load is a whole percentage (0–100) with one decimal of resolution.
struct SystemSnapshotPayload: Codable, Equatable {
    var cpuLoadPercent: Double
    var memoryUsedBytes: UInt64
    var memoryTotalBytes: UInt64
    var diskFreeBytes: UInt64
    var diskTotalBytes: UInt64
    var networkUpBytesPerSec: UInt64
    var networkDownBytesPerSec: UInt64

    /// Rounds the raw fraction (0…1) coming out of SystemMonitor into the
    /// one-decimal percentage the receipt reports.
    static func cpuLoadPercent(fromFraction fraction: Double) -> Double {
        let clamped = min(1, max(0, fraction))
        return (clamped * 1000).rounded() / 10
    }

    var summaryLine: String {
        let mem = memoryTotalBytes > 0
            ? Int((Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100).rounded())
            : 0
        return "CPU \(cpuLoadPercent)% · memory \(mem)% used"
    }
}

/// The ISO-8601 form used across bridge receipts. Fixed to UTC so receipts are
/// stable regardless of the Mac's locale/time zone.
enum BridgeDateFormat {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }

    static func date(from string: String) -> Date? {
        if let date = formatter.date(from: string) { return date }
        // Tolerate fractional seconds on the way in.
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }
}
