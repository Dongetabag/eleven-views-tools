// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The transport-independent decision core of the signed bridge.
///
/// Given (1) the *verified* caller identity produced by the signed IPC layer,
/// (2) an inbound `BridgeRequest`, and (3) the two allowlists (trusted callers
/// + capability registry), it decides whether the request may run.
///
/// This is the exact decision table proven end-to-end by
/// `Tools/bridge/bridge_ipc_proof.py`; keep the two in lockstep. The Swift side
/// owns production behaviour; the Python proof is the portable, CI-runnable
/// spec that exercises the same rules against the real registry JSON.
public struct BridgeAuthorizer: Sendable {
    /// A caller identity the signed IPC layer has already verified against the
    /// connecting process' code signature. `nil` fields mean the peer was
    /// unsigned / could not be verified.
    public struct VerifiedIdentity: Sendable, Equatable {
        public var teamId: String?
        public var signingIdentifier: String?
        public var signatureValid: Bool
        public init(teamId: String?, signingIdentifier: String?, signatureValid: Bool) {
            self.teamId = teamId
            self.signingIdentifier = signingIdentifier
            self.signatureValid = signatureValid
        }
    }

    public enum Decision: Equatable, Sendable {
        case allow(capabilityId: String, permissions: [String])
        case deny(outcome: BridgeOutcome, code: String, message: String)
    }

    public let registry: CapabilityRegistry
    public let trustedCallers: TrustedCallerPolicy

    public init(registry: CapabilityRegistry, trustedCallers: TrustedCallerPolicy) {
        self.registry = registry
        self.trustedCallers = trustedCallers
    }

    /// Ordered checks. Order matters: identity first (never leak capability
    /// existence to an untrusted peer), then allowlist, then scope, then
    /// approval.
    public func authorize(request: BridgeRequest, identity: VerifiedIdentity, now: Date = Date()) -> Decision {
        // 1. The signed IPC layer must have validated the caller's signature.
        guard identity.signatureValid, let teamId = identity.teamId,
              let signingId = identity.signingIdentifier else {
            return .deny(outcome: .denied,
                         code: "caller.unsigned",
                         message: "Caller code signature is missing or invalid.")
        }

        // 2. The verified identity must be an explicitly trusted caller.
        guard let trusted = trustedCallers.trustedCaller(teamId: teamId, signingIdentifier: signingId) else {
            return .deny(outcome: .denied,
                         code: "caller.untrusted",
                         message: "Caller \(teamId)/\(signingId) is not in the trusted-callers allowlist.")
        }

        // 3. Capability must exist in the registry allowlist.
        guard let capability = registry.capability(id: request.capability) else {
            return .deny(outcome: .denied,
                         code: "capability.unknown",
                         message: "Capability \(request.capability) is not in the registry.")
        }

        // 4. This trusted caller may be scoped to a subset of capabilities.
        if let allowed = trusted.allowedCapabilities, !allowed.isEmpty,
           !allowed.contains(capability.id) {
            return .deny(outcome: .denied,
                         code: "capability.forbiddenForCaller",
                         message: "Caller \(trusted.id) may not invoke \(capability.id).")
        }

        // 5. Requested scope must match the registry scope exactly.
        guard request.scope == capability.scope else {
            return .deny(outcome: .denied,
                         code: "scope.mismatch",
                         message: "Requested scope \(request.scope.rawValue) does not match registry scope \(capability.scope.rawValue).")
        }

        // 6. Approval gate: approvalRequired capabilities need a fresh token.
        if capability.approvalRequired {
            guard let approval = request.approval else {
                return .deny(outcome: .needsApproval,
                             code: "approval.missing",
                             message: "Capability \(capability.id) requires a local-user approval token.")
            }
            if isExpired(approval, now: now) {
                return .deny(outcome: .needsApproval,
                             code: "approval.expired",
                             message: "Approval token expired at \(approval.expiresAt ?? "unknown").")
            }
            if approval.token.trimmingCharacters(in: .whitespaces).isEmpty {
                return .deny(outcome: .needsApproval,
                             code: "approval.empty",
                             message: "Approval token is empty.")
            }
        }

        return .allow(capabilityId: capability.id, permissions: capability.permissions)
    }

    private func isExpired(_ approval: BridgeApproval, now: Date) -> Bool {
        guard let expiresAt = approval.expiresAt else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: expiresAt)
            ?? ISO8601DateFormatter().date(from: expiresAt)
        guard let date else { return false }
        return date < now
    }
}
