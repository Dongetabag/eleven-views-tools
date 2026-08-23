#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ElevenViewsBridge local CI: run everything that keeps the bridge contract,
# registry, schemas and signed-IPC policy honest. Portable (no macOS needed).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== registry drift check =="
python3 "$here/bridge_tool.py" check

echo "== schema validation (registry + examples) =="
python3 "$here/bridge_tool.py" validate

echo "== signed-IPC decision-table proof =="
python3 "$here/bridge_ipc_proof.py"

echo "All bridge checks passed."
