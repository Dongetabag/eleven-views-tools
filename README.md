# Eleven Views Tools

Eleven Views Tools is a local-first macOS menu bar toolkit being adapted for the Eleven Views software ecosystem. It combines everyday Mac controls, capture tools, window management, audio utilities, system monitoring, clipboard workflows, and automation in one native Swift app.

This repository is an independent fork of [vorssaint/vorssaint-utils](https://github.com/vorssaint/vorssaint-utils). It is not an official Vorssaint release and is not endorsed by the upstream maintainer.

## Fork status

The foundation pass is in progress:

- Product name changed to Eleven Views Tools
- Bundle identity changed to `io.elevenviews.tools`
- GitHub update source changed to `Dongetabag/eleven-views-tools`
- Eleven Views artwork replaces the upstream app artwork
- Original GPL license and upstream copyright notices are preserved
- Eleven Views integration seams are documented in [FORK_PLAN.md](FORK_PLAN.md)

Client distribution is supported when each build is accompanied by access to its matching GPL source. Screenshot and recording link uploads ship off until an Eleven Views-owned service is provisioned. Feedback opens a visible Mail draft addressed to `dev@elevenviews.io`, and product links lead to [elevenviews.io](https://elevenviews.io).

## Product direction

Tools is organized around customer outcomes instead of an undifferentiated feature catalog: Capture, Workspace, Create, Meeting, Mac Health, Ask Atlas, and Advanced Tools. The complete 53-feature assignment is documented in [TOOLS_OUTCOME_MAP.md](docs/product/TOOLS_OUTCOME_MAP.md) and enforced by an exhaustive Swift mapping.

The context-first Story foundation turns a real Tools workflow capture into a reviewed Story Brief, approved Story Plan, editable Scene Project, and versioned output. The product specification is [CONTEXT_FIRST_STORY_SYSTEM.md](docs/product/CONTEXT_FIRST_STORY_SYSTEM.md); versioned schemas and examples live in [docs/story](docs/story/README.md).

## Build locally

Requirements:

- Apple Silicon Mac
- macOS 14 or newer
- Xcode Command Line Tools

```sh
./build.sh --test
./build.sh --dev
```

The development build is staged at `build/stage/Eleven Views Tools (Developer).app`. Installation into `/Applications` is intentionally a separate explicit action:

```sh
./build.sh --dev --install
```

## Commercial model

GPL software may be sold. Eleven Views can charge for packaged releases, installation, configuration, support, managed integrations, and companion services. Anyone who receives a distributed build must also receive, or be able to obtain, its corresponding source under GPL-3.0-or-later. The covered app cannot be converted into closed-source proprietary software without a separate license from every relevant copyright holder.

## License and attribution

This fork remains licensed under [GPL-3.0-or-later](LICENSE).

Original work copyright © 2026 Vorssaint contributors. Eleven Views changes are identified in the repository history and [FORK_PLAN.md](FORK_PLAN.md). The Vorssaint name, icon, and trade dress are not used for this fork’s product identity.

Product support: [dev@elevenviews.io](mailto:dev@elevenviews.io) · [elevenviews.io](https://elevenviews.io)
