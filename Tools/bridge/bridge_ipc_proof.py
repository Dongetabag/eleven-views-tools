#!/usr/bin/env python3
"""ElevenViewsBridge signed-IPC proof (ELE-3160).

The signed XPC transport itself (`Sources/ElevenViewsBridgeIPC/XPCBridgeListener.swift`)
can only run on macOS with a real code signature. What is portable — and what
actually gates security — is the *decision table* the bridge applies once the
signed IPC layer has verified a caller:

    1. caller signature valid?            -> else denied  (caller.unsigned)
    2. caller in trusted-callers list?    -> else denied  (caller.untrusted)
    3. capability in registry allowlist?  -> else denied  (capability.unknown)
    4. capability allowed for THIS caller?-> else denied  (capability.forbiddenForCaller)
    5. requested scope == registry scope? -> else denied  (scope.mismatch)
    6. approvalRequired -> valid token?   -> else needs_approval (approval.*)
    otherwise                             -> success

This file re-implements that exact table (mirroring `BridgeAuthorizer.swift`),
drives it against the REAL `capability-registry.v1.json` and
`trusted-callers.v1.json`, and for every scenario:

  * synthesises a `BridgeRequest` and validates it against the v1 request schema,
  * runs the decision, builds a `BridgeReceipt` and validates it against the v1
    receipt schema,
  * asserts the outcome + error code match what we expect.

Any mismatch (a request that should be denied slips through, a receipt that does
not match the schema, an unexpected code) fails the process. That is the proof.
"""

from __future__ import annotations

import argparse
import json
import sys
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIDGE_DIR = REPO_ROOT / "docs/bridge"
SCHEMA_DIR = BRIDGE_DIR / "schemas"
REGISTRY = BRIDGE_DIR / "capability-registry.v1.json"
TRUSTED = REPO_ROOT / "Tools/bridge/trusted-callers.v1.json"

HOST = {"app": "Eleven Views Tools", "version": "3.1.4"}


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


@dataclass
class Identity:
    """What the signed IPC layer reports after verifying the peer signature."""

    team_id: str | None
    signing_identifier: str | None
    signature_valid: bool


@dataclass
class Scenario:
    name: str
    identity: Identity
    capability: str
    scope: str
    approval: dict | None
    expect_outcome: str
    expect_code: str | None
    caller_name: str = "test-caller"
    parameters: dict | None = field(default=None)


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def _trusted_caller(policy: dict, identity: Identity) -> dict | None:
    if not identity.team_id or not identity.signing_identifier:
        return None
    for caller in policy["callers"]:
        if (caller["teamId"] == identity.team_id
                and caller["signingIdentifier"] == identity.signing_identifier):
            return caller
    return None


def _approval_expired(approval: dict, now: datetime) -> bool:
    expires = approval.get("expiresAt")
    if not expires:
        return False
    try:
        dt = datetime.fromisoformat(expires.replace("Z", "+00:00"))
    except ValueError:
        return False
    return dt < now


def decide(registry: dict, policy: dict, scenario: Scenario, now: datetime) -> tuple[str, str | None]:
    """Mirror of BridgeAuthorizer.authorize. Returns (outcome, error_code)."""

    ident = scenario.identity
    if not ident.signature_valid or not ident.team_id or not ident.signing_identifier:
        return "denied", "caller.unsigned"

    trusted = _trusted_caller(policy, ident)
    if trusted is None:
        return "denied", "caller.untrusted"

    caps = {c["id"]: c for c in registry["capabilities"]}
    cap = caps.get(scenario.capability)
    if cap is None:
        return "denied", "capability.unknown"

    allowed = trusted.get("allowedCapabilities")
    if allowed and cap["id"] not in allowed:
        return "denied", "capability.forbiddenForCaller"

    if scenario.scope != cap["scope"]:
        return "denied", "scope.mismatch"

    if cap.get("approvalRequired"):
        approval = scenario.approval
        if approval is None:
            return "needs_approval", "approval.missing"
        if _approval_expired(approval, now):
            return "needs_approval", "approval.expired"
        if not str(approval.get("token", "")).strip():
            return "needs_approval", "approval.empty"

    return "success", None


