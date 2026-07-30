#!/usr/bin/env bash
#
# Purpose: launch the Gemma 4 E4B-it vision-chat llama-server instance on
#   port 8080. Deprioritized fallback, not the active production server
#   (that's start-qwen3.sh) - kept for when vision input is actually needed.
# Requires: llama.cpp built from source with the Vulkan backend at
#   $HOME/LocalAI/llama.cpp/build/bin/llama-server; the GGUF weights at
#   $HOME/LocalAI/models/gemma-4-E4B-it-UD-Q4_K_XL.gguf and
#   $HOME/LocalAI/models/mmproj-F16.gguf (see SETUP.md); an Intel iGPU (or
#   other Vulkan device). Also carries two local, unsubmitted llama.cpp
#   source patches (see docs/troubleshooting.md) that must be reapplied
#   after any `git pull` of llama.cpp/.
# Arguments: none. Edit the script directly to change model paths, port, or
#   sampling/runtime flags. Vision (--mmproj) is currently commented out -
#   uncomment the flag at the bottom to re-enable image input.
# Expected output: runs in the foreground (via `exec`); binds
#   127.0.0.1:8080 once ready; GET /health returns `{"status":"ok"}`.
# Typical usage: ./start-gemma-e4b.sh   (stop start-qwen3.sh first - same port)
# Failure cases: fails fast on a missing binary/model path; fails to bind if
#   start-qwen3.sh (same port 8080) is already running; more crash/hang-prone
#   than Qwen3 beyond the shared GPU fence-timeout bug - see
#   docs/troubleshooting.md for known failure modes and current mitigations.
#
# Gemma 3n E4B-it (Unsloth Dynamic Q4_K_XL) + vision (mmproj-F16)
# Ported from the tuned Windows setup (C:\LocalAI\Start-Server-Gemma4-E4B.bat)
# to Linux/Vulkan.
#
# Hardware: Intel i5-12500H (4P+8E, 16 threads), Intel Iris Xe iGPU via Vulkan
# (~8-9.8GB Vulkan-visible budget out of 16GB system RAM), Fedora 44.
#
# -ngl left unset: -ngl defaults to 'auto' in this build, same effect as the
# Windows script's reliance on --fit for full layer offload.
# -c 8192: dropped from 16384 (2026-07-29) while validating the
# GGML_VK_MAX_NODES_PER_SUBMIT=1 fence-timeout mitigation - smaller context
# means a smaller compute graph/KV cache and less GPU memory pressure. First
# tried 4096, but Open WebUI's actual request (system prompt + tool/function
# defs it attaches automatically) alone runs ~5100+ tokens, exceeding that -
# 8192 clears the overhead with room for real conversation. Raise back to
# 16384 once fence timeouts are confirmed gone.
# -ctk/-ctv q8_0 + -fa on: quantized KV cache, roughly halves context memory.
# --swa-full: without this, multi-turn requests reprocess the entire
# conversation from scratch every turn (see ggml-org/llama.cpp#22288) - this
# build has the fix, but it's still opt-in via this flag.
# -t 8: matches the P-core thread count tuned on the Windows side.
# No --mlock: same reasoning as start-qwen3.sh - ulimit -l is 8MB on this box,
# and the Windows testing already found mlock fought the OS under memory
# pressure on this 16GB machine (crashed a browser once). mmap (default) lets
# the kernel page cold parts out instead of hard-OOMing.
# --temp/--top-p/--top-k/--min-p: Google's published Gemma defaults.
# --mmproj: enables vision via OpenAI-style image_url content blocks on
# /v1/chat/completions. Audio does NOT work (upstream API gap + mtmd-cli
# crash on this model+mmproj combo, per the original Windows investigation) -
# vision-only.
#
# --reasoning off (2026-07-29): superseding the earlier decision not to carry
# this over from the Qwen3 script. That decision was made when "terminated in
# 1-5s" held true - but that was before Open WebUI's Builtin Tools setting was
# found to be attaching 33 native tool declarations to every request (~5100
# tokens of pure overhead, see JOURNAL.md 2026-07-29), which the model then
# spent its whole reasoning phase evaluating against trivial messages (one
# measured case: 172s prompt processing + 36s of reasoning generation for a
# single "test" message). Tool bloat is now fixed at the source (Admin >
# Models > Capabilities > Builtin Tools, unchecked), but the underlying fact
# remains: Gemma isn't a dedicated reasoning model like DeepSeek-R1/QwQ - the
# <think> block is freeform chain-of-thought the template invites, not
# something whose answer quality depends on being preserved. On this
# hardware (iGPU, ~9 tok/s), every second spent "thinking" is a real cost for
# no measured accuracy benefit on ordinary chat use. Not the same flag as
# --skip-chat-parsing (that one was never added here) - --reasoning off stops
# the model being prompted into a thinking phase at all, rather than just
# changing how an existing one gets parsed, so it doesn't reintroduce the
# Qwen3 template-hang failure mode this comment used to warn about.
#
# First request after a fresh boot may be slow (~2.5 tok/s prompt processing)
# due to one-time Vulkan shader compilation; subsequent requests are fast
# (~28 tok/s prompt processing) once Mesa's shader cache is warm.
#
# NOTE: binds port 8080, same as start-qwen3.sh. Only run one server at a
# time - stop the other first (`pkill -f llama-server`).

BIN="$HOME/LocalAI/llama.cpp/build/bin/llama-server"
MODEL="$HOME/LocalAI/models/gemma-4-E4B-it-UD-Q4_K_XL.gguf"
MMPROJ="$HOME/LocalAI/models/mmproj-F16.gguf"

# GGML_VK_MAX_NODES_PER_SUBMIT: default 100 (ggml-vulkan.cpp). On integrated
# GPUs, 100 compute-graph nodes in one Vulkan submission can run long enough
# to exceed the kernel driver's hang-detection timeout, causing a false
# "GPU hang" reset (see ggml-org/llama.cpp#21724, same root cause confirmed
# on an AMD APU - the fix there was dropping this to 1). Testing whether
# this explains the "Fence expiration time out"/ErrorDeviceLost incidents
# logged in JOURNAL.md's 2026-07-28 entries. Trial value, not yet confirmed.
export GGML_VK_MAX_NODES_PER_SUBMIT=1

exec "$BIN" \
  --model "$MODEL" \
  --port 8080 \
  -t 8 \
  -c 8192 \
  -fa on \
  -ctk q8_0 -ctv q8_0 \
  -np 1 \
  --swa-full \
  -lv 2 \
  --reasoning off \
  --temp 1.0 --top-p 0.95 --top-k 64 --min-p 0.0

  # --mmproj "$MMPROJ" \  # vision disabled while validating GPU-hang mitigation; re-add to restore image input
