<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# ElevenViewsBridge v1

`ElevenViewsBridge` is the versioned local contract other Eleven Views surfaces
(Desk, Hub, Audio, Flow, Atlas) use to ask Eleven Views Tools to do something on
the Mac and get back an evidence receipt. Feature code never couples directly to
another app: everything goes through this contract.

It is **local-first and allowlisted**. A caller can only invoke a capability that
appears in the [capability registry](capability-registry.v1.json), the bridge
re-checks scope / caller / approval before running, and no file, capture,
recording, clipboard, or credential leaves the Mac without a visible user action
and a destination preview.

## Pieces

| File | What it is |
| --- | --- |
| [`schemas/capability-registry.v1.schema.json`](schemas/capability-registry.v1.schema.json) | Shape of the capability registry. |
| [`schemas/bridge-request.v1.schema.json`](schemas/bridge-request.v1.schema.json) | Shape of an inbound action request. |
| [`schemas/bridge-receipt.v1.schema.json`](schemas/bridge-receipt.v1.schema.json) | Shape of the receipt returned for every request. |
| [`capability-registry.v1.json`](capability-registry.v1.json) | **Generated** allowlist of capabilities. Do not hand-edit. |
| [`examples/`](examples/) | Worked request + receipt pairs. |
| [`signed-ipc.md`](signed-ipc.md) | The signed XPC transport + trusted-caller allowlist (ELE-3160). |
| [`schemas/trusted-callers.v1.schema.json`](schemas/trusted-callers.v1.schema.json) | Shape of the trusted-callers allowlist. |
| `../../Tools/bridge/manifest.json` | Curated source of truth for the capability allowlist. |
| `../../Tools/bridge/trusted-callers.v1.json` | Trusted-caller (signature) allowlist. |
| `../../Tools/bridge/bridge_tool.py` | Registry generator + validator. |
| `../../Tools/bridge/bridge_ipc_proof.py` | Signed-IPC decision-table proof. |
| `../../Sources/Vorssaint/Services/Bridge/BridgeContract.swift` | Swift `Codable` mirror of the request / receipt schemas. |
| `../../Sources/Vorssaint/Services/Bridge/ScreenCaptureRegionBridge.swift` | Handler for `screen.captureRegion`: captures a region, writes a local PNG, returns a receipt. |
| `../../Sources/Vorssaint/Services/Bridge/AttachToDeskIssueBridge.swift` | Handler for `share.attachToDeskIssue`: Desk attachments upload + read-back verify. |
| `../../Sources/Vorssaint/Services/Bridge/AttachToDeskIssueIntent.swift` | The `share.attachToDeskIssue` App Intent. |
| `../../Tools/bridge/desk_attachments_proof.py` | Portable Desk attachments API proof (upload + SHA-256 read-back). |
| `../../Sources/Vorssaint/Services/Bridge/SystemSnapshotBridge.swift` | Handler for `system.snapshot`: read-only CPU/mem/disk/network summary + receipt. |
| `../../Sources/Vorssaint/Services/Bridge/SystemSnapshotIntent.swift` | The `system.snapshot` App Intent (Shortcuts / Spotlight entry point). |

## Implemented capabilities

| Capability | Kind | Swift |
| --- | --- | --- |
| `screen.captureRegion` | `app_intent` | `CaptureScreenRegionIntent` → `ScreenCaptureRegionBridge` (ELE-3159) |
| `share.attachToDeskIssue` | `app_intent` | `AttachToDeskIssueIntent` → `AttachToDeskIssueBridge` (ELE-3164) |
| `system.snapshot` | `app_intent` | `SystemSnapshotIntent` → `SystemSnapshotBridge` (ELE-3158) |

`screen.captureRegion` returns the **local path** of the capture in its receipt
artifact and never moves the file off the Mac; a later `share`-scope capability
with a destination preview is the only way a capture leaves the device. Because
the capability is `approvalRequired`, the handler refuses with a
`needs_approval` receipt (see
[`examples/screen-captureRegion.needs-approval.receipt.json`](examples/screen-captureRegion.needs-approval.receipt.json))
when no local-user approval token is supplied.

## Lifecycle

```
caller ──request (bridge-request.v1)──▶ ElevenViewsBridge
                                          │  1. capability in registry?
                                          │  2. scope matches registry?
                                          │  3. caller signature valid?  (ELE-3160)
                                          │  4. approvalRequired ⇒ valid token?
                                          │  5. run backing AppFeature / CommandBar action
caller ◀──receipt (bridge-receipt.v1)──── │  6. emit receipt (outcome, artifacts,
                                                permissionsUsed, timestamps)
```

- **Request** carries `capability`, `scope`, `caller`, optional `parameters`, and
  an `approval` token when the capability requires one.
- **Receipt** carries the `outcome`, any `artifacts` (kept local by default),
  the macOS `permissionsUsed`, and start/complete timestamps. Every request
  yields exactly one receipt, keyed back by `requestId`.

## Capability model

Each capability declares:

- `id` — stable dotted id (e.g. `system.snapshot`); never renamed once shipped.
- `kind` — `app_intent`, `command_bar_action`, or `deep_link`.
- `scope` — `read` | `capture` | `share` | `run` | `system` (drives approval defaults).
- `approvalRequired` — when true the bridge needs a valid local-user approval token.
- `feature` — the backing `AppFeature`; its `permissions` are the ceiling.
- `permissions` — the macOS permissions the capability may consume (≤ feature ceiling).
- `beta` — mirrors `AppFeature.isBeta`.

### Why it is generated

The registry is not hand-written. `Tools/bridge/bridge_tool.py` reads the Swift
source of truth so the contract can never lie about the app:

- **`FeatureCatalog.swift`** supplies, per capability's backing feature, the
  permission ceiling and beta flag.
- **`CommandBarCatalog.swift`** supplies the set of real `action.*` ids, so a
  `command_bar_action` capability can never point at an action that does not
  exist.

The curated `Tools/bridge/manifest.json` decides *which* actions are exposed and
may **narrow** (never exceed) a feature's permission ceiling. Regenerate after
editing the manifest:

```bash
python3 Tools/bridge/bridge_tool.py generate   # write capability-registry.v1.json
python3 Tools/bridge/bridge_tool.py check       # fail if the committed file is stale
python3 Tools/bridge/bridge_tool.py validate    # schema-validate registry + examples
```

Run `check` and `validate` in CI so the registry, schemas, and Swift can never
silently drift. A ready-to-install GitHub Actions workflow (`bridge.yml`) is
tracked as a follow-up because adding it needs a token with `workflow` scope;
until then both commands run locally and in any pre-commit hook.

## Security invariants

1. Allowlist only — unknown capabilities are rejected.
2. A capability's `permissions` can only be a subset of its backing feature's
   declared permissions (enforced at generation time).
3. `approvalRequired` capabilities need a fresh local-user token.
4. Artifacts stay on the Mac; moving them off-device is a separate, approved
   `share`-scope capability with a destination preview.
5. Caller identity is verified by the [signed IPC layer](signed-ipc.md)
   (ELE-3160): the peer's code signature is validated from its audit token and
   matched against the trusted-callers allowlist before any capability check.

## Versioning

`schema` strings are pinned to `.v1`. Additive, backward-compatible changes bump
`registryVersion`. A breaking change ships a new `.v2` schema and file rather
than mutating v1.

[ELE-3160]: https://github.com/Dongetabag/eleven-views-tools
