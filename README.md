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

Do not distribute a binary from this branch yet. Upstream-hosted sharing and feedback services are disabled with reserved `.invalid` endpoints. The remaining readiness work includes provisioning owned services if those features are enabled, completing the custom UI pass, validating every permission flow under the new bundle identity, and publishing matching source for every release.

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
