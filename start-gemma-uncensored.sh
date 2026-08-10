#!/usr/bin/env bash
# STATUS (2026-08-05): this is now the only Gemma production server on this
# box. start-gemma-e4b.sh (the censored, non-abliterated production instance
# this comment block originally described) and the model files it pointed at
# (including mmproj-F16.gguf - vision is NOT loaded here, no --mmproj below)
# were both deleted - only uncensored models are kept here now. Every "not
# production"/"production stays on 8080" reference below predates that and
# describes design intent from when both ran side by side, not current
# reality - kept as-is for the historical reasoning, not because port 8080
# is still in use.
#
# Gemma-4-E4B-Uncensored-HauhauCS-Aggressive (HauhauCS, biprojected abliteration)
# - uncensored chat model, same role as start-qwen3-uncensored.sh but for the
# Gemma family, kept on its own port so it doesn't collide, though see the
# memory-budget note below before running it alongside anything else.
#
# Quant: Q4_K_P (HauhauCS's own model-specific custom quant, ~5.34GB
# claimed 1-2 quant-levels above plain Q4_K_M at similar size), chosen
# 2026-08-01 over Q5_K_M for headroom on this iGPU's tight Vulkan budget.
# Note Unsloth's own Gemma-4 guide recommends 8-bit specifically for
# E2B/E4B (9-12GB VRAM), not 4-bit - this quant tier is a real quality
# tradeoff accepted for hardware fit, not a "good enough" equivalent.
#
# File verified 2026-08-01: full 720/720 tensor structural read clean
# (offsets sum to exact file size, no truncation), real llama-server load
# + generation test passed (coherent output, ~8.6 tok/s). Base checkpoint
# is pre-refresh (HF commit history: Apr 2026) - Google shipped a
# same-day family-wide Gemma-4 refresh 2026-07-15 (chat-template/
# tool-calling/FA4 fixes) that this fine-tune does NOT carry; llama.cpp
# logs "detected an outdated gemma4 chat template, applying compatibility
# workarounds" on load as a result. Not currently blocking anything found.
#
# --reasoning off: unlike production Gemma-4-E4B-it (which separates
# reasoning/content cleanly on its own template and does NOT need this),
# this checkpoint emits substantial hidden reasoning_content by default
# even with no tools block present - verified it can consume an entire
# max_tokens budget on "thinking" and return truncated/empty visible
# content otherwise. Verified --reasoning off suppresses it cleanly
# (equivalent to --chat-template-kwargs '{"enable_thinking":false}',
# picked the plain flag instead since it's bakeable here rather than
# needing every client to send it per-request).
#
# -np 1: llama-server defaults to n_slots=4 if unset, which allocates 4x
# the KV cache for -c - this is what tipped the system into OOM (swap
# maxed, 8MB/s thrashing) during verification earlier today. Always pass
# this explicitly for single-user use, same as every other script here.
#
# -c 16384, -ctk/-ctv q8_0, --swa-full: quantized KV cache + full SWA cache
# reuse so multi-turn requests don't reprocess the whole conversation every
# turn (ggml-org/llama.cpp#22288). The now-deleted censored Gemma script ran
# at -c 8192 pending confirmation the GGML_VK_MAX_NODES_PER_SUBMIT=1
# mitigation below was fully solid; this script uses 16384 on the strength
# of a 2026-08-01 stress test (~90s sustained generation, no new entries in
# ~/.local/share/gpu-fence-alerts.log afterward) but has less real-world
# runtime behind it than that more cautious value did. Drop to 8192 if fence
# timeouts show up here.
#
# GGML_VK_MAX_NODES_PER_SUBMIT=1: same iGPU fence-timeout mitigation as
# every other script here (ggml-org/llama.cpp#21724) - backend-level, not
# model-specific.
#
# --temp/--top-p/--top-k/--min-p: Google's published Gemma defaults, same
# as start-gemma-e4b.sh.
#
# Port 8082 (uncensored Qwen3 on 8081) - chosen to avoid collision, NOT
# validated for concurrent use with it. Same combined-memory-budget caveat
# as start-qwen3-uncensored.sh applies: this model alone was already larger
# than the old censored Gemma's Q4_K_XL (5.1GB vs 4.8GB) - do the memory math
# before running two servers at once rather than assuming it fits.

# -t 8: taskset -c 0-7 pinning was considered and benchmarked as a wash on
# this GPU-offloaded path (real cost in the CPU-fallback path instead) - see
# start-qwen3.sh for the full rationale. Not applied.

BIN="$HOME/LocalAI/llama.cpp/build/bin/llama-server"
MODEL="$HOME/LocalAI/models/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf"

export GGML_VK_MAX_NODES_PER_SUBMIT=1

exec "$BIN" \
  --model "$MODEL" \
  --port 8082 \
  -t 8 \
  -c 16384 \
  -np 1 \
  -fa on \
  -ctk q8_0 -ctv q8_0 \
  --swa-full \
  -lv 2 \
  --reasoning off \
  --temp 1.0 --top-p 0.95 --top-k 64 --min-p 0.0
