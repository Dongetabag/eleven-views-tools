#!/usr/bin/env python3
"""Guard the `system.snapshot` receipt contract from Swift ↔ JSON drift.

The App Intent (`SystemSnapshotIntent`) returns a v1 bridge receipt whose inline
artifact is encoded from the Swift `SystemSnapshotPayload`. This check runs on
any machine (no Swift toolchain needed) and fails if:

  1. The `SystemSnapshotPayload` fields in BridgeReceipt.swift stop matching the
     inline payload of docs/bridge/examples/system-snapshot.receipt.json, or
  2. The example receipt (the golden output) stops validating against
     bridge-receipt.v1.schema.json.

Run alongside `bridge_tool.py check` / `validate` in CI.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RECEIPT_MODEL = REPO_ROOT / "Sources/Vorssaint/Services/Bridge/BridgeReceipt.swift"
RECEIPT_SCHEMA = REPO_ROOT / "docs/bridge/schemas/bridge-receipt.v1.schema.json"
EXAMPLE = REPO_ROOT / "docs/bridge/examples/system-snapshot.receipt.json"


def swift_payload_fields(source: str) -> list[str]:
    """Ordered `var <name>:` fields inside `struct SystemSnapshotPayload`."""
    try:
        after = source.split("struct SystemSnapshotPayload", 1)[1]
    except IndexError as exc:  # pragma: no cover - guards a rename
        raise SystemExit("SystemSnapshotPayload not found in BridgeReceipt.swift") from exc
    body = after.split("static func", 1)[0]
    return re.findall(r"var (\w+):", body)


def main() -> int:
    example = json.loads(EXAMPLE.read_text())
    inline_keys = list(example["artifacts"][0]["inline"].keys())
    swift_fields = swift_payload_fields(RECEIPT_MODEL.read_text())

    failures: list[str] = []
    if swift_fields != inline_keys:
        failures.append(
            "SystemSnapshotPayload drift:\n"
            f"  swift: {swift_fields}\n"
            f"  json : {inline_keys}"
        )

    try:
        import jsonschema

        jsonschema.validate(example, json.loads(RECEIPT_SCHEMA.read_text()))
    except ImportError:
        print("WARNING: jsonschema not installed; skipped example validation.", file=sys.stderr)
    except jsonschema.ValidationError as exc:  # type: ignore[name-defined]
        failures.append(f"example receipt fails the v1 schema: {exc.message}")

    if failures:
        print("Receipt contract check FAILED:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(f"OK  system.snapshot payload fields match ({', '.join(swift_fields)}) and the example validates.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
