# Eleven Views Tools fork plan

Fork modification work began on 2026-08-23. This file is the prominent modification notice for Eleven Views changes to the upstream GPL work.

## Product direction

Eleven Views Tools should be the native Mac utility layer for the Eleven Views ecosystem. The local app remains useful without an account. Optional integrations connect approved actions and summaries to Eleven Views Hub, Audio, Flow, Desk, and Atlas.

## Licensing boundary

The upstream code is GPL-3.0-or-later. Selling the app is allowed, but every distributed derivative build must remain under the GPL and provide corresponding source. Original notices remain intact. Modified releases must be marked as modified and must not use the upstream name, icon, bundle identity, signing identity, update feed, or trade dress.

## Identity checklist

- [x] Repository: `Dongetabag/eleven-views-tools`
- [x] Product name: Eleven Views Tools
- [x] Bundle ID: `io.elevenviews.tools`
- [x] Executable names: `ElevenViewsTools` and `ElevenViewsToolsDeveloper`
- [x] Fan helper namespace: `io.elevenviews.tools.fan-control`
- [x] Update repository: `Dongetabag/eleven-views-tools`
- [x] Eleven Views app artwork
- [ ] Eleven Views signing and notarization identity
- [ ] Eleven Views release feed and signed release process
- [ ] Custom graphite and blue UI throughout settings, onboarding, and menu panels
- [x] Disable every upstream-hosted sharing endpoint and route feedback to `dev@elevenviews.io`
- [ ] Permission and migration QA under the new bundle identity

## Integration architecture

Keep integrations optional and local-first. A small `ElevenViewsBridge` service should expose a versioned local contract instead of coupling feature code directly to another app.

Proposed actions:

- Open Eleven Views Hub, Audio, Flow, or Desk through deep links
- Send a user-approved file or capture to Audio or Hub
- Publish local health summaries to the Hub manifest
- Run approved Atlas actions from the command bar
- Return evidence receipts after an integration action completes

Proposed local envelope:

```json
{
  "schema": "elevenviews.tools.action.v1",
  "action": "open|share|run|status",
  "target": "hub|audio|flow|desk|atlas",
  "payload": {},
  "requestedAt": "ISO-8601",
  "approval": "local-user-action"
}
```

No file contents, clipboard contents, recordings, or credentials should leave the Mac without a visible user action and a destination preview. Screenshot and recording sharing have no production endpoint and remain off until an Eleven Views service is explicitly provisioned and reviewed. In-app feedback opens a visible email draft to `dev@elevenviews.io`; the app sends nothing on its own.

## Release gates

1. Unit tests pass.
2. Development bundle builds and signs.
3. No visible upstream product branding remains.
4. No upstream service endpoint receives fork data.
5. Every requested permission explains the Eleven Views Tools feature that needs it.
6. The published source tag matches the distributed binary version.
7. GPL, attribution, privacy, and source links are present in the app and release page.
