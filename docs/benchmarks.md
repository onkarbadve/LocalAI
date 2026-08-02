# Benchmarks

Real numbers observed during actual use and testing on the [hardware documented here](hardware.md) (Intel i5-12500H, Iris Xe iGPU, Vulkan, 16GB RAM). Nothing here is a synthetic/standardized benchmark run — every figure was measured incidentally while validating a feature or chasing a bug, and is sourced from [JOURNAL.md](../JOURNAL.md) and [SETUP.md](../SETUP.md). See [models.md](models.md) for what each model in the table below is actually for. TODO markers are left where no measurement has been made.

## Generation speed

| Model | Quant | Context | Generation speed | Prompt processing | RAM (RSS) | GPU Memory (Vulkan-visible) | Notes |
|-------|-------|---------|-------------------|--------------------|-----------|------------------------------|-------|
| Qwen3-4B-Instruct-2507 | Unsloth Dynamic Q4_K_XL | 24576 | ~9–9.8 tok/s | ~28 tok/s warm, ~2.5 tok/s cold-start (first request after boot) | ~530MB (confirms GPU-resident, not CPU) | ~6GB (documented, solo) | Production chat/coding/agent model. Port 8080. |
| Qwen3-4B-Instruct-2507-heretic-av2 (abliterated) | mradermacher Q4_K_M | 24576 | ~11.58 tok/s generation | ~34 tok/s prompt processing | TODO | ~6GB (same base model, same context) | Blunt/direct assistant. Port 8081. Verified genuine Vulkan execution (not CPU/llvmpipe fallback). |
| Gemma 4 E4B-it + mmproj | Unsloth Dynamic Q4_K_XL | 8192 (reduced from 16384) | ~9–9.8 tok/s | ~28 tok/s warm, ~2.5 tok/s cold-start | TODO | TODO | Deprioritized — vision fallback, not actively used. |
| Qwen2.5-Coder-1.5B *(Windows only)* | Q4_K_M | 4096 | ~25 tok/s (per author's notes) | TODO | TODO | full offload, `-ngl 99` | Autocomplete only. |

## Cold start

| Platform | First load (fresh boot) | Warm restart |
|---|---|---|
| Windows | ~30–90s | ~7s |
| Fedora | First request ~2.5 tok/s prompt processing (Vulkan shader compilation) | ~28 tok/s once Mesa's shader cache is warm |

## Multi-turn cache reuse (Qwen3-4B-Instruct-2507, production)

Measured directly via `/slots` during real Open WebUI agent-mode testing (2026-07-29):

| Turn | Prompt tokens | Cached | Fresh tokens processed | Wall time |
|---|---|---|---|---|
| 1 (fresh chat) | 5,824 | 0 | 5,824 | 15.3s |
| 2 (same chat) | 5,990 | 5,857 | 133 | 23.8s |

~98% cache hit on turn 2 — the ~5,800-token system-prompt-plus-tool-declarations prefix is reused almost entirely after the first message. Turn 2's wall time is higher only because it triggered a real tool call (two generation passes), not because caching failed. Practical implication: single-message timing tests overstate real multi-turn conversation cost, since the expensive prefix reprocessing happens once per conversation, not once per message.

## Agent-mode / tool-calling round trips

9 real tests through the Open WebUI UI (not curl), across 6 Builtin Tools categories plus one no-tool control, all against production Qwen3 (2026-07-29):

- Single-round-trip calls (tool decision + final answer in one generation): ~15–27s
- Two-round-trip calls (tool call → results → separate follow-up commentary, e.g. `add_memory`, `search_chats`, `calculate_timestamp`): ~2x longer than single-round-trip, since it's two full ~5,800-token prompt-processing passes instead of one

Zero failures across all 9 tests. Full test table in [JOURNAL.md](../JOURNAL.md) (2026-07-29 entry).

## Build upgrade impact (Windows, b9305 → b10107)

| | Before (b9305) | After (b10107) |
|---|---|---|
| Layer offload | 43/43 | 43/43 (unchanged) |
| `--swa-full` cache reuse | works | works (unchanged) |
| Generation speed | ~8–9.5 tok/s | ~8–9.5 tok/s (unchanged) |
| Compute buffer | ~517MB | ~187MB |

## TODO — not yet measured

- [ ] Formal prompt-processing tok/s for Qwen3-4B-Instruct-2507-heretic-av2 and Gemma 4 E4B (RAM/GPU memory columns above)
- [ ] Head-to-head quality comparison across models on a fixed prompt set (see [models.md](models.md) for qualitative notes in the meantime)
- [ ] A repeatable, scripted benchmark harness — currently every number here was captured incidentally during real use, not a standing benchmark suite (tracked in [roadmap.md](roadmap.md#future-ideas))

## Related documents

- [hardware.md](hardware.md) — the machine every number above was measured on
- [models.md](models.md) — what each model is for, alongside the numbers here
- [SETUP.md](../SETUP.md) — the flags each measurement was taken with
- [JOURNAL.md](../JOURNAL.md) — the original sessions these numbers were measured during
