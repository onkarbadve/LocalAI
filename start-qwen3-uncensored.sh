#!/usr/bin/env bash
#
# Purpose: launch the secondary, uncensored/blunt-mode llama-server instance
#   (Qwen3-4B-Instruct-2507-heretic-av2) on port 8081. Not the production
#   agent-mode server - that's start-qwen3.sh.
# Requires: llama.cpp built from source with the Vulkan backend at
#   $HOME/LocalAI/llama.cpp/build/bin/llama-server; the GGUF at
#   $HOME/LocalAI/models/Qwen3-4B-Instruct-2507-heretic-av2.Q4_K_M.gguf
#   (see SETUP.md for source); an Intel iGPU (or other Vulkan device).
# Arguments: none. Edit the script directly to change model path, port, or
#   sampling/runtime flags.
# Expected output: runs in the foreground (via `exec`); binds
#   127.0.0.1:8081 once ready; GET /health returns `{"status":"ok"}`.
# Typical usage: ./start-qwen3-uncensored.sh   (register alongside :8080 in
#   Open WebUI - both connections stay configured, only one process need run)
# Failure cases: fails fast on a missing binary/model path; run mutually
#   exclusive with start-qwen3.sh at their current context sizes - combined
#   Vulkan memory does not fit both (see SETUP.md); see docs/troubleshooting.md
#   for repetition-loop and GPU fence-timeout failure modes.
#
# Qwen3-4B-Instruct-2507-heretic-av2 (arnomatic, abliterated via Heretic v1.1.0,
# GGUF by mradermacher) - separate/secondary "blunt, unfiltered" chat model.
# Not the production agent-mode server (that's start-qwen3.sh) - deliberately
# kept on its own port so both can run at once if wanted, or so this one can
# be started standalone without touching production.
#
# Chosen over mlabonne/NeuralDaredevil-8B-abliterated (2024, older, different
# base) specifically because this is an abliteration of the *exact* model
# already proven stable in production here (Qwen3-4B-Instruct-2507) - same
# architecture, same chat template, same generic-autoparser tool-calling path,
# so it inherits none of the Gemma-style bespoke-parser risk and none of the
# Qwen3.5 hybrid/recurrent-memory cache-restore bug (ggml-org/llama.cpp#21831,
# still open as of 2026-07-30 - ruled OUT any Qwen3.5-based uncensored finetune
# for this reason). Verified real via the UGI Leaderboard (DontPlanToEnd/
# UGI-Leaderboard on HF Spaces): UGI 38.81, NatInt 17.77 - highest of the
# Qwen3-4B-Instruct-2507-based uncensored finetunes there as of 2026-01-02,
# and notably scores *higher* NatInt than the untouched base model (13.76).
#
# Same base model as start-qwen3.sh, so the same two fixes apply and are
# carried over unchanged:
# --reasoning off: the shared Qwen3 chat template has a reasoning branch this
# non-thinking checkpoint never emits; auto-detection otherwise waits forever
# for a closing think tag and generation runs away. See start-qwen3.sh /
# JOURNAL.md for the original repro.
# GGML_VK_MAX_NODES_PER_SUBMIT=1: iGPU/Vulkan fence-timeout mitigation
# (i915 GPU-hang class bug, ggml-org/llama.cpp#21724) - backend/hardware-level,
# applies regardless of which model is running.
#
# NOT tested against Open WebUI's exact tool-calling request shape the way
# start-qwen3.sh was - this model's role is a blunt/direct assistant, not
# agent-mode duty, so that gauntlet wasn't required before standing it up.
# Re-verify (multi-turn cached_tokens growth, real tool-declaration payload)
# before ever promoting this to a tool-calling role.
#
# Anti-repetition/runaway tuning (added 2026-07-30, after a real long-form
# erotica test degenerated into a cycling phrase loop - "I pushed... I
# pulled... I want you to feel me..." repeating with minor variation and
# never hitting a stop condition):
# --repeat-penalty 1.1 --repeat-last-n 256: standard token-frequency penalty,
# widened window (default is only 64 tokens) so it actually covers longer-
# range repeats like the one observed, not just the last few dozen tokens.
# --dry-multiplier 0.8 (base/allowed-length left at their defaults 1.75/2):
# DRY sampling penalizes repeated *phrase* sequences specifically, not just
# individual token frequency - a better match for what actually happened
# (repeated multi-word phrases cycling), since plain repeat-penalty alone
# doesn't reliably catch that pattern.
# -n 2048: hard ceiling on tokens per response. Base model had no cap at all
# (`--predict` defaults to -1/infinite) - without this, a repetition loop that
# evades both penalties above could still run until it exhausts the context
# window (-c 24576) rather than actually stopping. This is the actual
# "runaway" backstop; the two penalties above are the preferred/earlier line
# of defense, this is the guaranteed one.
#
# Port 8081 (production Qwen3/Gemma stay on 8080) - chosen so this CAN run
# alongside production without a port collision, but as of 2026-07-30 the two
# are being run mutually exclusively on purpose, not concurrently: both at
# -c 24576 is ~6GB Vulkan-visible each (per start-qwen3.sh's own comment),
# ~12GB combined, over the documented ~7.4-9.8GB budget - and piling on memory
# pressure is exactly the wrong move while the intermittent i915 fence-timeout/
# GPU-hang issue (JOURNAL.md, still not fully root-caused) is unresolved.
# Revisit concurrent use only after shrinking this script's -c substantially
# (KV cache scales with context; dropping to -c 4096 would cut this model's
# footprint roughly in half) AND after the GPU-hang situation is calmer.

BIN="$HOME/LocalAI/llama.cpp/build/bin/llama-server"
MODEL="$HOME/LocalAI/models/Qwen3-4B-Instruct-2507-heretic-av2.Q4_K_M.gguf"

export GGML_VK_MAX_NODES_PER_SUBMIT=1

exec "$BIN" \
  --model "$MODEL" \
  --port 8081 \
  -t 8 \
  -c 24576 \
  -np 1 \
  -fa on \
  -lv 2 \
  --reasoning off \
  --temp 0.7 --top-p 0.8 --top-k 20 --min-p 0 \
  --repeat-penalty 1.1 --repeat-last-n 256 \
  --dry-multiplier 0.8 \
  -n 2048