def build_request(scenario: Scenario, now: datetime) -> dict:
    caller = {"id": scenario.caller_name, "name": scenario.caller_name}
    # Identity fields on the request mirror what the signed layer verified; the
    # bridge never trusts them, but the schema carries them for the receipt trail.
    if scenario.identity.team_id:
        caller["teamId"] = scenario.identity.team_id
    if scenario.identity.signing_identifier:
        caller["signingIdentifier"] = scenario.identity.signing_identifier

    request = {
        "schema": "elevenviews.bridge.request.v1",
        "requestId": str(uuid.uuid4()),
        "capability": scenario.capability,
        "scope": scenario.scope,
        "caller": caller,
        "requestedAt": _iso(now),
    }
    if scenario.parameters:
        request["parameters"] = scenario.parameters
    if scenario.approval:
        request["approval"] = scenario.approval
    return request


def build_receipt(request: dict, registry: dict, outcome: str, code: str | None,
                  started: datetime, completed: datetime) -> dict:
    cap = next((c for c in registry["capabilities"] if c["id"] == request["capability"]), None)
    receipt = {
        "schema": "elevenviews.bridge.receipt.v1",
        "receiptId": str(uuid.uuid4()),
        "requestId": request["requestId"],
        "capability": request["capability"],
        "outcome": outcome,
        "permissionsUsed": cap["permissions"] if (cap and outcome == "success") else [],
        "startedAt": _iso(started),
        "completedAt": _iso(completed),
        "host": {**HOST, "registryVersion": registry["registryVersion"]},
    }
    if outcome == "success":
        receipt["artifacts"] = []
    else:
        receipt["error"] = {"code": code or "denied", "message": f"{outcome}: {code}"}
    return receipt


def scenarios() -> list[Scenario]:
    trusted = Identity("EV11VIEWS0", "io.elevenviews.tools.bridge-harness", True)
    desk = Identity("EV11VIEWS0", "io.elevenviews.desk", True)
    wrong_team = Identity("BADTEAM123", "io.elevenviews.tools.bridge-harness", True)
    unsigned = Identity(None, None, False)
    tampered = Identity("EV11VIEWS0", "io.elevenviews.tools.bridge-harness", False)

    now = datetime.now(timezone.utc)
    fresh_token = {
        "token": "approval-" + uuid.uuid4().hex,
        "grantedBy": "local-user-action",
        "grantedAt": _iso(now),
        "expiresAt": _iso(now + timedelta(minutes=5)),
    }
    stale_token = {
        "token": "approval-" + uuid.uuid4().hex,
        "grantedBy": "local-user-action",
        "grantedAt": _iso(now - timedelta(minutes=30)),
        "expiresAt": _iso(now - timedelta(minutes=10)),
    }

    return [
        Scenario("read capability, trusted signed caller",
                 trusted, "system.snapshot", "read", None, "success", None,
                 caller_name="io.elevenviews.tools.bridge-harness"),
        Scenario("capture with fresh approval",
                 trusted, "screen.captureRegion", "capture", fresh_token, "success", None,
                 caller_name="io.elevenviews.tools.bridge-harness"),
        Scenario("unsigned caller is rejected",
                 unsigned, "system.snapshot", "read", None, "denied", "caller.unsigned"),
        Scenario("tampered signature (valid=false) is rejected",
                 tampered, "system.snapshot", "read", None, "denied", "caller.unsigned"),
        Scenario("wrong team id not in trusted list",
                 wrong_team, "system.snapshot", "read", None, "denied", "caller.untrusted"),
        Scenario("unknown capability is rejected",
                 trusted, "system.exfiltrate", "read", None, "denied", "capability.unknown",
                 caller_name="io.elevenviews.tools.bridge-harness"),
        Scenario("capability not allowed for this caller (desk cannot keepAwake)",
                 desk, "power.keepAwake", "run", None, "denied", "capability.forbiddenForCaller",
                 caller_name="io.elevenviews.desk"),
        Scenario("scope mismatch (read requested for a capture capability)",
                 trusted, "screen.captureRegion", "read", fresh_token, "denied", "scope.mismatch",
                 caller_name="io.elevenviews.tools.bridge-harness"),
        Scenario("approval-required capability with no token",
                 trusted, "screen.captureRegion", "capture", None, "needs_approval", "approval.missing",
                 caller_name="io.elevenviews.tools.bridge-harness"),
        Scenario("approval-required capability with expired token",
                 trusted, "screen.captureRegion", "capture", stale_token, "needs_approval", "approval.expired",
                 caller_name="io.elevenviews.tools.bridge-harness"),
        Scenario("share attach with fresh approval (desk caller)",
                 desk, "share.attachToDeskIssue", "share", fresh_token, "success", None,
                 caller_name="io.elevenviews.desk"),
        Scenario("share attach without approval token",
                 desk, "share.attachToDeskIssue", "share", None, "needs_approval", "approval.missing",
                 caller_name="io.elevenviews.desk"),
        Scenario("harness cannot invoke share attach (forbidden for caller)",
                 trusted, "share.attachToDeskIssue", "share", fresh_token, "denied", "capability.forbiddenForCaller",
                 caller_name="io.elevenviews.tools.bridge-harness"),
    ]


