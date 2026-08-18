# AGENTS.md

Instructions for any AI coding agent (not just Claude Code — see [CLAUDE.md](CLAUDE.md) for tool-specific notes) working in this repository.

## Repository purpose

This is a personal engineering notebook for a dual-OS (Windows + Fedora) local LLM serving setup built around `llama.cpp`, running on integrated graphics with no discrete GPU. It doubles as an open-source reference for anyone doing local inference on similar hardware. Both purposes matter — see [Repository philosophy](#repository-philosophy) below.

Start with [README.md](README.md) for the overview, then [SETUP.md](SETUP.md) for hardware/flags/directory layout, and [docs/](docs/) for deeper topic-specific reference. Do not explore `llama.cpp/` or `models/` to understand this repo's own structure — they're upstream/binary content excluded from Git (see [docs/hardware.md](docs/hardware.md#why-models-and-llamacpp-arent-in-git)); only read `llama.cpp/AGENTS.md` when actually working inside that directory.

This repo also tracks `pi-config/` — reproducible, secret-free system config for the separate Raspberry Pi box (Quadlet units, nftables, Caddy, watchdog/arbiter scripts, a `provision.sh`). The Pi itself is still not part of this repo (it's a separate physical machine, documented in [docs/overall-setup.md](docs/overall-setup.md) because the two boxes are managed as one system) — only its config shape is tracked here. Never commit anything under `pi-config/` without grepping it for secrets first (WiFi PSK, API keys, tokens) — see [pi-config/README.md](pi-config/README.md) for exactly what's excluded and why.

## Coding conventions

- Shell scripts (`start-*.sh`) use `#!/usr/bin/env bash` and `exec` into the final process rather than wrapping it, so signals pass through cleanly.
- Comments in scripts explain *why* a flag or value was chosen, not what the flag does — the reasoning is the valuable part, since most of these values came from real debugging, not defaults. Preserve that style when editing.
- Prefer editing existing scripts/docs over creating new ones. New model launch scripts follow the existing `start-<model>.sh` naming pattern.

## Documentation standards

- **Don't fabricate.** No invented benchmark numbers, no invented screenshots, no invented conclusions in [docs/lessons-learned.md](docs/lessons-learned.md) or [docs/benchmarks.md](docs/benchmarks.md). If a value isn't measured, leave a `TODO` marker instead of guessing.
- **Prefer moving content over deleting it.** If a document gets too long, extract a section into `docs/` and link back to it rather than cutting the information.
- **Keep README.md short.** It's the entry point, not the reference. Implementation detail belongs in [SETUP.md](SETUP.md) or [docs/](docs/), linked from the README.
- Every document should link to the related documents a reader would need next (see the "Documentation" / cross-link sections in README.md and each docs/ file) — avoid writing content that duplicates another file instead of linking to it.

## How scripts should be modified

- Don't change functionality (flags, ports, models) without a reason documented in the comment above the change and a corresponding [JOURNAL.md](JOURNAL.md) entry — this repo's whole value is the record of *why*, not just the current state.
- If a flag's behavior differs between models or OSes (e.g. `--reasoning off`, `--mlock`), verify it doesn't silently break the other configuration before reusing it — several journal entries document exactly this kind of assumption not holding across models.
- Local patches to `llama.cpp/` source (see [docs/troubleshooting.md](docs/troubleshooting.md)) do not survive a `git pull`/rebuild. If you touch `llama.cpp/`, note in `JOURNAL.md` that a patch needs reapplying, and check `llama.cpp/AGENTS.md` for that repo's own contribution rules before proposing anything upstream.

## Testing expectations

There is no automated test suite — this is infrastructure/config, not a library. "Testing" here means:
- After changing a launch script, actually start the server and confirm `/health` returns `ok`.
- For a behavior change (sampling, reasoning flags, context size), replay the real client's request shape (Open WebUI's actual JSON body, not a simplified curl call) before declaring it fixed — multiple bugs in this repo's history looked fixed under a simplified test and weren't. See [docs/troubleshooting.md](docs/troubleshooting.md) for examples.
- For anything affecting GPU offload or memory footprint, check process RSS after a real generation as a sanity check (low RSS = GPU-resident, as documented in [docs/benchmarks.md](docs/benchmarks.md)).

## Documentation update rules

- Append new entries to the **top** of [JOURNAL.md](JOURNAL.md) (newest first) whenever you make a change or resolve an issue — this is the one file that should never shrink.
- If a journal entry describes a bug with a clear Problem/Cause/Solution/Verification shape, consider also adding a structured entry to [docs/troubleshooting.md](docs/troubleshooting.md) — the journal is the narrative record, troubleshooting.md is the lookup reference.
- If a change affects hardware assumptions, flags, or model status, update [SETUP.md](SETUP.md) too — it should always reflect the current state, unlike the journal which is a historical log.
- Completed roadmap work moves out of [docs/roadmap.md](docs/roadmap.md)'s "Upcoming" section (checked off or removed), not just left stale.

## Repository philosophy

This repo is simultaneously:
1. **A personal engineering notebook** — the journal's honesty about dead ends, wrong guesses, and unresolved bugs is a feature, not noise to clean up. Don't sanitize JOURNAL.md into a highlight reel.
2. **An open-source reference** — someone else running local inference on similar (no-discrete-GPU, RAM-constrained) hardware should be able to use this repo's documented issues and fixes without reading the whole history.

When these pull in different directions, keep the journal's detail intact and put the polished, scannable version in `docs/` — don't compromise one document to serve both purposes.
