# ADR 0001: Fedora as the daily driver, Windows preserved as origin

**Status**: Accepted (implemented) — Fedora is the current daily driver as of this document.
**Date**: Ported the week of 2026-07-27/28 (per [JOURNAL.md](../JOURNAL.md)'s backfilled history); Windows setup predates the journal.

## Context

The setup was originally built and tuned on Windows (`C:\LocalAI`) — llama.cpp, Vulkan offload, quantized KV cache, flash attention, thread counts matched to the CPU's P-core/E-core split, all already working. The binding constraint throughout is 16GB of shared system RAM on a machine with no discrete GPU, where the OS's own idle footprint directly competes with the budget available for GPU-visible model memory.

## Decision

Move daily-driver duty to Fedora 44, specifically with KDE Plasma over GNOME for its lower idle RAM footprint, partly to reclaim RAM Windows was holding onto for the model budget. The Windows install was **not** wiped — it's preserved on its own NTFS partition, mountable read-only for reference, because some tooling (the MCP server stack, the dual-server coding setup) hadn't been ported to Fedora at the time of the switch and still hasn't (see [roadmap.md](../docs/roadmap.md)).

## Alternatives considered

- **Stay on Windows.** Already tuned and working, avoiding a rebuild and the platform-specific issues that surfaced during the port (below). Rejected because a desktop OS holding onto RAM the model could otherwise use is a direct cost on a 16GB machine — the whole point of moving was to claw that back.
- **GNOME on Fedora.** Considered against the same idle-footprint criterion used to justify the OS switch itself; KDE Plasma was picked instead specifically for its lower baseline RAM usage.
- **Wipe Windows entirely.** Rejected — the MCP tool stack and dual-server coding setup were still Windows-only and hadn't been re-validated on Fedora, so removing the working reference environment would have meant losing working tooling with no replacement ready.

## Consequences

- **Positive**: once ported, steady-state generation speed came out nearly identical to Windows (~9.2 vs ~9.4 tok/s, same models/flags) — confirming the OS switch didn't cost performance, only changed where the RAM headroom came from.
- **Positive**: cold-start behavior differs but isn't clearly worse — Fedora starts generating around ~2.5 tok/s while Mesa compiles shaders for the very first request, then climbs to ~28 tok/s once cached; Windows takes 30–90s to first token cold, ~7s on restarts once warm.
- **Negative**: hit new, Fedora-specific issues Windows never had — the Vulkan build's `glslc`-not-`glslangValidator` package-naming trap, and a hard `ulimit -l` 8MB cap from systemd's `user@.service` hardening that breaks `--mlock` outright (Windows's own mlock experience was already shaky under memory pressure, so both platforms ended up on plain mmap regardless — see [lessons-learned.md](../docs/lessons-learned.md)).
- **Negative / open**: the migration is intentionally incomplete — the Windows-only MCP tooling and dual-server coding setup remain unported, tracked as roadmap items rather than treated as done.

## Related

[docs/hardware.md](../docs/hardware.md) · [docs/lessons-learned.md](../docs/lessons-learned.md#fedora-experience) · [docs/roadmap.md](../docs/roadmap.md) · [JOURNAL.md](../JOURNAL.md)