def run(emit_dir: Path | None) -> int:
    try:
        import jsonschema
    except ImportError:
        print("ERROR: jsonschema not installed (pip install jsonschema).", file=sys.stderr)
        return 2

    registry = load(REGISTRY)
    policy = load(TRUSTED)
    request_schema = load(SCHEMA_DIR / "bridge-request.v1.schema.json")
    receipt_schema = load(SCHEMA_DIR / "bridge-receipt.v1.schema.json")
    policy_schema = load(SCHEMA_DIR / "trusted-callers.v1.schema.json")

    # The trusted-callers policy is itself part of the contract; validate it.
    try:
        jsonschema.validate(policy, policy_schema)
    except jsonschema.ValidationError as exc:
        print(f"ERROR: trusted-callers.v1.json is invalid: {exc.message}", file=sys.stderr)
        return 1

    if emit_dir:
        emit_dir.mkdir(parents=True, exist_ok=True)

    failures = 0
    print(f"Signed-IPC proof — registry v{registry['registryVersion']}, "
          f"{len(policy['callers'])} trusted caller(s), {len(scenarios())} scenarios\n")
    print(f"{'scenario':<52} {'expected':<26} {'actual':<26} result")
    print("-" * 116)

    for sc in scenarios():
        started = datetime.now(timezone.utc)
        request = build_request(sc, started)

        # 1. The synthesised request must itself be a valid v1 request.
        try:
            jsonschema.validate(request, request_schema)
        except jsonschema.ValidationError as exc:
            failures += 1
            print(f"{sc.name:<52} REQUEST SCHEMA INVALID: {exc.message}")
            continue

        outcome, code = decide(registry, policy, sc, started)
        completed = datetime.now(timezone.utc)
        receipt = build_receipt(request, registry, outcome, code, started, completed)

        # 2. The receipt must be a valid v1 receipt.
        schema_ok = True
        try:
            jsonschema.validate(receipt, receipt_schema)
        except jsonschema.ValidationError as exc:
            schema_ok = False
            print(f"{sc.name:<52} RECEIPT SCHEMA INVALID: {exc.message}")

        # 3. The decision must match expectation.
        exp = f"{sc.expect_outcome}/{sc.expect_code or '-'}"
        act = f"{outcome}/{code or '-'}"
        ok = schema_ok and outcome == sc.expect_outcome and code == sc.expect_code
        if not ok:
            failures += 1
        print(f"{sc.name:<52} {exp:<26} {act:<26} {'PASS' if ok else 'FAIL'}")

        if emit_dir:
            slug = sc.name.split("(")[0].strip().replace(" ", "-").replace(",", "")[:40]
            (emit_dir / f"{slug}.request.json").write_text(json.dumps(request, indent=2) + "\n")
            (emit_dir / f"{slug}.receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")

    print("-" * 116)
    if failures:
        print(f"\n{failures} scenario(s) FAILED — signed-IPC policy is not holding.", file=sys.stderr)
        return 1
    print("\nAll scenarios passed: unsigned/untrusted/unknown/forbidden/scope/approval all enforced.")
    if emit_dir:
        print(f"Emitted request+receipt evidence to {emit_dir}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--emit", metavar="DIR", type=Path, default=None,
                        help="write each scenario's request+receipt JSON to DIR")
    args = parser.parse_args()
    return run(args.emit)


if __name__ == "__main__":
    raise SystemExit(main())
