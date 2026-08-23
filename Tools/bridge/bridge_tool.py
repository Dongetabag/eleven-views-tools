#!/usr/bin/env python3
"""ElevenViewsBridge registry generator and validator.

The capability registry is an allowlist: it is NOT the full command bar. It is
a curated set of actions (Tools/bridge/manifest.json) enriched with facts read
straight out of the Swift source of truth:

  - FeatureCatalog.swift  -> the AppFeature that backs each capability, the
                             macOS permissions that feature may consume, and
                             whether it is beta.
  - CommandBarCatalog.swift -> the set of real "action.*" ids, so a manifest
                             entry can never point at a command bar action that
                             does not exist.

Subcommands:
  generate   Write docs/bridge/capability-registry.v1.json from the manifest.
  check      Regenerate in memory and fail if it differs from the committed file.
  validate   Schema-validate the registry and every docs/bridge/examples/* file.

Run `check` and `validate` in CI so the registry, schemas and Swift never drift.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
FEATURE_CATALOG = REPO_ROOT / "Sources/Vorssaint/Core/FeatureCatalog.swift"
COMMANDBAR_CATALOG = REPO_ROOT / "Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift"
MANIFEST = REPO_ROOT / "Tools/bridge/manifest.json"
REGISTRY_OUT = REPO_ROOT / "docs/bridge/capability-registry.v1.json"
BRIDGE_DIR = REPO_ROOT / "docs/bridge"
SCHEMA_DIR = BRIDGE_DIR / "schemas"
EXAMPLES_DIR = BRIDGE_DIR / "examples"

COMMENT_RE = re.compile(r"//[^\n]*")
IDENT_RE = re.compile(r"\.([a-zA-Z][a-zA-Z0-9]*)")


def _strip_comments(text: str) -> str:
    return COMMENT_RE.sub("", text)


def _balanced_block(source: str, signature: str) -> str:
    """Return the {...} body that follows `signature` in `source`."""
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for i in range(brace, len(source)):
        c = source[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1 : i]
    raise ValueError(f"unbalanced braces after {signature!r}")


def parse_feature_catalog(text: str) -> dict:
    """Extract features, group, permissions and beta flags from FeatureCatalog."""
    # 1. Enum cases (bare identifiers, comma separated, possibly wrapped).
    enum_body = _strip_comments(_balanced_block(text, "enum AppFeature: String, CaseIterable"))
    features: list[str] = []
    for stmt in re.split(r"\bcase\b", enum_body):
        stmt = stmt.strip()
        if not stmt:
            continue
        for tok in re.findall(r"[a-zA-Z][a-zA-Z0-9]*", stmt):
            features.append(tok)
    feature_set = set(features)

    # 2. permissions: [AppPermission] -> map feature -> [permission raw values]
    perms_body = _strip_comments(_balanced_block(text, "var permissions: [AppPermission]"))
    permissions: dict[str, list[str]] = {}
    for labels, arr in re.findall(r"case\s+([^:]*?):\s*return\s*\[([^\]]*)\]", perms_body, re.DOTALL):
        case_features = IDENT_RE.findall(labels)
        case_perms = IDENT_RE.findall(arr)
        for f in case_features:
            if f in feature_set:
                permissions[f] = case_perms
    for f in feature_set:
        permissions.setdefault(f, [])

    # 3. beta features from isBeta.
    beta_body = _balanced_block(text, "var isBeta: Bool")
    beta = set(IDENT_RE.findall(_strip_comments(beta_body)))

    return {"features": feature_set, "permissions": permissions, "beta": beta}


def parse_commandbar_action_ids(text: str) -> set[str]:
    return set(re.findall(r'id:\s*"(action\.[a-zA-Z0-9._]+)"', text))


def build_registry() -> dict:
    fc = parse_feature_catalog(FEATURE_CATALOG.read_text())
    action_ids = parse_commandbar_action_ids(COMMANDBAR_CATALOG.read_text())
    manifest = json.loads(MANIFEST.read_text())

    features = fc["features"]
    perms_by_feature = fc["permissions"]
    beta_features = fc["beta"]

    capabilities = []
    used_permissions: set[str] = set()
    errors: list[str] = []

    for cap in manifest["capabilities"]:
        cid = cap.get("id", "<missing>")
        feature = cap.get("feature")
        feature_perms = None
        if feature is not None:
            if feature not in features:
                errors.append(f"{cid}: feature {feature!r} is not an AppFeature case")
            else:
                feature_perms = perms_by_feature.get(feature, [])

        if cap.get("kind") == "command_bar_action":
            action_id = cap.get("commandBarActionId")
            if action_id not in action_ids:
                errors.append(
                    f"{cid}: commandBarActionId {action_id!r} not found in CommandBarCatalog"
                )

        # Explicit permissions narrow the feature ceiling; they may never exceed it.
        if "permissions" in cap:
            resolved = list(cap["permissions"])
            if feature_perms is not None:
                extra = [p for p in resolved if p not in feature_perms]
                if extra:
                    errors.append(
                        f"{cid}: permissions {extra} exceed feature {feature!r} ceiling {feature_perms}"
                    )
        else:
            resolved = list(feature_perms or [])

        entry = {
            "id": cid,
            "title": cap["title"],
            "kind": cap["kind"],
            "scope": cap["scope"],
            "approvalRequired": bool(cap["approvalRequired"]),
            "permissions": resolved,
            "beta": feature in beta_features if feature else False,
        }
        if "description" in cap:
            entry["description"] = cap["description"]
        if feature:
            entry["feature"] = feature
        if cap.get("commandBarActionId"):
            entry["commandBarActionId"] = cap["commandBarActionId"]
        if cap.get("deepLink"):
            entry["deepLink"] = cap["deepLink"]
        if cap.get("parameters"):
            entry["parameters"] = cap["parameters"]
        capabilities.append(entry)
        used_permissions.update(resolved)

    if errors:
        raise SystemExit("Manifest validation failed:\n  - " + "\n  - ".join(errors))

    return {
        "schema": "elevenviews.bridge.capability-registry.v1",
        "registryVersion": manifest["registryVersion"],
        "app": manifest["app"],
        "permissions": sorted(used_permissions),
        "capabilities": capabilities,
    }


def _serialize(registry: dict) -> str:
    return json.dumps(registry, indent=2, ensure_ascii=False) + "\n"


def cmd_generate(_args) -> int:
    REGISTRY_OUT.write_text(_serialize(build_registry()))
    print(f"Wrote {REGISTRY_OUT.relative_to(REPO_ROOT)}")
    return 0


def cmd_check(_args) -> int:
    generated = _serialize(build_registry())
    if not REGISTRY_OUT.exists():
        print(f"ERROR: {REGISTRY_OUT} missing; run `bridge_tool.py generate`.", file=sys.stderr)
        return 1
    current = REGISTRY_OUT.read_text()
    if current != generated:
        print(
            "ERROR: capability-registry.v1.json is out of date.\n"
            "Run: python3 Tools/bridge/bridge_tool.py generate",
            file=sys.stderr,
        )
        return 1
    print("Registry is up to date with FeatureCatalog + CommandBar + manifest.")
    return 0


def cmd_validate(_args) -> int:
    try:
        import jsonschema
    except ImportError:
        print("ERROR: jsonschema not installed (pip install jsonschema).", file=sys.stderr)
        return 2

    def load(p: Path):
        return json.loads(p.read_text())

    registry_schema = load(SCHEMA_DIR / "capability-registry.v1.schema.json")
    request_schema = load(SCHEMA_DIR / "bridge-request.v1.schema.json")
    receipt_schema = load(SCHEMA_DIR / "bridge-receipt.v1.schema.json")

    failures = 0
    checks: list[tuple[Path, dict]] = [(REGISTRY_OUT, registry_schema)]
    for example in sorted(EXAMPLES_DIR.glob("*.json")):
        name = example.name
        if "request" in name:
            checks.append((example, request_schema))
        elif "receipt" in name:
            checks.append((example, receipt_schema))
        else:
            print(f"WARNING: {name} not matched to a schema, skipping.")

    registry = load(REGISTRY_OUT)
    known_capabilities = {c["id"] for c in registry["capabilities"]}

    for path, schema in checks:
        try:
            jsonschema.validate(load(path), schema)
            print(f"OK   {path.relative_to(REPO_ROOT)}")
        except jsonschema.ValidationError as exc:
            failures += 1
            print(f"FAIL {path.relative_to(REPO_ROOT)}: {exc.message}", file=sys.stderr)

    # Cross-check: every example request/receipt names a real registry capability.
    for example in sorted(EXAMPLES_DIR.glob("*.json")):
        data = load(example)
        cap = data.get("capability")
        if cap and cap not in known_capabilities:
            failures += 1
            print(
                f"FAIL {example.relative_to(REPO_ROOT)}: capability {cap!r} not in registry",
                file=sys.stderr,
            )

    if failures:
        print(f"{failures} validation failure(s).", file=sys.stderr)
        return 1
    print("All schema validations passed.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("generate", help="write the registry JSON")
    sub.add_parser("check", help="fail if the committed registry is stale")
    sub.add_parser("validate", help="schema-validate registry + examples")
    args = parser.parse_args()
    return {"generate": cmd_generate, "check": cmd_check, "validate": cmd_validate}[args.command](args)


if __name__ == "__main__":
    raise SystemExit(main())
