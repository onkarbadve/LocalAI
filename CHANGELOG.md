# Changelog

Version history of this repository and the setup it documents. This is a summary view — [JOURNAL.md](JOURNAL.md) is the detailed, dated source of truth; [adr/](adr/) explains the reasoning behind the decisions that stuck. Entries are grouped into rough milestones, not formal semver releases (there's no package here to version) — the numbers exist to give a sense of order and progress.

## v1.5 — Repository polish and CI (2026-07-31)

- README: tightened "Features" into "Key Takeaways" and "Repository Structure" into "Repository at a Glance" (added a quick-facts table) for first-screen scannability.
- Added `docs/compatibility.md` (tested OS/tool versions) and `docs/github-setup.md` (manual GitHub configuration checklist).
- Added a static PNG export of the architecture diagram (`docs/images/architecture.png`) alongside the existing Mermaid source.
- Added `.github/workflows/docs-lint.yml` — markdown formatting and link checks, no build/test steps — plus minimal issue templates (`.github/ISSUE_TEMPLATE/`).
- Terminology and cross-link consistency pass across every markdown file; no functional or technical content changed.

## v1.4 — Documentation overhaul (2026-07-30 onward)

- Restructured `README.md` around overview / features / architecture / quick start / repo structure / screenshots / benchmarks / documentation / roadmap.
- Added `docs/` reference set: `architecture.md`, `hardware.md`, `models.md`, `benchmarks.md`, `troubleshooting.md`, `lessons-learned.md`, `roadmap.md`.
- Added `AGENTS.md` (tool-agnostic conventions for AI coding agents), `adr/` (Architecture Decision Records), and this changelog.
- Added open-source readiness files: `LICENSE` (MIT), `CONTRIBUTING.md`, `SECURITY.md`.
- Added a standardized Purpose/Requires/Usage/Output/Failure-cases header to every `start-*.sh` script, alongside the existing detailed rationale comments.
- Added screenshot placeholders (`docs/images/`) pending real captures.

## v1.3 — Uncensored model and remote access (2026-07-29 – 2026-07-30)

- Added `start-qwen3-uncensored.sh` — a secondary, abliterated Qwen3-4B-Instruct-2507 variant for blunt/direct-assistant use, selected via a documented leaderboard cross-check (see [adr/0002](adr/0002-qwen3-model-choice.md) for the base-model reasoning it builds on).
- Set up Tailscale for remote access (phone, away from home) without port-forwarding or public exposure; resolved the Open Terminal Direct-vs-System connection split this exposed.
- Registered both `llama-server` ports as simultaneous Open WebUI connections (`OPENAI_API_BASE_URLS`, plural) so switching the active model doesn't require reconfiguring the frontend.
- Diagnosed and root-caused the `i915`/Vulkan iGPU fence-timeout bug; applied `GGML_VK_MAX_NODES_PER_SUBMIT=1` as a trial mitigation and patched three unguarded crash sites in `llama.cpp`'s server code (local, unsubmitted — see [docs/troubleshooting.md](docs/troubleshooting.md)).

## v1.2 — Open WebUI, Open Terminal, and the switch to Qwen3 for agent mode (2026-07-28 – 2026-07-29)

- Deployed Open WebUI as the chat frontend (rootless Podman) — see [adr/0003](adr/0003-openwebui.md).
- Deployed Open Terminal as a shell/file Integration for the chat models.
- Found and fixed the Builtin Tools token-bloat issue (~5,100 tokens/request) and the reasoning/tool-call-parser hang bugs (see [docs/troubleshooting.md](docs/troubleshooting.md)).
- Switched the production server from Gemma 4 E4B to Qwen3-4B-Instruct-2507 after direct agent-mode testing showed Gemma breaking under a large Builtin Tools set — full reasoning in [adr/0002](adr/0002-qwen3-model-choice.md).

## v1.1 — Fedora migration (2026-07-27 – 2026-07-28)

- Ported the tuned Windows setup to Fedora 44 as the new daily driver — see [adr/0001](adr/0001-fedora-over-windows.md).
- Built `llama.cpp` from source with the Vulkan backend on Fedora, working through the `glslc`/`spirv-*-devel` build-dependency trap.
- Confirmed near-identical steady-state generation speed to Windows (~9.2 vs ~9.4 tok/s) once ported.
- Windows install (`C:\LocalAI`) preserved, not wiped — MCP tooling and the dual-server coding setup hadn't been ported yet.

## v1.0 — Original Windows setup (predates JOURNAL.md)

- Local coding-assistant setup on Windows (`C:\LocalAI`): Qwen3.5-4B for chat/edit/agent, Qwen2.5-Coder-1.5B for autocomplete, wired into Continue.dev via a 5-server MCP stack.
- General chat setup added: Qwen3-4B-Instruct-2507 and Gemma 4 E4B-it (+ vision via `mmproj`), tuned with Vulkan offload, quantized KV cache, and flash attention.
- Diagnosed the Qwen3.5-4B multi-turn caching bug and switched to Qwen3-4B-Instruct-2507 — see [adr/0002](adr/0002-qwen3-model-choice.md).
- Upgraded the `llama.cpp` build (b9305 → b10107), re-verified offload/cache-reuse/speed unchanged; kept the old build as an instant rollback.

## Related documents

- [JOURNAL.md](JOURNAL.md) — the full, dated, narrative log every entry above is summarized from
- [docs/roadmap.md](docs/roadmap.md) — what's next, framed as upcoming work rather than history
- [adr/](adr/) — the reasoning behind the decisions that stuck
