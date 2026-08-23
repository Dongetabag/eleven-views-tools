// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Resolves and validates the code signature of a connecting peer.
///
/// On Apple platforms this uses the Security framework: the peer's audit token
/// (obtained from the XPC connection) is turned into a `SecCode`, checked for
/// validity, and matched against a `SecRequirement` (the trusted designated
/// requirement). The verified `teamId` / `signingIdentifier` are then handed to
/// `BridgeAuthorizer` — they are *never* read from the request body.
///
/// The whole type is gated on `canImport(Security)` so the transport-independent
/// contract + authorizer still build (and are proven) on Linux/CI.
public struct CallerSignatureVerifier: Sendable {
    public struct VerificationResult: Sendable {
        public var teamId: String?
        public var signingIdentifier: String?
        public var isValid: Bool
    }

    public init() {}
}

#if canImport(Security)
import Security

extension CallerSignatureVerifier {
    /// Build a `SecCode` for the peer identified by `auditToken` and validate it.
    ///
    /// - Parameter auditToken: the connecting process' audit token
    ///   (`xpc_connection_get_audit_token` / `NSXPCConnection.auditToken`).
    /// - Parameter designatedRequirement: an optional code-signing requirement
    ///   string. When provided, the peer must satisfy it (e.g. an
    ///   `anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>"`
    ///   requirement) or verification fails closed.
    public func verify(auditToken: audit_token_t,
                       designatedRequirement: String? = nil) -> VerificationResult {
        var tokenData = auditToken
        let attributes = [kSecGuestAttributeAudit: Data(bytes: &tokenData,
                                                        count: MemoryLayout<audit_token_t>.size)] as CFDictionary

        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let guestCode = code else {
            return VerificationResult(teamId: nil, signingIdentifier: nil, isValid: false)
        }

        // Static code lets us read signing info and check against a requirement.
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(guestCode, [], &staticCode) == errSecSuccess,
              let staticGuest = staticCode else {
            return VerificationResult(teamId: nil, signingIdentifier: nil, isValid: false)
        }

        // Validity: the on-disk signature must be intact.
        guard SecStaticCodeCheckValidity(staticGuest, [], nil) == errSecSuccess else {
            return VerificationResult(teamId: nil, signingIdentifier: nil, isValid: false)
        }

        // Optional designated requirement (fail closed if it does not match).
        if let requirementString = designatedRequirement {
            var requirement: SecRequirement?
            guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
                  let req = requirement,
                  SecStaticCodeCheckValidity(staticGuest, [], req) == errSecSuccess else {
                return VerificationResult(teamId: nil, signingIdentifier: nil, isValid: false)
            }
        }

        // Pull team id + signing identifier from the signing information.
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticGuest, flags, &info) == errSecSuccess,
              let signingInfo = info as? [String: Any] else {
            return VerificationResult(teamId: nil, signingIdentifier: nil, isValid: false)
        }

        let teamId = signingInfo[kSecCodeInfoTeamIdentifier as String] as? String
        let signingId = signingInfo[kSecCodeInfoIdentifier as String] as? String
        return VerificationResult(teamId: teamId, signingIdentifier: signingId, isValid: true)
    }
}
#endif
