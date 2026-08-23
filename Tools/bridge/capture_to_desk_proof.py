#!/usr/bin/env python3
"""Portable Capture-to-Desk proof (ELE-3161 / ELE-3164).

Uploads a tiny PNG to a scoped Desk issue via the attachments API, then
verifies the stored sha256 matches the local file. This proves the Desk half
of the vertical slice from the desk/agent environment.

Env:
  PAPERCLIP_API_URL, PAPERCLIP_API_KEY, PAPERCLIP_COMPANY_ID
  CAPTURE_TO_DESK_ISSUE_ID (optional; defaults to PAPERCLIP_TASK_ID)

Usage:
  python3 Tools/bridge/capture_to_desk_proof.py
"""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def tiny_png() -> bytes:
    return bytes([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB4, 0x00, 0x00, 0x00,
        0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ])


def main() -> int:
    api = os.environ.get("PAPERCLIP_API_URL", "").rstrip("/")
    key = os.environ.get("PAPERCLIP_API_KEY", "")
    company = os.environ.get("PAPERCLIP_COMPANY_ID", "")
    issue = os.environ.get("CAPTURE_TO_DESK_ISSUE_ID") or os.environ.get("PAPERCLIP_TASK_ID", "")
    run = os.environ.get("PAPERCLIP_RUN_ID", "")
    if not all([api, key, company, issue]):
        print(
            "missing PAPERCLIP_API_URL, PAPERCLIP_API_KEY, PAPERCLIP_COMPANY_ID, issue id",
            file=sys.stderr,
        )
        return 2

    png = tiny_png()
    local_sha = hashlib.sha256(png).hexdigest()
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        f.write(png)
        path = f.name

    curl = [
        "curl", "-sS", "-X", "POST",
        f"{api}/api/companies/{company}/issues/{issue}/attachments",
        "-H", f"Authorization: Bearer {key}",
    ]
    if run:
        curl.extend(["-H", f"X-Paperclip-Run-Id: {run}"])
    curl.extend([
        "-F", f"file=@{path};type=image/png",
        "-F", "description=Capture-to-Desk bridge proof",
    ])
    out = subprocess.check_output(curl, text=True)
    uploaded = json.loads(out)
    att_id = uploaded.get("id")
    remote_sha = uploaded.get("sha256")
    if not att_id:
        print("upload missing id:", out, file=sys.stderr)
        return 1

    if remote_sha != local_sha:
        print(f"sha mismatch local={local_sha} remote={remote_sha}", file=sys.stderr)
        return 1

    receipt = {
        "schema": "elevenviews.bridge.receipt.v1",
        "capability": "share.attachCaptureToDesk",
        "outcome": "success",
        "artifacts": [{
            "kind": "json",
            "mimeType": "application/json",
            "inline": {
                "attachmentId": att_id,
                "issueId": issue,
                "sha256": remote_sha,
                "byteSize": uploaded.get("byteSize"),
            },
            "description": "Desk attachment created and sha256 verified on upload response.",
        }],
    }
    print(json.dumps(receipt, indent=2))
    print("OK capture-to-desk proof", att_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
