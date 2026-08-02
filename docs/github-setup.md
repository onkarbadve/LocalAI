# GitHub Repository Setup

A checklist of the GitHub configuration that lives in repository settings, not in files — so it doesn't get lost between this repo and any future one. None of this affects how the setup runs; it only affects how the repository presents itself on GitHub. Everything here is done once via the GitHub web UI (Settings tab), not via a script.

## Repository description

The one-line summary shown under the repo name on GitHub and in search results. Keep it in sync with the README's tagline so the two never drift:

> Dual-OS (Windows + Fedora) local LLM serving, built around llama.cpp — no discrete GPU, just an Intel iGPU and Vulkan.

Set under **Settings → General → Description** (or the pencil icon next to the description on the repo home page).

## Repository topics

Topics drive GitHub's discovery/search — add them under the gear icon next to "About" on the repo home page. Suggested set, based on what this repo actually documents:

`llama-cpp` `local-llm` `vulkan` `intel-iris-xe` `igpu` `open-webui` `self-hosted` `tailscale` `fedora` `podman` `local-inference` `on-device-ai`

Prefer existing, already-searched-for topics over inventing new ones — check what similar repos use before adding a topic that has zero other adopters.

## Social preview

The image shown when this repo's link is shared (Slack, Twitter/X, Discord, etc.). Set under **Settings → General → Social preview**. GitHub's recommended size is 1280×640px. The architecture diagram ([`docs/images/architecture.png`](images/architecture.png)) or a real captured screenshot from [`docs/images/`](images/) (once populated, see [`docs/images/README.md`](images/README.md)) are the two natural candidates — pick whichever is legible at thumbnail size, since the diagram has more small text.

## Homepage URL

The link shown next to the description on the repo home page, set in the same **About** panel as topics. This repo has no hosted deployment (it documents a personal, single-machine setup), so leave it unset or point it at the published LinkedIn write-up if a public link is wanted.

## Release strategy

There's no packaged artifact here — no binary, no library, nothing to version-pin a downstream consumer against. [`CHANGELOG.md`](../CHANGELOG.md) already tracks milestones as rough, non-semver versions (v1.0–v1.4). Two options if GitHub Releases are wanted anyway, purely for visibility:

- **Tag milestone commits** matching the `CHANGELOG.md` versions (e.g. `v1.4`) and publish a GitHub Release per tag, with the corresponding changelog section pasted into the release notes.
- **Skip Releases entirely** and treat `CHANGELOG.md` + `JOURNAL.md` as the version history, since that's already true today and Releases would just duplicate it.

Given this repo's philosophy (a running notebook, not a product), skipping Releases is the lower-maintenance default — only start tagging if a specific need comes up (e.g. linking a stable reference point from an external write-up).

## Branch protection (optional)

Not currently load-bearing for a single-maintainer repo, but worth enabling if collaborators are ever added:

- Require pull requests before merging to `main` (no direct pushes).
- Require the docs-lint workflow (see [.github/workflows/](../.github/workflows/)) to pass before merging.
- Do **not** require approvals from a nonexistent second maintainer — that would just lock the repo, not add safety.

Set under **Settings → Branches → Branch protection rules**.

## Discussions (optional)

GitHub Discussions (Settings → General → Features → Discussions) is a reasonable home for open-ended questions ("does this work on an AMD iGPU?") that don't fit the Issues templates in [`.github/ISSUE_TEMPLATE/`](../.github/ISSUE_TEMPLATE/) (bug reports, doc fixes, feature requests all assume something concrete to act on). Not enabled by default here — a personal-notebook repo with low traffic doesn't need a second channel alongside Issues until there's evidence people are actually asking open-ended questions.

## Related documents

- [CONTRIBUTING.md](../CONTRIBUTING.md) — the workflow contributors follow once the repo is configured
- [CHANGELOG.md](../CHANGELOG.md) — the version history a release strategy would draw from
- [README.md](../README.md) — the description/topics above should stay consistent with this
- [.github/workflows/](../.github/workflows/) — the CI check branch protection would gate on
