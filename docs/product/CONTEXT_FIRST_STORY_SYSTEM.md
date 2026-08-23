# Eleven Views Context-First Story System

Status: Foundation specification
Owner: Eleven Views
Primary surfaces: Atlas, Eleven Views Tools, Desk, Eleven Views Audio, Story Studio
Contract version: v1

## 1. Problem statement

People repeatedly explain the same company, product, audience, claims, visual rules, presenter choices, and privacy boundaries every time they create a demo or tutorial. Generic generation then invents details, presents planned work as released, and produces disconnected files that become stale when the product changes.

Eleven Views needs a governed production system that understands durable company truth, captures the real product, plans the story before generation, keeps editing immediate, and publishes versioned assets with evidence. The system must create useful output from one real workflow without turning Tools into a professional video editor or giving an agent unrestricted Mac access.

## 2. Product principle

Atlas knows what is true. A Story Brief defines what is being made. A Story Plan defines how the story will be told. Specialized workers build it. A human approves consequential decisions. Tools and product signals keep the result current.

The foundational separation is:

```text
Company and client context
          ↓
Product context
          ↓
Story context
          ↓
Story brief
          ↓
Story plan
          ↓
Explicit approval
          ↓
Scene project
          ↓
Versioned story asset
```

Context, brief, plan, source artifacts, rendered outputs, and observations are different objects. None may silently overwrite another.

## 3. Goals

### User goals

1. Reduce the time from a completed product workflow to a reviewable 16:9 demo draft to less than 15 minutes for the first vertical slice.
2. Let a creator approve or correct every durable claim, product state, visual rule, presenter setting, and privacy rule before generation.
3. Turn one Tools capture into a reusable scene project that can produce a landscape video and a vertical derivative without recapturing the workflow.
4. Preserve immediate manual editing for scene order, trim, copy, narration, focus area, presenter visibility, and output settings.
5. Make every published asset traceable to its context version, product version, source capture, approval, render, and publish receipt.

### Business goals

1. Make Tools valuable as a free Mac utility while creating a clear upgrade into governed Desk and Atlas workflows.
2. Establish Story Context as a reusable company asset across product demos, websites, onboarding, support, proposals, sales, and social content.
3. Create a multi-output production system whose marginal cost falls as approved context, flows, presenter profiles, and scene templates accumulate.

## 4. Non-goals for v1

1. Generic text-to-video. The first release is grounded in actual product capture.
2. Synthetic talking heads or lip synchronization. Presenter identity uses an approved real photo, narration, and a waveform.
3. Customer-specific foundation-model training. v1 uses structured context, retrieval, templates, and generation-time conditioning.
4. A full nonlinear video editor. Advanced timing can exist, but the default editing model is scenes and steps.
5. Interactive branching, public embeds, analytics, and automatic product recapture. The data model must support them, but they follow the video vertical slice.
6. Automatic mutation of durable context from performance data. Outcomes may generate proposals only.
7. Automatic publishing or external transfer without named human approval.

## 5. System responsibilities

| System | Responsibility |
|---|---|
| Atlas | Resolve company, client, product, audience, messaging, approved claims, proof, presenter, channel, and privacy context |
| Tools | Capture real screens, windows, pointer movement, clicks, timing, OCR, recordings, and owner-only local artifacts |
| Desk | Run production tasks, approvals, worker stages, artifact review, status, verification, and receipts |
| Audio | Normalize narration, create WAV derivatives, calculate waveform data, and apply approved voice and sound presets |
| Story Studio | Edit scenes, render outputs, maintain versions, and later publish interactive assets |
| ElevenLabs | Generate narration for an approved Presenter Profile through a managed secret |
| Website and client portal | Display approved versioned story assets and later interactive experiences |

## 6. Canonical objects

The v1 contracts live in `docs/story/schemas`.

| Object | Question | Lifetime |
|---|---|---|
| `atlas.product-context.v1` | What product and released workflow are we showing? | Versioned by product state |
| `atlas.presenter-profile.v1` | Who is narrating and how should they sound and appear? | Long-lived and versioned |
| `atlas.story-context.v1` | How should this organization and product be represented? | Long-lived and reviewed |
| `story.brief.v1` | What are we making right now, for whom, and why? | One project request |
| `story.plan.v1` | How will this asset tell the story? | One approved generation or revision |
| `story.scene-project.v1` | What sources, scenes, narration, interactions, and outputs compose the editable project? | Versioned working project |

