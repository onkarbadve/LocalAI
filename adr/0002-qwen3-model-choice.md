# ADR 0002: Qwen3-4B-Instruct-2507 as the production chat/agent model

**Status**: Accepted (implemented) — current production model, port 8080.
**Date**: Switched from Qwen3.5-4B on 2026-07-26; switched from Gemma 4 E4B for agent-mode specifically on 2026-07-29 (per [JOURNAL.md](../JOURNAL.md)).

## Context

The production server needs to handle chat, coding, and agent-mode (structured tool-calling) duty on a 16GB, no-discrete-GPU machine. Two other models were tried in this role before landing on the current one, each ruled out for a distinct, verified reason rather than a vague quality judgment.

## Decision

Run **Qwen3-4B-Instruct-2507** (dense, Unsloth Dynamic Q4_K_XL) as the production chat/coding/agent-mode model, with `--reasoning off` to work around a template-inherited bug (see [troubleshooting.md](../docs/troubleshooting.md)).

## Alternatives considered

- **Qwen3.5-4B** — the original production model. Hybrid attention + Mamba2/SSM architecture hit an upstream `llama.cpp` bug (`ggml-org/llama.cpp#21831`): `cached_tokens` stuck at a constant regardless of turn count on multi-turn requests. Confirmed to be a checkpoint-*restore-selection* bug, not a cache-frequency one, so cache-tuning flags didn't help. Rejected — still open upstream as of the last check ([models.md](../docs/models.md)).
- **Gemma 4 E4B-it** — ran as production for a period, and is vision-capable (Qwen3 is not). Rejected for the agent-mode role specifically after direct testing: with `--reasoning off` and a large (~26-33) Builtin Tools declaration set, it produced garbage `<unused2171>...`-style token output instead of a real response — a genuine functional break, not a quality tradeoff. Also independently more crash/hang-prone than Qwen3 beyond the shared iGPU fence-timeout bug. Not deleted — kept as the vision fallback, since Qwen3 has no vision capability to replace it with.

## Consequences

- **Positive**: dense architecture has no recurrent-memory component, so it isn't subject to the Qwen3.5 bug class at all, not just this one instance of it.
- **Positive**: validated end-to-end through real Open WebUI usage — 9/9 agent-mode tests across 6 Builtin Tools categories plus a no-tool control passed cleanly once the server-side hang was fixed (see [benchmarks.md](../docs/benchmarks.md)).
- **Negative**: needed its own non-obvious fix. The model's chat template is shared with a "thinking" variant it doesn't use, and auto-detection defaulted to treating it as reasoning-capable, causing runaway generation. `--reasoning off` fixes this, but the fix is checkpoint/template-specific — it had to be explicitly re-verified as *not* applicable to Gemma before being considered for reuse there (it wasn't).
- **Neutral**: this decision only concerns the *production/agent-mode* role. A separate model (`Qwen3-4B-Instruct-2507-heretic-av2`, an abliteration of this same base) fills a deliberately distinct blunt/direct-assistant role — see [models.md](../docs/models.md) for how that choice built directly on this one.

## Related

[docs/models.md](../docs/models.md) · [docs/troubleshooting.md](../docs/troubleshooting.md#llama-server-never-finishes-generating-qwen3-runaway-generation) · [docs/lessons-learned.md](../docs/lessons-learned.md#model-selection) · [SETUP.md](../SETUP.md)
