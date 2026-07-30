#!/usr/bin/env bash
# Qwen3-4B-Instruct-2507 (Unsloth Dynamic Q4_K_XL) - chat/general use
# Ported from the tuned Windows setup (C:\LocalAI\Start-Server.bat) to Linux/Vulkan.
#
# Hardware: Intel i5-12500H (4P+8E, 16 threads), Intel Iris Xe iGPU via Vulkan
# (~8-9.8GB Vulkan-visible budget out of 16GB system RAM), Fedora 44.
#
# -ngl left unset: this llama.cpp build defaults -ngl to 'auto', which offloads
# all layers that fit - verified via low RSS (~530MB) after a real generation,
# meaning the model lives in GPU memory, not process RAM.
# -t 8: matches the P-core thread count already tuned on the Windows side for
# this exact CPU.
# -c 24576: same context size as the Windows script (~6GB VRAM budget, solo-server).
# -fa on: flash attention, pinned explicit.
# No --mlock / -lm mlock: this box's ulimit -l is only 8MB (default Fedora/PAM
# limit), so mlock silently fails to lock most of the buffer anyway without a
# sudo + relogin ulimit change. The Windows Gemma script independently found
# mlock risky under memory pressure on this 16GB machine, so mmap-only (default)
# is used here for both models rather than fighting the OS under pressure.
# --temp/--top-p/--top-k/--min-p: Qwen's published Qwen3-4B-Instruct-2507
# non-thinking defaults.
# --reasoning off: this build's reasoning-format defaults to 'auto', detected
# from the chat template. Qwen3's template has a reasoning branch (shared with
# the thinking variant of the model family) even though this Instruct/non-
# thinking checkpoint never emits <think> tags. Auto-detection was flagging it
# as a reasoning model, waiting for a closing think tag that never appears,
# and generation ran away indefinitely instead of stopping (found via
# Open WebUI: a plain "hi" produced 2000+ tokens and never finished). Forcing
# it off makes the server treat all output as plain content again.
# --skip-chat-parsing REMOVED (2026-07-29): originally added because
# --reasoning off alone didn't stop the response-formatting hang described
# above. But --skip-chat-parsing also disables structured tool_calls
# extraction - everything lands in message.content unparsed, which silently
# breaks Open WebUI's native/Builtin Tools agent mode (the model can still
# emit tool-call-shaped text, but Open WebUI never sees a real tool_calls
# field to execute). Directly retested today: --reasoning off alone (no
# skip-chat-parsing), replaying the exact original repro shape (streaming,
# reasoning_format:deepseek explicitly in the request body, a 14-tool
# declaration set matching Open WebUI's real payload size) - no hang, correct
# tool_calls on trigger messages, correct abstention on plain messages, at
# both 2-tool and 14-tool scale. The original hang seems to have needed
# something specific to the no-tools/--reasoning-off-only combination that
# doesn't reproduce once tools are actually in the request - not fully
# explained, but empirically the hang doesn't return with tools present, and
# removing this flag is what makes agent mode functional at all.
#
# GGML_VK_MAX_NODES_PER_SUBMIT=1 (2026-07-29): same iGPU/Vulkan-level fence-
# timeout risk documented and mitigated for Gemma (start-gemma-e4b.sh,
# JOURNAL.md 2026-07-28) applies here too - it's a backend/hardware issue,
# not model-specific. No reason this server should run unprotected just
# because the crash hasn't been observed on this model yet.
#
# Switched to being the primary/production server (2026-07-29): chosen over
# Gemma 4 E4B specifically for agent-mode/tool-calling use, since Gemma's
# chat_format broke (garbage <unused2xxx> token output) once --reasoning off
# was combined with a large Builtin Tools declaration set, while Qwen3
# handled the identical test cleanly. See JOURNAL.md for the full comparison.
#
# NOTE: binds port 8080, same as start-gemma-e4b.sh. Only run one server at a
# time - stop the other first (`pkill -f llama-server`).

BIN="$HOME/LocalAI/llama.cpp/build/bin/llama-server"
MODEL="$HOME/LocalAI/models/Qwen3-4B-Instruct-2507-UD-Q4_K_XL.gguf"

export GGML_VK_MAX_NODES_PER_SUBMIT=1

exec "$BIN" \
  --model "$MODEL" \
  --port 8080 \
  -t 8 \
  -c 24576 \
  -np 1 \
  -fa on \
  -lv 2 \
  --reasoning off \
  --temp 0.7 --top-p 0.8 --top-k 20 --min-p 0
