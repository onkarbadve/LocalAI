#!/usr/bin/env bash
#
# Purpose: launch Qwen3.5-9B (OpenVINO IR, INT4) via OpenVINO Model Server
#   (OVMS) on the Intel iGPU, OpenAI-compatible API on port 8085. This is
#   the TEXT half of a deliberate two-instance split with
#   start-ovms-qwen3.5-9b-vision.sh - see that script's header for why:
#   OVMS has no per-component device flag, and Qwen3.5-9B's GPU
#   vision-merger hallucination bug (openvino#37223, unfixed upstream)
#   means only text should ever be sent here. Send image/vision requests
#   to the CPU instance on port 8086 instead - don't send them to this one.
# Requires: podman; the `docker.io/openvino/model_server:weekly` image
#   (main-branch dev build - the closest thing OVMS has to "nightly"; no
#   tag literally called that exists on Docker Hub as of 2026-08-04); the
#   pre-converted IR at ~/LocalAI/models/Qwen3.5-9B-int4-ov (downloaded
#   from OpenVINO/Qwen3.5-9B-int4-ov on HF, NOT exported locally); an
#   Intel iGPU exposing /dev/dri/renderD128.
#
# UNVERIFIED - test before trusting this model through this server:
#   1. Runtime version. Qwen3.5's hybrid linear/full attention GPU kernels
#      needed OpenVINO nightly (dev20260603+) to avoid CL_OUT_OF_RESOURCES
#      (openvino#36151) - confirmed via openvino_genai directly in
#      test_ov_qwen.py using the `ov-env` nightly venv (dev20260803).
#      Whether OVMS's `weekly` image (built from main, refreshed every
#      few days) bundles an OpenVINO runtime new enough is NOT checked -
#      OVMS's own release cadence for its internal OpenVINO dependency is
#      independent of the openvino PyPI nightly wheels. If container logs
#      show CL_OUT_OF_RESOURCES or it never reaches AVAILABLE, this image
#      still isn't new enough - fall back to serving via the ov-env venv
#      directly (see test_ov_qwen.py) instead of OVMS.
#   2. VLM support in OVMS's --task text_generation graph for this
#      multi-component IR (openvino_language_model +
#      openvino_text_embeddings_model + three openvino_vision_embeddings*
#      files) - expected to load automatically, not confirmed end-to-end.
#   3. --reasoning_parser qwen3 was proven for Qwen3-8b's chat template,
#      not separately re-verified against Qwen3.5-9B's (also a hybrid
#      thinking model per test_ov_qwen.py, so expected to apply the same
#      way, just not confirmed through OVMS).
#
# Port 8085: 8080-8082 are llama-server scripts, 8083 MeTube, 8084 is the
# Qwen3-8b OVMS instance, 8086 is this model's CPU/vision counterpart,
# 8888 SearXNG, 3000 Open WebUI.
#
# :Z on the bind mount: same SELinux reasoning as start-ovms-qwen3-8b.sh -
# Fedora enforces by default, bind mounts need relabeling for the
# container's confined process to read them.
#
# --cache_dir (added 2026-08-04, tuning pass): writable named volume for
# compiled-kernel cache, separate from the read-only model mount. Without
# this, OVMS recompiles GPU kernels from scratch on every cold start
# (~26s for this model) - same gap flagged (never fixed) for
# start-ovms-qwen3-8b.sh back on 2026-08-02. Uses a named volume, not a
# bind-mounted host directory - same reason as open-webui-data/searxng-data
# (see start-searxng.sh): rootless Podman's UID mapping makes a
# bind-mounted host dir unwritable by the container's internal user. A
# first attempt with a bind mount confirmed this the hard way - "Cache
# directory /cache is not writable; access() result: -1" in the logs.
#
# --kv_cache_precision u8: roughly halves per-sequence KV cache memory
# for a usually-negligible accuracy cost (only affects cached
# activations, not model weights) - directly raises how many concurrent
# requests fit before the cache pool fills up.
#
# --cache_size 2: pins the KV cache pool at 2GB instead of the default
# dynamic (0 = grow-on-demand) allocation. Without this, capacity is
# whatever the pool happens to grow to under load (measured emergently
# at ~493.7MB / ~15 concurrent short requests on 2026-08-04) rather than
# a deliberate, predictable number. 2GB chosen conservatively given this
# box measured ~4.3GB available under concurrent-request load with the
# other pods (searxng/open-terminal/open-webui) already running - leaves
# headroom rather than maximizing for cache size alone.
#
# --metrics_enable: exposes ovms_request_time_us/ovms_inference_time_us
# on the REST port so the effect of the above is actually measurable,
# not guessed at - same approach used to diagnose qwen3-8b's thinking-mode
# slowness on 2026-08-02.
#
# Memory note: this box OOM'd once from loading two device-targeted
# copies of an 8B model at once (JOURNAL 2026-08-03). Running this AND
# the vision/CPU instance simultaneously means ~2x this model's weights
# resident (~5-9GB each depending on precision) on a 16GB box - check
# `free -h` before starting both, and stop whichever instance isn't
# actively needed rather than leaving both up by default.
#
# Arguments: none. Typical usage: ./start-ovms-qwen3.5-9b-text.sh, then
# check `podman logs ovms-qwen3.5-9b-text` for "state changed to:
# AVAILABLE" before sending requests, then curl or point Open WebUI at
# http://127.0.0.1:8085/v3 - text prompts only.

CONTAINER=ovms-qwen3.5-9b-text
MODEL_DIR="$HOME/LocalAI/models/Qwen3.5-9B-int4-ov"
CACHE_VOLUME=ovms-qwen3.5-9b-text-cache

if podman container exists "$CONTAINER"; then
  if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER")" = "true" ]; then
    echo "$CONTAINER is already running - http://127.0.0.1:8085/v3"
    exit 0
  fi
  echo "Starting existing $CONTAINER container..."
  exec podman start -a "$CONTAINER"
fi

exec podman run -d \
  --name "$CONTAINER" \
  --device /dev/dri \
  -p 127.0.0.1:8085:8085 \
  -v "$MODEL_DIR:/models/qwen3.5-9b:ro,Z" \
  -v "$CACHE_VOLUME:/cache" \
  docker.io/openvino/model_server:weekly \
  --port 9001 --rest_port 8085 \
  --model_name qwen3.5-9b-text --model_path /models/qwen3.5-9b \
  --task text_generation --target_device GPU \
  --reasoning_parser qwen3 --tool_parser hermes3 \
  --cache_dir /cache --kv_cache_precision u8 --cache_size 2 \
  --metrics_enable
