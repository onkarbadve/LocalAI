# ADR 0003: Open WebUI as the chat frontend, on rootless Podman

**Status**: Accepted (implemented) — current chat frontend, port 3000.
**Date**: Predates [JOURNAL.md](../JOURNAL.md); documented retroactively (2026-07-30 entry), same as the Podman-over-Docker decision below.

## Context

`llama-server` exposes an OpenAI-compatible HTTP API but no real chat interface. A frontend was needed that could talk to that API, support agent-mode tool-calling, and give the models a way to actually execute commands (not just chat), all while running self-hosted on the same box.

## Decision

Run **Open WebUI** as the chat frontend, deployed as a rootless Podman container (`--network host`, so it can reach `llama-server`'s loopback-only ports without bridge-networking workarounds).

## Alternatives considered

**Honestly: none are on record as having been formally evaluated.** Per [JOURNAL.md](../JOURNAL.md)'s 2026-07-30 entry — written specifically to capture reasoning that was never actually debated in-session — Open WebUI (like Podman itself) was simply the starting choice the setup was built around, not a decision arrived at by comparing it against alternatives. This ADR exists to document *why it stuck* based on what real usage showed, not to retroactively invent a comparison against other frontends (e.g. LibreChat, text-generation-webui) that never happened.

What's actually documented as having made it stick, from real use:
- **Multiple backend registration**: `OPENAI_API_BASE_URLS`/`OPENAI_API_KEYS` (plural, semicolon-separated) let both `llama-server` instances (production + uncensored) register as connections simultaneously, so switching which one is running doesn't require reconfiguring the frontend.
- **A first-class Integrations mechanism**: Open Terminal plugs in as a dedicated Integration (Admin/personal Settings → Integrations) rather than needing a generic OpenAPI tool-server wrapper.
- **Real structured tool-calling**: Builtin Tools verified working end-to-end across 9/9 real agent-mode tests once server-side flags were fixed.

## Consequences

- **Positive**: once the backend-side quirks (reasoning-hang, tool-call-parser hang) were resolved, integration for both plain chat and agent-mode tool-calling has been reliable in real use.
- **Positive**: the Integrations model fit Open Terminal specifically well — a first-class settings page rather than bespoke tool-schema wiring.
- **Negative**: real, undocumented rough edges only surfaced through use, not from reading feature lists — Code Interpreter's auto-invoke doesn't work against a local llama.cpp backend at all (confirmed by tracing the actual outgoing prompt: no code-execution tool was ever declared); Builtin Tools silently attaches ~5,100 tokens of overhead to *every* request regardless of relevance unless disabled per-model; the terminal-connection configuration exists as two independent, unsynced stores (personal "Direct" vs. admin-level "System"), and only one of them is reachable from chat tool-calling.
- **Coupled decision**: deploying via Podman rather than Docker was Fedora's path of least resistance (default container engine, no root daemon, rootless by default) — see [JOURNAL.md](../JOURNAL.md)'s 2026-07-30 entry for that reasoning in full; not broken out as its own ADR since it's a packaging choice, not a load-bearing architectural one.

## Related

[docs/architecture.md](../docs/architecture.md) · [docs/troubleshooting.md](../docs/troubleshooting.md) · [docs/lessons-learned.md](../docs/lessons-learned.md#open-webui) · [SETUP.md](../SETUP.md)
