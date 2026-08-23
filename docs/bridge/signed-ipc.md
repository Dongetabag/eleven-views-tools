<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Signed XPC IPC (ELE-3160)

The [ElevenViewsBridge v1 contract](README.md) says a request only runs after
the bridge has (a) verified the caller's code signature and (b) confirmed the
capability is on the allowlist. This doc covers the transport that enforces (a),
the policy that enforces the *who* half of (b), and how both are proven.

## Two allowlists

The bridge answers two independent questions before it runs anything:

| Question | Source of truth | Enforced by |
| --- | --- | --- |
| **Who is calling?** (is this a trusted, correctly-signed process?) | [`Tools/bridge/trusted-callers.v1.json`](../../Tools/bridge/trusted-callers.v1.json) | signed IPC layer + `BridgeAuthorizer` |
| **What may they do?** (is the capability exposed, at this scope, with approval?) | [`capability-registry.v1.json`](capability-registry.v1.json) | `BridgeAuthorizer` |

Identity is **never** taken from the request body. The `caller.teamId` /
`caller.signingIdentifier` fields on a request exist only for the receipt trail;
the authorizer uses the identity the transport verified from the connecting
process' audit token.

## Components (`Sources/ElevenViewsBridgeIPC`)

| File | Role | Portable? |
| --- | --- | --- |
| `BridgeContract.swift` | Codable `BridgeRequest` / `BridgeReceipt` / caller / approval, matching the v1 schemas. | yes |
| `CapabilityRegistry.swift` | Loads + indexes the capability allowlist. | yes |
| `TrustedCallerPolicy.swift` | Loads + indexes the trusted-callers allowlist. | yes |
| `BridgeAuthorizer.swift` | The ordered decision table (allow / deny / needs_approval). | yes |
| `CallerSignatureVerifier.swift` | Turns a peer audit token into a verified team id + signing id via the Security framework. | macOS (`canImport(Security)`) |
| `XPCBridgeListener.swift` | Mach-service XPC listener: reads audit token, verifies, authorizes, replies with a receipt. | macOS (`canImport(XPC)`) |
| `Sources/BridgeHarness/main.swift` | On-Mac client: sends one request, prints the receipt. | macOS |

Everything transport-independent (contract, both registries, the decision
table) builds on Linux/CI. Only the audit-token → `SecCode` step and the XPC
wire are Apple-only, and they are isolated behind `#if canImport(...)`.

## Decision table (ordered)

`BridgeAuthorizer.authorize` applies these checks in order. Order matters:
identity is checked first so capability existence never leaks to an untrusted
peer.

1. Signature valid? → else `denied / caller.unsigned`
2. Verified identity in trusted-callers? → else `denied / caller.untrusted`
3. Capability in registry? → else `denied / capability.unknown`
4. Capability allowed for *this* caller? → else `denied / capability.forbiddenForCaller`
5. Requested scope == registry scope? → else `denied / scope.mismatch`
6. `approvalRequired` and fresh token? → else `needs_approval / approval.{missing,expired,empty}`
7. otherwise → `allow`

## Signature verification (on macOS)

`CallerSignatureVerifier`:

1. reads the peer's `audit_token_t` from the XPC connection,
2. `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)` → the peer's `SecCode`,
3. `SecStaticCodeCheckValidity` → the signature is intact,
4. optionally checks a `SecRequirement` (e.g. `anchor apple generic and
   certificate leaf[subject.OU] = "<TEAMID>"`) — **fail closed** on mismatch,
5. reads `teamIdentifier` + `identifier` from the signing information.

Those verified values — not anything from the request — are what the authorizer
matches against the trusted-callers policy.

## Proving it

The XPC hop and code-signature check only run on a signed macOS build, so the
proof is split:

- **Portable proof (CI / Linux / here):** `Tools/bridge/bridge_ipc_proof.py`
  re-implements the exact decision table, drives it against the real registry +
  trusted-callers files, and for every scenario validates the synthesised
  request and the resulting receipt against the v1 schemas, then asserts the
  outcome + error code. A denied request that slips through, or a receipt that
  fails the schema, fails the process.

  ```bash
  python3 Tools/bridge/bridge_ipc_proof.py            # assert-only
  python3 Tools/bridge/bridge_ipc_proof.py --emit /tmp/ipc-evidence   # + write receipts
  ```

  Scenarios: trusted read allow, capture-with-approval allow, unsigned deny,
  tampered-signature deny, untrusted-team deny, unknown-capability deny,
  forbidden-for-caller deny, scope-mismatch deny, missing-approval and
  expired-approval → needs_approval.

- **Swift proof (macOS CI):** `Tests/ElevenViewsBridgeIPCTests` mirrors the same
  scenarios against `BridgeAuthorizer` directly (`swift test`).

- **End-to-end (a signed Mac):** run the listener inside the app, then
  `bridge-harness <machService> system.snapshot read` and read the receipt. Only
  a harness signed with a `signingIdentifier` listed in the trusted-callers file
  gets an allow.

Keep the Python proof and the Swift tests in lockstep — they are two views of one
decision table.

## Follow-ups

- The concrete capability runner (dispatch to `AppFeature` / CommandBar actions
  and real artifact capture) lands with the Capture-to-Desk slice ([ELE-3161]).
- A `bridge.yml` GitHub Actions workflow that runs `bridge_tool.py check`,
  `bridge_tool.py validate` and `bridge_ipc_proof.py` is deferred until a token
  with `workflow` scope is available (same constraint noted in the ELE-3157 PR).

[ELE-3161]: https://github.com/Dongetabag/eleven-views-tools