Every durable claim and important context field must carry source provenance, verification time, confidence, approval state, and whether it was observed or inferred.

Product capabilities must distinguish `released`, `beta`, `internal`, `building`, `planned`, and `deprecated`. Only released or explicitly approved beta functionality may appear as currently available in external content.

## 7. Context inheritance

```text
Eleven Views global
        ↓
Company
        ↓
Client
        ↓
Product
        ↓
Campaign or channel
        ↓
Story project
        ↓
Scene override
```

Lower scopes may override an inherited value only when the project records the override and its source. A scene override changes that scene, not durable company context.

## 8. First-run context intake

1. Enter a company website.
2. Atlas proposes identity, visual roles, typography roles, recurring messages, product pages, screenshots, calls to action, and writing patterns.
3. The person approves, edits, or removes every proposed card.
4. The person connects product sources such as product documentation, GitHub, Figma, Desk, Drive, files, or a Tools recording.
5. Atlas resolves product capabilities and their release states. The person reviews them.
6. Atlas proposes audiences, problems, outcomes, objections, terminology, approved messages, prohibited messages, and evidence.
7. The person creates a Presenter Profile with a real photo and recorded, uploaded, or ElevenLabs narration settings.
8. The person reviews privacy rules and screens or data that may not be shown.
9. The system creates an approved Story Context version. Later changes create a new version.

Extraction never becomes durable truth without review.

## 9. Primary vertical slice

The first engineering milestone is one complete loop:

```text
Select Desk and a released workflow
        ↓
Record the flow with Tools
        ↓
Create an owner-only FlowCapture
        ↓
Resolve approved Story Context
        ↓
Propose a Story Brief and Story Plan
        ↓
Human approves the plan
        ↓
Create scenes from the real capture
        ↓
Place automatic click focus and zooms
        ↓
Generate or attach narration
        ↓
Normalize WAV and calculate waveform
        ↓
Add presenter photo, captions, and approved sounds
        ↓
Run fact, privacy, brand, and render QA
        ↓
Human reviews
        ↓
Render 16:9 and 9:16 outputs
        ↓
Create a versioned Story Asset receipt
```

## 10. User stories

1. As a product creator, I want to teach Eleven Views my brand and product once so that future projects start with reviewed context instead of a blank prompt.
2. As a product owner, I want every capability labeled by release state so that planned functionality is never presented as shipped.
3. As a creator, I want to record a real workflow in Tools so that the generated story uses the actual product interface.
4. As a creator, I want to review a Story Plan before generation so that I can correct the narrative before time and compute are spent.
5. As a creator, I want direct scene editing so that small changes do not require an agent run.
6. As a presenter, I want an approved profile photo and voice configuration reused consistently so that every asset sounds and looks like us.
7. As a reviewer, I want private information flagged before rendering so that client data does not leak into content.
8. As an operator, I want every stage to leave an artifact or receipt so that Desk can show what happened and what requires approval.
9. As a future viewer, I want the same story to support interactive steps so that I can learn by doing rather than only watching.

## 11. Requirements

### P0: foundation and first vertical slice

- Versioned JSON contracts for Story Context, Product Context, Presenter Profile, Story Brief, Story Plan, and Scene Project.
- Provenance and approval state for claims, proof, product state, and important inferred context.
- A FlowCapture manifest containing capture time, app and window identity where available, display dimensions, video, pointer samples, click events, scene candidates, OCR references, source product version, and privacy classification.
- Owner-only storage for raw captures and narration assets.
- Story Plan approval before scene generation.
- A scene editor with direct reorder, trim, narration text, focus area, presenter visibility, caption, and duration controls.
- Recorded voice, uploaded WAV, or ElevenLabs narration through a managed secret.
- WAV normalization and waveform-envelope generation through Eleven Views Audio.
- Automatic focus and zoom candidates derived from recorded clicks. Every candidate remains editable.
- Fact, product-state, brand, privacy, clipping, and missing-source QA.
- Deterministic 16:9 and 9:16 rendering from the same scene project.
- Draft, approved, rendered, and published version identities with rollback-safe manifests.
- Desk receipts for context resolution, plan approval, source assets, audio, QA, render, and publish state.

### P1: multi-output production

