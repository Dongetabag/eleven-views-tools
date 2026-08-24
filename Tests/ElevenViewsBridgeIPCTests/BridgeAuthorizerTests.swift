// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import XCTest
@testable import ElevenViewsBridgeIPC

/// Swift-side proof of the signed-IPC decision table. This mirrors, scenario
/// for scenario, the portable `Tools/bridge/bridge_ipc_proof.py`. The two must
/// stay in lockstep: the Python proof runs everywhere (CI/Linux), these tests
/// run on macOS where the real XPC + Security transport lives.
final class BridgeAuthorizerTests: XCTestCase {
    private func makeRegistry() -> CapabilityRegistry {
        func cap(_ id: String, _ scope: BridgeScope, approval: Bool, perms: [String] = []) -> CapabilityRegistry.Capability {
            .init(id: id, title: id, kind: "app_intent", scope: scope,
                  approvalRequired: approval, permissions: perms, beta: false,
                  description: nil, feature: nil, commandBarActionId: nil)
        }
        return CapabilityRegistry(
            schema: "elevenviews.bridge.capability-registry.v1",
            registryVersion: 1,
            app: .init(bundleId: "io.elevenviews.tools", name: "Eleven Views Tools"),
            permissions: ["screenRecording"],
            capabilities: [
                cap("system.snapshot", .read, approval: false),
                cap("screen.captureRegion", .capture, approval: true, perms: ["screenRecording"]),
                cap("power.keepAwake", .run, approval: false)
            ])
    }

    private func makePolicy() -> TrustedCallerPolicy {
        TrustedCallerPolicy(
            schema: "elevenviews.bridge.trusted-callers.v1",
            policyVersion: 1,
            requireExplicitAllowlist: true,
            callers: [
                .init(id: "harness", name: "harness", teamId: "EV11VIEWS0",
                      signingIdentifier: "io.elevenviews.tools.bridge-harness",
                      allowedCapabilities: ["system.snapshot", "screen.captureRegion", "power.keepAwake"]),
                .init(id: "desk", name: "desk", teamId: "EV11VIEWS0",
                      signingIdentifier: "io.elevenviews.desk",
                      allowedCapabilities: ["system.snapshot", "screen.captureRegion"])
            ])
    }

    private func authorizer() -> BridgeAuthorizer {
        BridgeAuthorizer(registry: makeRegistry(), trustedCallers: makePolicy())
    }

    private func request(_ capability: String, _ scope: BridgeScope,
                         approval: BridgeApproval? = nil) -> BridgeRequest {
        BridgeRequest(requestId: UUID().uuidString, capability: capability, scope: scope,
                      caller: BridgeCaller(id: "harness", name: "harness"),
                      approval: approval, requestedAt: "2026-08-23T16:00:00.000Z")
    }

    private let trusted = BridgeAuthorizer.VerifiedIdentity(
        teamId: "EV11VIEWS0", signingIdentifier: "io.elevenviews.tools.bridge-harness", signatureValid: true)

    func testTrustedReadCapabilityIsAllowed() {
        let d = authorizer().authorize(request: request("system.snapshot", .read), identity: trusted)
        XCTAssertEqual(d, .allow(capabilityId: "system.snapshot", permissions: []))
    }

    func testUnsignedCallerDenied() {
        let unsigned = BridgeAuthorizer.VerifiedIdentity(teamId: nil, signingIdentifier: nil, signatureValid: false)
        let d = authorizer().authorize(request: request("system.snapshot", .read), identity: unsigned)
        XCTAssertEqual(d, .deny(outcome: .denied, code: "caller.unsigned",
                                message: "Caller code signature is missing or invalid."))
    }

    func testValidSignatureButUntrustedTeamDenied() {
        let untrusted = BridgeAuthorizer.VerifiedIdentity(
            teamId: "BADTEAM123", signingIdentifier: "io.elevenviews.tools.bridge-harness", signatureValid: true)
        if case let .deny(outcome, code, _) = authorizer().authorize(request: request("system.snapshot", .read), identity: untrusted) {
            XCTAssertEqual(outcome, .denied)
            XCTAssertEqual(code, "caller.untrusted")
        } else {
            XCTFail("expected deny")
        }
    }

    func testUnknownCapabilityDenied() {
        if case let .deny(_, code, _) = authorizer().authorize(request: request("system.exfiltrate", .read), identity: trusted) {
            XCTAssertEqual(code, "capability.unknown")
        } else { XCTFail("expected deny") }
    }

    func testCapabilityForbiddenForCaller() {
        let desk = BridgeAuthorizer.VerifiedIdentity(
            teamId: "EV11VIEWS0", signingIdentifier: "io.elevenviews.desk", signatureValid: true)
        if case let .deny(_, code, _) = authorizer().authorize(request: request("power.keepAwake", .run), identity: desk) {
            XCTAssertEqual(code, "capability.forbiddenForCaller")
        } else { XCTFail("expected deny") }
    }

    func testScopeMismatchDenied() {
        if case let .deny(_, code, _) = authorizer().authorize(request: request("screen.captureRegion", .read), identity: trusted) {
            XCTAssertEqual(code, "scope.mismatch")
        } else { XCTFail("expected deny") }
    }

    func testApprovalRequiredWithoutTokenNeedsApproval() {
        if case let .deny(outcome, code, _) = authorizer().authorize(request: request("screen.captureRegion", .capture), identity: trusted) {
            XCTAssertEqual(outcome, .needsApproval)
            XCTAssertEqual(code, "approval.missing")
        } else { XCTFail("expected needs_approval") }
    }

    func testApprovalRequiredWithExpiredTokenNeedsApproval() {
        let expired = BridgeApproval(token: "abc", grantedBy: .localUserAction,
                                     grantedAt: "2026-08-23T15:00:00.000Z",
                                     expiresAt: "2026-08-23T15:10:00.000Z")
        let now = ISO8601DateFormatter().date(from: "2026-08-23T16:00:00Z")!
        if case let .deny(outcome, code, _) = authorizer().authorize(
            request: request("screen.captureRegion", .capture, approval: expired), identity: trusted, now: now) {
            XCTAssertEqual(outcome, .needsApproval)
            XCTAssertEqual(code, "approval.expired")
        } else { XCTFail("expected needs_approval") }
    }

    func testApprovalRequiredWithFreshTokenAllowed() {
        let fresh = BridgeApproval(token: "abc", grantedBy: .localUserAction,
                                   grantedAt: "2026-08-23T16:00:00.000Z",
                                   expiresAt: "2026-08-23T16:05:00.000Z")
        let now = ISO8601DateFormatter().date(from: "2026-08-23T16:01:00Z")!
        let d = authorizer().authorize(request: request("screen.captureRegion", .capture, approval: fresh),
                                       identity: trusted, now: now)
        XCTAssertEqual(d, .allow(capabilityId: "screen.captureRegion", permissions: ["screenRecording"]))
    }

    func testHandlerEmitsDenyReceiptForUnsignedCaller() {
        let handler = BridgeRequestHandler(
            authorizer: authorizer(),
            host: BridgeHost(app: "Eleven Views Tools", version: "3.1.4", registryVersion: 1))
        let unsigned = BridgeAuthorizer.VerifiedIdentity(teamId: nil, signingIdentifier: nil, signatureValid: false)
        let receipt = handler.handle(request: request("system.snapshot", .read), identity: unsigned)
        XCTAssertEqual(receipt.outcome, .denied)
        XCTAssertEqual(receipt.error?.code, "caller.unsigned")
        XCTAssertEqual(receipt.schema, BridgeReceipt.schemaId)
    }
}
