# Benchmarks

Real numbers observed during actual use and testing on the [hardware documented here](hardware.md) (Intel i5-12500H, Iris Xe iGPU, Vulkan, 16GB RAM). Nothing here is a synthetic/standardized benchmark run — every figure was measured incidentally while validating a feature or chasing a bug, and is sourced from [JOURNAL.md](../JOURNAL.md) and [SETUP.md](../SETUP.md). See [models.md](models.md) for what each model in the table below is actually for. TODO markers are left where no measurement has been made. **"Production"/"port 8080" labels below on the censored `Qwen3-4B-Instruct-2507` and `Gemma 4 E4B-it` rows are historical** — both models and their launch scripts were deleted 2026-08-05 (only uncensored models are kept on this box now); left as measured at the time rather than rewritten, per this repo's convention of not retroactively editing recorded history.

## Generation speed

| Model | Quant | Context | Generation speed | Prompt processing | RAM (RSS) | GPU Memory (Vulkan-visible) | Notes |
|-------|-------|---------|-------------------|--------------------|-----------|------------------------------|-------|
| Qwen3-4B-Instruct-2507 | Unsloth Dynamic Q4_K_XL | 24576 | ~9–9.8 tok/s | ~28 tok/s warm, ~2.5 tok/s cold-start (first request after boot) | ~530MB (confirms GPU-resident, not CPU) | ~6GB (documented, solo) | Deleted 2026-08-05 (censored model). Was port 8080. |
| Qwen3-4B-Instruct-2507-heretic-av2 (abliterated) | mradermacher Q4_K_M | 24576 | ~11.58 tok/s (incidental, superseded below) | ~34 tok/s (incidental, superseded below) | 680MB RSS (measured 2026-08-05) | ~6GB (same base model, same context) | Production chat/coding/agent model. Port 8081. Verified genuine Vulkan execution (not CPU/llvmpipe fallback). |
| Gemma 4 E4B-it + mmproj | Unsloth Dynamic Q4_K_XL | 8192 (reduced from 16384) | ~9–9.8 tok/s | ~28 tok/s warm, ~2.5 tok/s cold-start | TODO | TODO | Deleted 2026-08-05 (censored model + mmproj). Was port 8080. |
| Gemma-4-E4B-Uncensored-HauhauCS-Aggressive | Q4_K_P | 16384 | see formal benchmark below | see formal benchmark below | 3.07GB RSS (measured 2026-08-05; `--swa-full` + q8_0 KV cache, larger than Qwen's) | ~5.3GB | Production chat, text-only (no `--mmproj`). Port 8082. |
| Qwen2.5-Coder-1.5B *(Windows only)* | Q4_K_M | 4096 | ~25 tok/s (per author's notes) | TODO | TODO | full offload, `-ngl 99` | Autocomplete only. |

### Formal benchmark, 2026-08-05 — both production servers, live

Superseding the incidental "~11.58 tok/s"/"~34 tok/s" figures above (single-observation, captured mid-task rather than as a dedicated benchmark) — this is the first run using a repeatable methodology and a standing script (`bench-llama-server.py`, repo root). Each `llama-server` instance was launched via its real production `start-*.sh` script (same flags used in daily use — see [SETUP.md](../SETUP.md)), benchmarked, then stopped before the next one started (the two are mutually exclusive on this iGPU's memory budget, same as normal operation). Methodology: 1 untimed warmup + 5 timed runs per phase; prompt-processing (PP) uses a 600-601 token prompt with `cache_prompt:false` forcing full uncached evaluation each run; generation (TG) forces exactly 128 tokens via `ignore_eos:true` so runs are directly comparable. Mean ± stdev via the server's own `timings.prompt_per_second`/`timings.predicted_per_second` fields (no client-side timing).

| Model | Port | PP (600-601 tok prompt) | TG (128 tok forced) |
|---|---|---|---|
| Qwen3-4B-Instruct-2507-heretic-av2 | 8081 | 150.26 ± 0.34 tok/s | 10.41 ± 0.03 tok/s |
| Gemma-4-E4B-Uncensored-HauhauCS-Aggressive | 8082 | 100.61 ± 0.34 tok/s | 7.34 ± 0.01 tok/s |

Both runs completed with zero new entries in `~/.local/share/gpu-fence-alerts.log` (checked before/after each) — no fence-timeout/device-lost activity during either benchmark. Qwen is faster on both axes, consistent with it being the smaller/denser model (Q4_K_M, dense architecture) vs. Gemma's larger footprint, `-ctk`/`-ctv q8_0` quantized KV cache, and `--swa-full`. These PP/TG numbers aren't directly comparable to the OVMS table below (different prompt, different context length, different backend) — treat each table as internally consistent, not cross-comparable.

## OpenVINO / OVMS (evaluated backend, not in daily use)

Measured via `openvino_genai`'s `PerfMetrics` API (5 timed runs + 1 warmup, greedy decoding) directly against the OpenVINO IR — not through the OVMS container's HTTP layer, though OVMS serves the same IR. See [SETUP.md](../SETUP.md#alternative-backend-openvino--ovms-evaluated-not-in-daily-use) for how these are launched.

| Model | Device | Throughput | TTFT | Load time | Date |
|---|---|---|---|---|---|
| Qwen3-8B (int4-ov) | GPU (iGPU) | 11.12–11.51 tok/s | TODO | TODO | 2026-08-02 |
| Qwen3-8B (int4-ov) | CPU | 7.56–7.64 tok/s | TODO | TODO | 2026-08-02 |
| TinyLlama-1.1B-Chat (int4-ov) | GPU (iGPU) | 61.34 ± 5.55 tok/s | 57.0 ± 0.4 ms | ~3.6s | 2026-08-03 |
| Qwen3.5-9B (int4-ov), text-only | GPU (iGPU), via `openvino_genai` directly | 10.22–10.30 tok/s | ~447ms | 18.24s | 2026-08-04 |
| Qwen3.5-9B (int4-ov), vision | GPU (iGPU), via `openvino_genai` directly | 10.20 tok/s | ~10.2s (vision-encoder pass dominates TTFT) | — | 2026-08-04 — **output is hallucinated on GPU, throughput number is not meaningful in isolation**, see [troubleshooting.md](troubleshooting.md) and [openvino#37223](https://github.com/openvinotoolkit/openvino/issues/37223) |
| Qwen3.5-9B (int4-ov), text-only | GPU (iGPU), via OVMS (`start-ovms-qwen3.5-9b-text.sh`) | 9.35 ± 0.07 tok/s (client-side, HTTP `/v3/chat/completions` streaming; slightly below the direct-`openvino_genai` row above, consistent with added HTTP serialization/dispatch overhead) | 2500 ± 158 ms TTFT (~230 tok prompt) | ~18s warm restart (`--cache_dir` on a named volume), ~26–43s cold | 2026-08-14, on the `weekly` image built 2026-08-13 (5 timed runs + 1 warmup, unique-nonce prompts to defeat prefix caching, `temperature:0`; OVMS's `/metrics` has no per-token latency fields so this is client-side wall-clock, not server-reported) |

**Qwen3.5-9B via OVMS concurrency** (2026-08-04, `start-ovms-qwen3.5-9b-text.sh`, `max_tokens:60` short prompts): the executor admitted up to ~15 concurrent requests at once (`All requests` == `Scheduled requests` in the server logs, no queuing below that); bursts of 32 concurrent requests all completed successfully (`http_200`), with per-request latency degrading roughly linearly as concurrency rose (5–12s at 8 concurrent → 9–22s at 16 → 8.8–34.6s at 32) — consistent with shared GPU compute across more sequences, not admission rejection. This ceiling held even after pinning a 4x larger, fixed 2GB KV-cache pool (`--cache_size 2 --kv_cache_precision u8`) — cache size was tested directly and ruled out as the cause; the real limiting factor is still unidentified. See [SETUP.md](../SETUP.md#qwen35-9b-via-ovms-start-ovms-qwen35-9b-textsh--start-ovms-qwen35-9b-visionsh) and JOURNAL.md 2026-08-04 (both entries) for the full investigation.

**CPU+iGPU split confirmed not possible for a single request** (2026-08-03): compiled both models above with `HETERO:GPU,CPU` and `AUTO:GPU,CPU`; `compiled_model.get_property('EXECUTION_DEVICES')` returned `['GPU.0']` in every case — HETERO only reassigns ops to CPU when the GPU plugin can't run them, and both models are fully GPU-supported, so there's nothing to split. No mixed-device number exists to report here because there's no mixed-device execution happening.

Not apples-to-apples across the two models: Qwen3-8B went through a proper calibrated `optimum-intel` IR conversion; TinyLlama's IR is a community conversion of unknown calibration rigor. Treat the ~5.5x throughput gap as roughly consistent with the ~7x parameter-count difference, not a precise ratio.

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

- [x] Formal prompt-processing tok/s for the two production models (`Qwen3-4B-Instruct-2507-heretic-av2`, `Gemma-4-E4B-Uncensored-HauhauCS-Aggressive`) — done 2026-08-05, see the formal benchmark subsection above. GPU-memory (Vulkan-visible) columns still not directly measured (RAM/RSS now is).
- [ ] Head-to-head quality comparison across models on a fixed prompt set (see [models.md](models.md) for qualitative notes in the meantime)
- [x] A repeatable, scripted benchmark harness — `bench-llama-server.py` (repo root, added 2026-08-05) benchmarks any running `llama-server` instance via its native `/completion` endpoint with a fixed warmup+timed-runs methodology. Covers the llama.cpp/Vulkan side of this item; the OpenVINO/OVMS side still uses the separate `test_ov_qwen.py` script, and there's no single harness spanning both backends yet (tracked in [roadmap.md](roadmap.md#future-ideas)).

## Related documents

- [hardware.md](hardware.md) — the machine every number above was measured on
- [models.md](models.md) — what each model is for, alongside the numbers here
- [SETUP.md](../SETUP.md) — the flags each measurement was taken with
- [JOURNAL.md](../JOURNAL.md) — the original sessions these numbers were measured during
