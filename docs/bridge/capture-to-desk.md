# Capture-to-Desk vertical slice

End-to-end path: **capture a screen region on the Mac → user approves via App Intent → upload to a scoped Desk issue → sha256 read-back on the upload response**.

| Layer | Component |
| --- | --- |
| Capture | `screen.captureRegion` → `ScreenCaptureRegionBridge` |
| Share | `share.attachCaptureToDesk` → `DeskAttachmentBridge` |
| Shortcut | `CaptureToDeskIntent` ("Capture to Desk") |
| Desk proof (agent) | `Tools/bridge/capture_to_desk_proof.py` |
| Examples | [`share-attachCaptureToDesk.request.json`](examples/share-attachCaptureToDesk.request.json), [`share-attachCaptureToDesk.receipt.json`](examples/share-attachCaptureToDesk.receipt.json) |

## Desk-side proof (no Mac required)

From any environment with Paperclip agent credentials:

```bash
export PAPERCLIP_API_URL="https://desk.elevenviews.io"
export PAPERCLIP_API_KEY="<scoped-run-jwt>"
export PAPERCLIP_COMPANY_ID="<company-id>"
export CAPTURE_TO_DESK_ISSUE_ID="<target-issue-id>"   # optional

python3 Tools/bridge/capture_to_desk_proof.py
```

Success prints `OK capture-to-desk proof <attachment-id>` and a JSON receipt with matching `sha256`.

## Mac E2E proof (M4 Max)

### 1. Build developer variant

```bash
git clone https://github.com/Dongetabag/eleven-views-tools.git
cd eleven-views-tools
git checkout codex/eleven-views-tools-foundation

./build.sh --dev --install
```

Developer build uses bundle id `io.elevenviews.tools.dev` so it coexists with the production app.

### 2. Grant permissions

Open **Eleven Views Tools (Developer)** once and approve Screen Recording when prompted (required for region capture).

### 3. Scoped Desk token

Use a short-lived scoped JWT for the **target issue** (same company + issue id you will attach to). Options:

- Paperclip agent run on that issue (`PAPERCLIP_API_KEY` from a heartbeat)
- Desk board UI if a user-scoped export exists for testing

You need:

- `companyId` — Eleven Views company UUID
- `issueId` — target issue UUID (e.g. [ELE-3156](https://desk.elevenviews.io/ELE/issues/ELE-3156))
- `accessToken` — Bearer JWT with attachment write on that issue
- `apiBaseURL` — `https://desk.elevenviews.io` (default)

### 4. Run the shortcut

**Spotlight / Shortcuts:** search **Capture to Desk** (Eleven Views Tools Developer).

Parameters:

| Field | Value |
| --- | --- |
| Desk company id | `<companyId>` |
| Desk issue id | `<issueId>` |
| Desk API token | `<accessToken>` |
| Desk API base URL | `https://desk.elevenviews.io` |

Flow: select screen region → intent runs capture → uploads PNG → dialog shows attachment id.

### 5. Verify on Desk

Open the target issue on Desk. Confirm:

- New PNG attachment appears in the thread
- File opens and matches the captured region
- (Optional) Compare sha256 from bridge receipt dialog / logs with attachment metadata if exposed in UI

### 6. Receipt expectations

Successful `share.attachCaptureToDesk` receipt:

- `outcome`: `success`
- `artifacts[0].inlineDeskAttachment.attachmentId` — Desk attachment UUID
- `artifacts[0].inlineDeskAttachment.sha256` — matches local file

## Security notes

- `share` scope always requires a local-user approval token (App Intent invocation counts).
- Only `io.elevenviews.desk` is on the trusted caller list for `share.attachCaptureToDesk` (signed IPC path).
- Tokens must be scoped to the destination issue; the bridge does not discover issues by itself.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `needs_approval` on capture | Missing approval token (should not happen from App Intent) |
| `desk_rejected` HTTP 401/403 | Token expired or wrong issue scope |
| `sha_mismatch` | Desk response corrupt; re-run; file disk vs upload mismatch |
| Empty capture file | Screen Recording permission not granted |
| Shortcut missing | Rebuild with `--dev --install`; check Shortcuts app library |

## Issues

- Implementation: [ELE-3164](/ELE/issues/ELE-3164) (Atlas lane, merged [PR #8](https://github.com/Dongetabag/eleven-views-tools/pull/8))
- Exit criteria parent: [ELE-3161](/ELE/issues/ELE-3161) (blocked on [ELE-3159](/ELE/issues/ELE-3159) board status)
- Program: [ELE-3156](/ELE/issues/ELE-3156)
