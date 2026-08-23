#!/usr/bin/env python3
"""Desk attachments API proof (ELE-3164 / Capture-to-Desk).

Portable end-to-end proof that the Paperclip Desk attachments API accepts a
multipart upload, returns structured metadata (id, sha256, byteSize), and that
the uploaded bytes can be read back and verified.

Environment (auto-injected on Desk heartbeats):
  PAPERCLIP_API_URL
  PAPERCLIP_API_KEY          Bearer JWT for the run/agent
  PAPERCLIP_COMPANY_ID
  PAPERCLIP_TASK_ID          Target issue UUID
  PAPERCLIP_RUN_ID           Optional; sent as X-Paperclip-Run-Id on upload

Read-back uses:
  POST /api/companies/{companyId}/issues/{issueId}/attachments
  GET  /api/attachments/{attachmentId}/content

The issue attachments list route may be empty on some builds; this proof verifies
via the upload response plus a content download SHA-256 match.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import sys
import urllib.error
import urllib.request
import zlib
from pathlib import Path


def minimal_png() -> bytes:
    """1×1 PNG — tiny, valid, deterministic."""
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    ihdr_chunk = b"IHDR" + ihdr
    ihdr_crc = struct.pack(">I", zlib.crc32(ihdr_chunk) & 0xFFFFFFFF)
    raw = b"\x00" + bytes([255, 0, 0])
    comp = zlib.compress(raw)
    idat_chunk = b"IDAT" + comp
    idat_crc = struct.pack(">I", zlib.crc32(idat_chunk) & 0xFFFFFFFF)
    iend_chunk = b"IEND"
    iend_crc = struct.pack(">I", zlib.crc32(iend_chunk) & 0xFFFFFFFF)
    return (
        sig
        + struct.pack(">I", len(ihdr))
        + ihdr_chunk
        + ihdr_crc
        + struct.pack(">I", len(comp))
        + idat_chunk
        + idat_crc
        + struct.pack(">I", 0)
        + iend_chunk
        + iend_crc
    )


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def multipart_body(fields: dict[str, str], file_field: str, filename: str,
                   content: bytes, content_type: str) -> tuple[bytes, str]:
    boundary = f"----ElevenViewsBridge{hashlib.sha256(content).hexdigest()[:16]}"
    parts: list[bytes] = []
    for name, value in fields.items():
        parts.append(
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
            f"{value}\r\n".encode()
        )
    parts.append(
        (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{file_field}"; filename="{filename}"\r\n'
            f"Content-Type: {content_type}\r\n\r\n"
        ).encode()
        + content
        + b"\r\n"
    )
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)
    return body, f"multipart/form-data; boundary={boundary}"


def request_json(method: str, url: str, token: str, *,
                 body: bytes | None = None,
                 content_type: str | None = None,
                 run_id: str | None = None) -> dict:
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": "ElevenViewsBridge/desk-attachments-proof",
    }
    if content_type:
        headers["Content-Type"] = content_type
    if run_id:
        headers["X-Paperclip-Run-Id"] = run_id
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {url} -> HTTP {exc.code}: {detail}") from exc
    if not raw:
        return {}
    return json.loads(raw.decode("utf-8"))


def download_bytes(url: str, token: str) -> bytes:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}",
                                               "User-Agent": "ElevenViewsBridge/desk-attachments-proof"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GET {url} -> HTTP {exc.code}: {detail}") from exc


def run_proof(*, api_url: str, api_key: str, company_id: str, issue_id: str,
              run_id: str | None, emit_dir: Path | None) -> int:
    png = minimal_png()
    digest = sha256_hex(png)
    filename = "desk-attachments-proof.png"

    upload_url = f"{api_url.rstrip('/')}/api/companies/{company_id}/issues/{issue_id}/attachments"
    body, ctype = multipart_body({}, "file", filename, png, "image/png")
    uploaded = request_json("POST", upload_url, api_key, body=body,
                            content_type=ctype, run_id=run_id)

    attachment_id = uploaded.get("id")
    response_sha = uploaded.get("sha256")
    byte_size = uploaded.get("byteSize")
    content_path = uploaded.get("contentPath")

    checks: list[tuple[str, bool, str]] = []
    checks.append(("upload returned id", bool(attachment_id), str(attachment_id)))
    checks.append(("upload sha256 matches payload", response_sha == digest, response_sha or ""))
    checks.append(("upload byteSize matches payload", byte_size == len(png), str(byte_size)))
    checks.append(("upload contentPath present", bool(content_path), str(content_path)))

    readback_url = f"{api_url.rstrip('/')}{content_path}" if content_path else None
    readback_ok = False
    readback_sha = ""
    if readback_url:
        readback = download_bytes(readback_url, api_key)
        readback_sha = sha256_hex(readback)
        readback_ok = readback_sha == digest
    checks.append(("content read-back sha256 matches", readback_ok, readback_sha))

    evidence = {
        "proof": "desk.attachments.v1",
        "issueId": issue_id,
        "companyId": company_id,
        "upload": uploaded,
        "expectedSha256": digest,
        "readBackSha256": readback_sha,
        "checks": [{"name": n, "pass": ok, "detail": d} for n, ok, d in checks],
    }

    if emit_dir:
        emit_dir.mkdir(parents=True, exist_ok=True)
        (emit_dir / "desk-attachments-proof.json").write_text(
            json.dumps(evidence, indent=2) + "\n"
        )

    print(f"Desk attachments proof — issue {issue_id}")
    print(f"{'check':<40} {'result'}")
    print("-" * 52)
    failures = 0
    for name, ok, detail in checks:
        if not ok:
            failures += 1
        print(f"{name:<40} {'PASS' if ok else 'FAIL'}  {detail}")

    if failures:
        print(f"\n{failures} check(s) FAILED.", file=sys.stderr)
        return 1
    print("\nAll checks passed: upload metadata + read-back SHA-256 verified.")
    return 0


def env_or(name: str, default: str | None = None) -> str | None:
    value = os.environ.get(name, default)
    return value if value else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--api-url", default=env_or("PAPERCLIP_API_URL"))
    parser.add_argument("--api-key", default=env_or("PAPERCLIP_API_KEY"))
    parser.add_argument("--company-id", default=env_or("PAPERCLIP_COMPANY_ID"))
    parser.add_argument("--issue-id", default=env_or("PAPERCLIP_TASK_ID"))
    parser.add_argument("--run-id", default=env_or("PAPERCLIP_RUN_ID"))
    parser.add_argument("--emit", metavar="DIR", type=Path, default=None,
                        help="write evidence JSON to DIR")
    parser.add_argument("--skip-if-unconfigured", action="store_true",
                        help="exit 0 when required env vars are missing (for optional CI)")
    args = parser.parse_args()

    missing = [n for n, v in [
        ("api-url", args.api_url),
        ("api-key", args.api_key),
        ("company-id", args.company_id),
        ("issue-id", args.issue_id),
    ] if not v]
    if missing:
        msg = "Missing required configuration: " + ", ".join(missing)
        if args.skip_if_unconfigured:
            print(f"SKIP: {msg}")
            return 0
        print(f"ERROR: {msg}", file=sys.stderr)
        return 2

    return run_proof(
        api_url=args.api_url,
        api_key=args.api_key,
        company_id=args.company_id,
        issue_id=args.issue_id,
        run_id=args.run_id,
        emit_dir=args.emit,
    )


if __name__ == "__main__":
    raise SystemExit(main())
