# Eleven Views Story Contracts

These contracts are the implementation boundary for the context-first Story system. They deliberately separate durable reviewed context from one project brief, the approved narrative plan, raw Tools capture, and the editable scene project.

## Schemas

| Contract | Purpose |
|---|---|
| `atlas.story-context.v1` | Reviewed brand, audience, messaging, claims, presenter, channel, terminology, and privacy context |
| `atlas.product-context.v1` | Versioned product truth with explicit release states |
| `atlas.presenter-profile.v1` | Approved real presenter identity and voice configuration without provider secrets |
| `story.brief.v1` | Per-project objective, audience, formats, channels, source material, presenter, and constraints |
| `story.plan.v1` | Reviewable narrative and output plan that must be approved before production |
| `tools.flow-capture.v1` | Owner-only real-product recording manifest with pointer, click, window, OCR, and privacy evidence |
| `story.scene-project.v1` | Multi-output editable scenes, narration, waveform, focus, interaction, captions, QA, render, and publish references |

## Invariants

1. Context is proposed and reviewed. Extraction is never durable truth by itself.
2. Product capabilities carry a release state. Planned and building work is not described as shipped.
3. Presenter profiles store provider identifiers and settings, never an API key.
4. A Story Plan must carry an approved approval record before narration generation or rendering begins.
5. Raw capture and audio assets are owner-only unless a human approves a narrower transfer.
6. Scene editing is direct. An agent is optional for reasoning-heavy revisions, not required for reorder or trim.
7. Performance events become observations and proposals. They do not mutate Story Context automatically.
8. Publishing creates a new version and receipt. It does not overwrite the prior version irreversibly.

Run `python3 Tools/story/check_story_contract.py` to parse every contract and verify the canonical identifiers and references.
