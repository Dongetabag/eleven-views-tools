// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Swift mirror of the ElevenViewsBridge v1 wire contract
/// (`docs/bridge/schemas`). These types are the Swift source of truth for
/// encoding requests and receipts; the JSON they produce is schema-validated in
/// CI by `Tools/bridge/bridge_tool.py validate`, so the two can never drift.
///
/// Everything here is local-first: a receipt records what happened on this Mac
/// and where any artifact was written. Moving an artifact off the device is a
/// separate, user-approved `share`-scope capability and is never done here.
enum Bridge {
    static let requestSchema = "elevenviews.bridge.request.v1"
    static let receiptSchema = "elevenviews.bridge.receipt.v1"

    /// Kept in lockstep with `registryVersion` in
    /// `docs/bridge/capability-registry.v1.json`.
    static let registryVersion = 1

    /// ISO-8601 in UTC with a trailing `Z`, matching the `date-time` format the
    /// schemas require and the committed examples use.
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// `scope` values a capability can declare / a request can carry.
enum BridgeScope: String, Codable {
    case read, capture, share, run, system
}

/// The single outcome a receipt reports. Raw values match the receipt schema's
/// `outcome` enum exactly.
enum BridgeOutcome: String, Codable {
    case success
    case failed
    /// Policy or caller rejected the request.
    case denied
    case cancelled
    /// A macOS grant (e.g. Screen Recording) is missing.
    case needsPermission = "needs_permission"
    /// `approvalRequired` and no valid local-user token was supplied.
    case needsApproval = "needs_approval"
}

/// How a local approval was granted. Raw values match the request schema.
enum BridgeGrantedBy: String, Codable {
    case localUserAction = "local-user-action"
    case policy
}

/// Who is asking. On the signed IPC layer (ELE-3160) these are verified against
/// the connecting process; for a locally invoked App Intent the caller is the
/// app itself.
struct BridgeCaller: Codable {
    var id: String
    var name: String
    var teamId: String?
    var signingIdentifier: String?
}

/// The approval as it appears on a receipt (token + who granted it). The
/// request-side approval carries additional `grantedAt` / `expiresAt` fields;
/// the receipt schema forbids them, so this is deliberately narrower.
struct BridgeReceiptApproval: Codable {
    var token: String
    var grantedBy: String?
}

/// A structured error attached to a non-success receipt.
struct BridgeError: Codable {
    var code: String
    var message: String
}

/// One thing the action produced. File / image artifacts stay local until a
/// separate, user-approved `share` capability moves them.
struct BridgeArtifact: Codable {
    enum Kind: String, Codable {
        case file, text, json, image
    }

    var kind: Kind
    var path: String?
    var mimeType: String?
    var bytes: Int?
    var sha256: String?
    var description: String?
}

/// Identity of the app that produced the receipt.
struct BridgeHost: Codable {
    var app: String
    var version: String
    var registryVersion: Int?
}

/// The evidence record returned for every request. Encodes to
/// `elevenviews.bridge.receipt.v1`.
struct BridgeReceipt: Codable {
    var schema: String
    var receiptId: String
    var requestId: String
    var capability: String
    var outcome: BridgeOutcome
    var artifacts: [BridgeArtifact]?
    var permissionsUsed: [String]
    var approval: BridgeReceiptApproval?
    var error: BridgeError?
    var startedAt: String
    var completedAt: String
    var host: BridgeHost

    init(requestId: String,
         capability: String,
         outcome: BridgeOutcome,
         artifacts: [BridgeArtifact]? = nil,
         permissionsUsed: [String] = [],
         approval: BridgeReceiptApproval? = nil,
         error: BridgeError? = nil,
         startedAt: Date,
         completedAt: Date,
         host: BridgeHost) {
        self.schema = Bridge.receiptSchema
        self.receiptId = UUID().uuidString
        self.requestId = requestId
        self.capability = capability
        self.outcome = outcome
        self.artifacts = artifacts
        self.permissionsUsed = permissionsUsed
        self.approval = approval
        self.error = error
        self.startedAt = Bridge.timestamp(startedAt)
        self.completedAt = Bridge.timestamp(completedAt)
        self.host = host
    }

    /// Deterministic, schema-shaped JSON (sorted keys, pretty-printed) suitable
    /// for logging next to a capture or handing back over IPC.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    func jsonString() -> String {
        (try? jsonData()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
