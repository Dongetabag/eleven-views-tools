// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The signed XPC transport for ElevenViewsBridge.
///
/// Wire format is deliberately simple: each XPC message carries one key,
/// `payload`, whose value is the UTF-8 JSON of a `BridgeRequest`. The reply
/// carries `payload` = JSON of a `BridgeReceipt`. Keeping the envelope to a
/// single JSON blob means the exact same bytes are what the portable proof
/// (`bridge_ipc_proof.py`) validates against the v1 schemas.
///
/// Flow per message:
///   1. Read the peer's audit token from the connection.
///   2. `CallerSignatureVerifier` turns it into a verified identity.
///   3. `BridgeAuthorizer` decides allow / deny using the two allowlists.
///   4. On allow, the request is dispatched to the backing feature runner;
///      on deny, a receipt with the deny outcome is returned immediately.
///
/// The Darwin transport is gated behind `canImport(XPC)` so the contract,
/// registry, trusted-caller policy and authorizer all build and are proven on
/// Linux/CI where XPC and Security do not exist.
public struct BridgeMessageEnvelope {
    public static let payloadKey = "payload"
}

/// Something that actually performs an allowed capability and produces the
/// artifacts / permissionsUsed for the receipt. Kept abstract here; the
/// Capture-to-Desk slice (ELE-3161) supplies the concrete runner.
public protocol BridgeCapabilityRunner: Sendable {
    func run(request: BridgeRequest,
             capabilityId: String,
             permissions: [String]) throws -> (outcome: BridgeOutcome, artifacts: [BridgeArtifact], permissionsUsed: [String])
}

/// Pure request→receipt handler shared by every transport. This is what the
/// XPC listener calls once it has a verified identity, and what the proof
/// harness drives directly.
public struct BridgeRequestHandler: Sendable {
    public let authorizer: BridgeAuthorizer
    public let host: BridgeHost
    public let runner: BridgeCapabilityRunner?

    public init(authorizer: BridgeAuthorizer, host: BridgeHost, runner: BridgeCapabilityRunner? = nil) {
        self.authorizer = authorizer
        self.host = host
        self.runner = runner
    }

    public func handle(request: BridgeRequest,
                       identity: BridgeAuthorizer.VerifiedIdentity,
                       now: Date = Date()) -> BridgeReceipt {
        let startedAt = Self.iso(now)
        switch authorizer.authorize(request: request, identity: identity, now: now) {
        case let .deny(outcome, code, message):
            return BridgeReceipt(requestId: request.requestId,
                                 capability: request.capability,
                                 outcome: outcome,
                                 permissionsUsed: [],
                                 error: BridgeError(code: code, message: message),
                                 startedAt: startedAt,
                                 completedAt: Self.iso(Date()),
                                 host: host)
        case let .allow(capabilityId, permissions):
            guard let runner else {
                // No runner wired yet (proof / contract-only builds): report
                // that the caller cleared policy but nothing executed it.
                return BridgeReceipt(requestId: request.requestId,
                                     capability: capabilityId,
                                     outcome: .success,
                                     permissionsUsed: permissions,
                                     artifacts: [],
                                     startedAt: startedAt,
                                     completedAt: Self.iso(Date()),
                                     host: host)
            }
            do {
                let result = try runner.run(request: request,
                                            capabilityId: capabilityId,
                                            permissions: permissions)
                return BridgeReceipt(requestId: request.requestId,
                                     capability: capabilityId,
                                     outcome: result.outcome,
                                     permissionsUsed: result.permissionsUsed,
                                     artifacts: result.artifacts,
                                     startedAt: startedAt,
                                     completedAt: Self.iso(Date()),
                                     host: host)
            } catch {
                return BridgeReceipt(requestId: request.requestId,
                                     capability: capabilityId,
                                     outcome: .failed,
                                     permissionsUsed: permissions,
                                     error: BridgeError(code: "runner.failed", message: "\(error)"),
                                     startedAt: startedAt,
                                     completedAt: Self.iso(Date()),
                                     host: host)
            }
        }
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

#if canImport(XPC)
import XPC
#if canImport(Security)
import Security

/// Bridging shim for the audit token of an XPC peer. `xpc_connection_get_audit_token`
/// is SPI; production builds declare it in a private module map. It is isolated
/// here so the rest of the transport stays portable.
@_silgen_name("xpc_connection_get_audit_token")
func _xpc_connection_get_audit_token(_ connection: xpc_connection_t, _ token: UnsafeMutablePointer<audit_token_t>)

public final class XPCBridgeListener {
    private let machServiceName: String
    private let handler: BridgeRequestHandler
    private let verifier: CallerSignatureVerifier
    private let designatedRequirement: String?
    private var listener: xpc_connection_t?

    public init(machServiceName: String,
                handler: BridgeRequestHandler,
                verifier: CallerSignatureVerifier = CallerSignatureVerifier(),
                designatedRequirement: String? = nil) {
        self.machServiceName = machServiceName
        self.handler = handler
        self.verifier = verifier
        self.designatedRequirement = designatedRequirement
    }

    public func resume() {
        let listener = xpc_connection_create_mach_service(machServiceName, nil,
                                                          UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))
        self.listener = listener
        xpc_connection_set_event_handler(listener) { [weak self] peer in
            guard let self, xpc_get_type(peer) == XPC_TYPE_CONNECTION else { return }
            self.configure(peer: peer)
        }
        xpc_connection_resume(listener)
    }

    private func configure(peer: xpc_connection_t) {
        xpc_connection_set_event_handler(peer) { [weak self] event in
            guard let self, xpc_get_type(event) == XPC_TYPE_DICTIONARY else { return }
            self.serve(event: event, peer: peer)
        }
        xpc_connection_resume(peer)
    }

    private func serve(event: xpc_object_t, peer: xpc_connection_t) {
        var token = audit_token_t()
        _xpc_connection_get_audit_token(peer, &token)
        let verified = verifier.verify(auditToken: token, designatedRequirement: designatedRequirement)
        let identity = BridgeAuthorizer.VerifiedIdentity(teamId: verified.teamId,
                                                         signingIdentifier: verified.signingIdentifier,
                                                         signatureValid: verified.isValid)

        guard let reply = xpc_dictionary_create_reply(event) else { return }
        let receipt = buildReceipt(from: event, identity: identity)
        if let data = try? JSONEncoder().encode(receipt) {
            data.withUnsafeBytes { raw in
                xpc_dictionary_set_data(reply, BridgeMessageEnvelope.payloadKey,
                                        raw.baseAddress, raw.count)
            }
        }
        xpc_connection_send_message(peer, reply)
    }

    private func buildReceipt(from event: xpc_object_t,
                              identity: BridgeAuthorizer.VerifiedIdentity) -> BridgeReceipt {
        var length = 0
        let now = Date()
        guard let ptr = xpc_dictionary_get_data(event, BridgeMessageEnvelope.payloadKey, &length),
              let request = try? JSONDecoder().decode(BridgeRequest.self,
                                                      from: Data(bytes: ptr, count: length)) else {
            return BridgeReceipt(requestId: "00000000-0000-0000-0000-000000000000",
                                 capability: "unknown",
                                 outcome: .failed,
                                 error: BridgeError(code: "request.malformed",
                                                    message: "Could not decode BridgeRequest payload."),
                                 startedAt: BridgeRequestHandler.iso(now),
                                 completedAt: BridgeRequestHandler.iso(Date()),
                                 host: handler.host)
        }
        return handler.handle(request: request, identity: identity, now: now)
    }
}
#endif
#endif
