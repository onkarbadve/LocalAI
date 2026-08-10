#!/usr/bin/env bash
#
# Purpose: launch Qwen3-8B (OpenVINO IR, INT4) via OpenVINO Model Server (OVMS)
#   on the Intel iGPU, OpenAI-compatible API on port 8084. This is the
#   OpenVINO-backend counterpart to the llama.cpp/Vulkan chat servers
#   (start-qwen3-uncensored.sh / start-gemma-uncensored.sh as of 2026-08-05;
#   was start-qwen3.sh before that script and its censored model were
#   deleted) - see JOURNAL.md 2026-08-02 for why both backends exist
#   (OpenVINO evaluation) and the bugs hit standing this up.
# Requires: podman; the `docker.io/openvino/model_server:latest-gpu` image
#   (already pulled - see `podman images`); the converted IR at
#   ~/LocalAI/openvino-test/qwen3-8b-int4-ov (NOT a GGUF - a separate
#   HF->OpenVINO conversion, see JOURNAL.md); an Intel iGPU exposing
#   /dev/dri/renderD128.
# Arguments: none. Model path, port, and OVMS flags are fixed below - edit
#   the script directly to change them.
# Expected output: runs detached (podman -d); REST server up within ~10s
#   (compiling the graph takes longer than starting the process) - check
#   `podman logs ovms-qwen3-8b` for "state changed to: AVAILABLE" before
#   sending requests.
# Typical usage: ./start-ovms-qwen3-8b.sh   (then curl or point Open WebUI
#   at http://127.0.0.1:8084/v3)
# Failure cases: fails to bind if another OVMS container (e.g. a TinyLlama
#   instance) already holds port 8084 - only one OVMS container runs at a
#   time on this box; `podman stop <name>` the other one first. A container
#   that starts but never reaches AVAILABLE in the logs usually means the
#   iGPU device node isn't visible (`/dev/dri` missing/permission) or the
#   IR directory path is wrong.
#
# :Z on the bind mount: same SELinux reasoning as start-metube.sh - Fedora
# enforces by default, and a bind-mounted host directory keeps its
# `user_home_t` context unless relabeled, which a container process is
# confined away from regardless of UID/GID. Named volumes don't need this;
# bind mounts of existing host directories do.
#
# --reasoning_parser qwen3 / --tool_parser hermes3: Qwen3 is a hybrid
# thinking model - without these, <think> blocks and tool calls land as raw
# text in `content` instead of the structured `reasoning_content`/
# `tool_calls` fields Open WebUI expects.
#
# Port 8084: chosen because 8080-8082 are the llama-server scripts, 8083 is
# MeTube, 8888 is SearXNG, 3000 is Open WebUI.
#
# No --cache_dir: the model directory is mounted read-only, so a cache path
# under it isn't writable (OVMS logs a harmless warning and falls back to
# recompiling kernels each load, ~13s cold - see JOURNAL.md). A separate
# writable cache volume would fix this but hasn't been set up.
#
# enable_thinking default: Qwen3-8B pays a full <think> pass on every
# request unless the caller sends `chat_template_kwargs:
# {"enable_thinking": false}` - JOURNAL.md 2026-08-02 found this cut
# response time from 40-110s to ~1.3s bare / ~9.5s through Open WebUI's
# tool-declaration payload. Not baked into this script (that's a per-caller
# request option, or an Open WebUI model-params setting) - just flagging it
# so a fresh caller isn't surprised by slow first responses.

CONTAINER=ovms-qwen3-8b
MODEL_DIR="$HOME/LocalAI/openvino-test/qwen3-8b-int4-ov"

if podman container exists "$CONTAINER"; then
  if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER")" = "true" ]; then
    echo "$CONTAINER is already running - http://127.0.0.1:8084/v3"
    exit 0
  fi
  echo "Starting existing $CONTAINER container..."
  exec podman start -a "$CONTAINER"
fi

exec podman run -d \
  --name "$CONTAINER" \
  --device /dev/dri \
  -p 127.0.0.1:8084:8084 \
  -v "$MODEL_DIR:/models/qwen3-8b:ro,Z" \
  docker.io/openvino/model_server:latest-gpu \
  --port 9000 --rest_port 8084 \
  --model_name qwen3-8b --model_path /models/qwen3-8b \
  --task text_generation --target_device GPU \
  --reasoning_parser qwen3 --tool_parser hermes3
