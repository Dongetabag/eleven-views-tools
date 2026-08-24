# Capture-to-Desk vertical slice

The first client-safe path is intentionally two visible actions:

```text
Capture Screen Region
  → local owner-only PNG
  → review or redact locally
  → Attach File to Desk Issue
  → native confirmation
  → scoped upload
  → content download + byte-count/SHA-256 verification
  → receipt
```

Capture and external sharing remain separate until Eleven Views Tools has a
foreground preview that can show the exact image and Desk destination before
one combined approval.

| Layer | Component |
| --- | --- |
| Capture | `screen.captureRegion` → `ScreenCaptureRegionBridge` |
| Share | `share.attachToDeskIssue` → `AttachToDeskIssueBridge` |
| Shortcuts | `CaptureScreenRegionIntent`, then `AttachToDeskIssueIntent` |
| Desk proof | `Tools/bridge/desk_attachments_proof.py` |
| Keychain setup | `Tools/bridge/configure_desk_bridge.sh` |

## Desk-side proof

From a Desk agent run with scoped credentials:

```bash
python3 Tools/bridge/desk_attachments_proof.py
```

The proof uploads a deterministic PNG, checks the attachment metadata, downloads
the stored content, and fails unless its SHA-256 still matches.

## Mac setup

### 1. Build the developer variant

```bash
git clone https://github.com/Dongetabag/eleven-views-tools.git
cd eleven-views-tools
git checkout codex/eleven-views-tools-foundation
./build.sh --dev --install
```

The developer build uses `io.elevenviews.tools.dev`, so it can coexist with the
release app.

### 2. Grant Screen Recording

Open Eleven Views Tools (Developer), then grant Screen Recording when macOS asks.

### 3. Pair one Desk company

```bash
Tools/bridge/configure_desk_bridge.sh configure
```

Enter the Desk company UUID. The final macOS Keychain prompt accepts the scoped
Desk token without placing it in shell history, process arguments, a Shortcut,
or an Application Support file. Bridge v1 supports one active company pairing.

### 4. Capture locally

Run **Capture Screen Region** from Shortcuts or Spotlight. Confirm the native
privacy prompt, select the region, then inspect or redact the saved PNG.

### 5. Attach after review

Run **Attach File to Desk Issue**. Supply:

- the Desk issue identifier, such as `ELE-3164`, or its UUID;
- the reviewed local file path.

Confirm the native share prompt. Success is reported only after Desk returns the
attachment and the app downloads it again to verify the exact byte count and
SHA-256.

## Security boundaries

- Capture requires a fresh native confirmation before pixels are read.
- Sharing requires a second native confirmation before bytes leave the Mac.
- Release builds can contact only `https://desk.elevenviews.io` and refuse
  cross-origin redirects.
- The Desk token is stored in macOS Keychain.
- Files are limited to 25 MB. Empty files, symlinks, and malformed issue IDs are
  rejected.
- Multipart filenames are sanitized before transmission.
- Desk remains the only trusted signed caller for the share capability. The
  proof harness is explicitly forbidden.

## One-click workflow gate

A future **Capture to Desk** composite intent may combine these steps only after
the app provides a foreground preview containing the exact capture, destination
company, destination issue, and upload action. The preview must be followed by a
fresh user confirmation. Tokens must never be App Intent parameters.

## Related work

- Desk lane: `ELE-3164`
- Phase 1 exit criteria: `ELE-3161`
- Program: `ELE-3156`
