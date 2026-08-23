// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The *who* allowlist. Loaded from `Tools/bridge/trusted-callers.v1.json`.
///
/// The signed IPC layer only accepts a connection whose *verified* code
/// signature matches one of these entries. Identity is never taken from the
/// request body — it comes from `CallerSignatureVerifier`, which reads the
/// connecting process' audit token and validates it against the Security
/// framework.
public struct TrustedCallerPolicy: Codable, Sendable {
    public struct TrustedCaller: Codable, Sendable {
        /// Stable caller id (bundle id / service name) used for logging + receipts.
        public var id: String
        public var name: String
        /// Apple Developer Team ID the caller must be signed with.
        public var teamId: String
        /// Exact code-signing identifier the caller must present.
        public var signingIdentifier: String
        /// Optional: capabilities this caller may invoke. `nil`/empty = any
        /// capability the registry allows (still subject to scope + approval).
        public var allowedCapabilities: [String]?
    }

    public var schema: String
    public var policyVersion: Int
    /// When true, a caller must additionally appear in `callers`; when false the
    /// signed layer trusts any process whose signature satisfies the platform
    /// designated requirement (used only for the on-device first-party case).
    public var requireExplicitAllowlist: Bool
    public var callers: [TrustedCaller]

    public func trustedCaller(teamId: String?, signingIdentifier: String?) -> TrustedCaller? {
        guard let teamId, let signingIdentifier else { return nil }
        return callers.first { $0.teamId == teamId && $0.signingIdentifier == signingIdentifier }
    }

    public static func load(from url: URL) throws -> TrustedCallerPolicy {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TrustedCallerPolicy.self, from: data)
    }
}
