# Roadmap

Where this setup has been and where it's headed. "Completed" and "Upcoming" are drawn directly from [JOURNAL.md](../JOURNAL.md) and [SETUP.md](../SETUP.md#path-forward); "Future Ideas" are speculative and explicitly marked as such — not commitments, not scoped, not started. See [CHANGELOG.md](../CHANGELOG.md) for the same completed work framed as version history, and [adr/](../adr/) for the reasoning behind the load-bearing decisions along the way.

## Completed

- Local coding-assistant setup on Windows (`C:\LocalAI`), Qwen3.5-4B + Qwen2.5-Coder-1.5B, MCP tool stack for agentic coding.
- Diagnosed and resolved the Qwen3.5-4B multi-turn caching bug by switching to dense Qwen3-4B-Instruct-2507 (see [adr/0002-qwen3-model-choice.md](../adr/0002-qwen3-model-choice.md)).
- Ported the setup from Windows to Fedora as the daily driver, built `llama.cpp` from source with the Vulkan backend (see [adr/0001-fedora-over-windows.md](../adr/0001-fedora-over-windows.md), [adr/0004-vulkan-backend.md](../adr/0004-vulkan-backend.md)).
- Deployed Open WebUI as the chat frontend via rootless Podman (see [adr/0003-openwebui.md](../adr/0003-openwebui.md)).
- Deployed Open Terminal as a shell/file Integration, wired into both Open WebUI's chat tool-calling and Files/Terminal side panels.
- Diagnosed and root-caused the `i915`/Vulkan iGPU fence-timeout bug, applied `GGML_VK_MAX_NODES_PER_SUBMIT=1` as a trial mitigation, and patched three unguarded crash sites in `llama.cpp`'s server code (local, unsubmitted).
- Set up Tailscale for remote access (phone, away from home) without port-forwarding or public exposure.
- Selected and deployed a secondary, uncensored/blunt-mode model (`Qwen3-4B-Instruct-2507-heretic-av2`) via a documented, leaderboard-cross-checked evaluation process.
- Full documentation overhaul: `docs/` reference set, `AGENTS.md`, open-source readiness files (`LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`).

## Upcoming

Framed as independent "chapters" in [SETUP.md](../SETUP.md#path-forward) — each is its own project, meant to be gone deep on one at a time rather than cleared in order:

- [ ] **Close the hallucination gap with real RAG** — document/web-search grounding via Open WebUI's existing support for it, rather than just documenting that the uncensored model confabulates.
- [ ] **Port the Windows-only MCP tool stack to Fedora** — filesystem/git/memory/fetch/shell servers, plus the dual-server coding setup (`startCoding.bat`), neither of which made the Windows → Fedora jump yet.
- [ ] **Resolve the iGPU fence-timeout bug upstream, not just mitigate it** — validate `GGML_VK_MAX_NODES_PER_SUBMIT=1` over real extended use, then file the upstream `i915` bug with the dmesg traces/coredumps already gathered.
- [ ] **Real concurrent serving instead of manual model swapping** — re-examine the mutual-exclusivity assumption between the two chat models (shrink context sizes and/or add a lightweight router) now that it's been running stably for a while.
- [ ] **Voice via `whisper.cpp`**, routed around Gemma's dead-end audio path (two separate unfixable upstream blockers documented in [troubleshooting.md](troubleshooting.md)).
- [ ] **A small personal LoRA fine-tune** on personal data/writing style — everything so far has been off-the-shelf quants and community abliterations.
- [ ] **Turn crash monitoring into real self-healing infrastructure** — `gpu-fence-watch.service` currently only alerts; auto-restart-on-crash plus a phone push notification would close the gap between "noticed it crashed" and "it healed itself."
- [ ] **A repeatable, scripted model-evaluation pipeline** — today's evaluation rigor (leaderboard cross-check, GitHub issue verification, source checks) is manual and ad-hoc per model.

Smaller open items, not folded into a chapter above:
- Revisit Qwen3.5-4B once its upstream caching bug (`ggml-org/llama.cpp#21831`) is fixed.
- Reconsider `--mlock` on Fedora if ever moving to higher-RAM hardware (would need raising systemd's `LimitMEMLOCK`).
- A small supervisor/menu script for day-to-day model switching, narrower in scope than the self-healing chapter above.

## Future Ideas

Speculative, unscoped, not yet started, and not a commitment — listed here so they're not lost, not because they're planned:

- **Audio models** — beyond the `whisper.cpp` voice chapter above: text-to-speech for a full voice loop, not just speech-to-text.
- **Multi-model routing** — a lightweight proxy that picks which of the registered `llama-server` connections to hit per-request, rather than the current manual mutually-exclusive swap.
- **Intel NPU experiments** — this machine's CPU includes an NPU that's currently unused by any part of this setup; whether `llama.cpp` or another runtime can target it at all is an open question, not a validated plan.
- **Containerized deployment for `llama-server` itself** — currently only Open WebUI and Open Terminal run in Podman; the inference server runs bare-metal. Worth revisiting once/if the Vulkan-in-container story on Fedora is better understood.
- **Automated benchmarking** — a standing harness that runs the same prompt set against every candidate model and records tok/s, quality, and memory automatically, superseding today's incidental, measured-during-real-use numbers (see [benchmarks.md](benchmarks.md)).
- **Broader agent workflows** — beyond the current Builtin Tools + Open Terminal integration, e.g. multi-step planning or the ported MCP stack acting together rather than as isolated tools.

## Related documents

- [SETUP.md](../SETUP.md#path-forward) — the original "path forward" writeup this roadmap is built from
- [CHANGELOG.md](../CHANGELOG.md) — completed work as version history
- [adr/](../adr/) — why the stable decisions behind this roadmap were made
- [JOURNAL.md](../JOURNAL.md) — the dated, narrative source of truth for everything completed