- Captions, small approved SFX library, music presets, and automatic ducking.
- GIF, documentation, and step-guide outputs from the same scenes.
- Channel templates for website, LinkedIn, Shorts, onboarding, support, and sales.
- Reusable Story Context inheritance for company, client, product, campaign, project, and scene scopes.
- Context-diff review when Atlas proposes updates from a website or connected source.

### P2: interactive and live content

- Hotspots, click-to-continue, chapters, branching, variables, forms, and calls to action.
- Stable embed asset IDs with draft and published versions.
- Viewer events, branch intent, completion, replay, drop-off, and conversion observations.
- Product dependency tracking, staleness detection, partial recapture, partial regeneration, and reviewed push updates.
- Outcome-led strategy proposals. Observations never silently rewrite durable context.

## 12. Production state machine

```text
CONTEXT_RESOLVED
       ↓
BRIEF_READY
       ↓
PLAN_READY
       ↓
PLAN_APPROVED
       ↓
ASSETS_READY
       ↓
SCENES_READY
       ↓
AUDIO_READY
       ↓
QA_READY
       ↓
REVIEW_READY
       ↓
APPROVED
       ↓
RENDERED
       ↓
PUBLISHED
       ↓
MONITORING
```

A failed stage keeps its inputs and evidence. An external write is never retried silently. Any consequential edit after approval invalidates that approval.

## 13. Acceptance criteria for milestone one

- Given reviewed company and product context, when a creator starts a project, then the brief resolves the approved audience, claims, presenter, product version, and channel rules without asking for them again.
- Given a Tools workflow recording, when flow interpretation completes, then the system proposes ordered scenes and click-based focus regions without inventing product UI.
- Given a draft Story Plan, when the creator has not approved it, then no narration generation or render begins.
- Given an approved plan, when production completes, then the same Scene Project renders a 16:9 master and a 9:16 derivative.
- Given Accessibility is unavailable, when a capture contains click timing but not key timing, then production continues and identifies the missing enrichment without blocking recording.
- Given a screen contains a configured sensitive-data pattern, when QA runs, then publishing is blocked until the finding is redacted or explicitly resolved.
- Given a rendered asset, when the receipt is inspected, then it identifies the context, product, capture, plan, scene project, audio, QA, render, and approver versions.
- Given a scene reorder or trim, when the creator applies the edit, then the change occurs immediately without invoking an agent.

## 14. Success metrics

| Metric | Success threshold | Stretch target | Evaluation |
|---|---:|---:|---|
| First capture to reviewable draft | 15 minutes or less | 8 minutes or less | First 20 internal projects |
| Plan approval before generation | 95% of projects | 100% | First 30 days |
| Product-state or unsupported-claim escapes | 0 | 0 | Continuous QA |
| Projects rendered to two aspect ratios | 80% | 95% | First 30 days |
| Manual correction time after first draft | Under 10 minutes | Under 5 minutes | First 20 internal projects |
| Context reused without re-entry | 70% of durable fields | 90% | First 30 days |
| Private-data publishing incidents | 0 | 0 | Continuous |

## 15. Open questions

### Blocking before implementation of rendering

1. Design: Does Story Studio begin as a Tools window or as a shared Eleven Views workspace surface that Tools opens?
2. Engineering: Which local media framework becomes the deterministic renderer, and what project format remains portable across macOS versions?
3. Security: Which fields may be sent to external generation providers, and which must remain local or be explicitly approved per request?
4. Product: Which real Desk workflow is the first golden-flow test and which released build is its source of truth?

### Non-blocking during foundation work

1. Data: Which analytics provider will hold interactive events before the Eleven Views event service exists?
2. Design: Which presenter presets ship after Minimal and Founder?
3. Product: Should Scene Project be the public product term or remain an internal model?

## 16. Delivery phases

1. Foundation: outcome-based Tools taxonomy, versioned schemas, examples, provenance rules, and Desk task graph.
2. Capture: dependable recording, FlowCapture manifest, click and pointer events, scene candidates, OCR, and privacy preflight.
3. Story: context resolver, brief, plan, approval, scene project, and direct scene editing.
4. Audio and render: presenter profile, narration, WAV pipeline, waveform, captions, zooms, SFX, 16:9, and 9:16.
5. Multi-output: GIF, documentation, help guide, and reusable channel templates.
6. Interactive: hotspots, branches, variables, forms, embeds, and observations.
7. Maintenance: source dependencies, staleness, partial recapture, reviewed updates, stable asset IDs, and rollback.
