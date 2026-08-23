#!/usr/bin/env python3
"""Parse and cross-check the versioned Eleven Views Story contracts.

This checker intentionally uses only the Python standard library so it can run
in GitHub Actions, on KVM4, and on a client Mac without installing packages.
It verifies canonical schema identities, required example fields, local JSON
Pointer references, and the approval gate represented by the approved plan.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from urllib.parse import urldefrag


ROOT = Path(__file__).resolve().parents[2]
SCHEMA_DIR = ROOT / "docs" / "story" / "schemas"
EXAMPLE_DIR = ROOT / "docs" / "story" / "examples"

EXPECTED = {
    "product-context.v1.schema.json": "atlas.product-context.v1",
    "presenter-profile.v1.schema.json": "atlas.presenter-profile.v1",
    "story-context.v1.schema.json": "atlas.story-context.v1",
    "story-brief.v1.schema.json": "story.brief.v1",
    "story-plan.v1.schema.json": "story.plan.v1",
    "flow-capture.v1.schema.json": "tools.flow-capture.v1",
    "scene-project.v1.schema.json": "story.scene-project.v1",
}


def load(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected a JSON object")
    return value


def resolve_pointer(document: object, fragment: str, source: Path) -> None:
    if not fragment:
        return
    if not fragment.startswith("/"):
        raise ValueError(f"{source}: unsupported JSON Pointer #{fragment}")
    current = document
    for raw_part in fragment[1:].split("/"):
        part = raw_part.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or part not in current:
            raise ValueError(f"{source}: unresolved JSON Pointer #{fragment}")
        current = current[part]


def walk_refs(value: object, source: Path, documents: dict[Path, dict]) -> None:
    if isinstance(value, dict):
        reference = value.get("$ref")
        if isinstance(reference, str) and not reference.startswith(("http://", "https://")):
            path_part, fragment = urldefrag(reference)
            target = source if not path_part else (source.parent / path_part).resolve()
            if target not in documents:
                if not target.exists():
                    raise ValueError(f"{source}: missing local schema reference {reference}")
                documents[target] = load(target)
            resolve_pointer(documents[target], fragment, source)
        for child in value.values():
            walk_refs(child, source, documents)
    elif isinstance(value, list):
        for child in value:
            walk_refs(child, source, documents)


def main() -> int:
    documents: dict[Path, dict] = {}
    schema_ids: set[str] = set()

    for path in sorted(SCHEMA_DIR.glob("*.json")):
        document = load(path)
        documents[path.resolve()] = document
        schema_id = document.get("$id")
        if not isinstance(schema_id, str) or not schema_id.startswith("https://elevenviews.io/"):
            raise ValueError(f"{path}: $id must use https://elevenviews.io/")
        if schema_id in schema_ids:
            raise ValueError(f"{path}: duplicate $id {schema_id}")
        schema_ids.add(schema_id)

    for path, document in list(documents.items()):
        walk_refs(document, path, documents)

    examples: list[tuple[Path, dict, dict]] = []
    for filename, contract_id in EXPECTED.items():
        schema_path = SCHEMA_DIR / filename
        schema = documents.get(schema_path.resolve()) or load(schema_path)
        declared = schema.get("properties", {}).get("schema", {}).get("const")
        if declared != contract_id:
            raise ValueError(f"{schema_path}: expected schema const {contract_id}, got {declared}")
        example_path = EXAMPLE_DIR / filename.replace(".v1.schema", ".example")
        example = load(example_path)
        if example.get("schema") != contract_id:
            raise ValueError(f"{example_path}: expected schema {contract_id}")
        missing = [key for key in schema.get("required", []) if key not in example]
        if missing:
            raise ValueError(f"{example_path}: missing required fields {missing}")
        examples.append((example_path, example, schema))

    validation_mode = "structural"
    try:
        from jsonschema import Draft202012Validator
        from referencing import Registry, Resource

        registry = Registry().with_resources(
            (document["$id"], Resource.from_contents(document))
            for document in documents.values()
            if isinstance(document.get("$id"), str)
        )
        for example_path, example, schema in examples:
            Draft202012Validator(schema, registry=registry).validate(example)
        validation_mode = "full JSON Schema"
    except ImportError:
        pass

    plan = load(EXAMPLE_DIR / "story-plan.example.json")
    approval = plan.get("approval", {})
    if plan.get("status") != "approved" or approval.get("status") != "approved":
        raise ValueError("approved Story Plan example must include an approved approval record")
    for key in ("approvedBy", "approvedAt", "approvalRef"):
        if not approval.get(key):
            raise ValueError(f"approved Story Plan is missing approval.{key}")

    print(f"STORY CONTRACTS OK ({len(EXPECTED)} contracts, {len(schema_ids)} schemas, {validation_mode})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"STORY CONTRACTS FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
