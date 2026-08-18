#!/usr/bin/env bash
#
# Purpose: launch Qwen3.5-9B (OpenVINO IR, INT4) via OpenVINO Model Server
#   (OVMS) on CPU, pinned to P-cores only, OpenAI-compatible API on port
#   8086. This is the VISION half of a deliberate two-instance split with
#   start-ovms-qwen3.5-9b-text.sh.
#
# Why two instances instead of one: OVMS only exposes a single
# --target_device flag per model - there is no documented way to pin the
# vision-embeddings sub-graph to CPU while the language model runs on
# GPU within one servable (checked export_model.py's flags and the OVMS
# VLM/parameters docs directly - only a single global --target_device
# exists, matching JOURNAL's earlier finding that HETERO/AUTO can't
# split one request across devices on this stack either). Qwen3.5-9B's
# GPU vision-merger hallucination bug (openvino#37223, root-caused
# 2026-08-04, unfixed upstream) means the ONLY way to get correct
# image-understanding answers right now is to keep vision off the GPU
# entirely - hence a second, CPU-only instance. Send image/vision
# requests here; send text-only requests to the GPU instance on 8085
# instead (faster, and this model is a genuine hybrid thinking model, so
# CPU-only would pay a real speed cost across every request if used for
# everything).
#
# Why P-cores only (logical CPUs 0-7): confirmed via `lscpu -e` on this
# box - CPUs 0-7 are the 4 P-cores (4500MHz max, hyperthreaded), CPUs
# 8-15 are the 8 E-cores (3300MHz max, no HT). Pinning avoids the
# scheduler spreading OpenVINO's CPU inference threads onto the slower
# E-cores. UNVERIFIED: whether OpenVINO's CPU plugin thread pool
# actually respects the container's cgroup cpuset affinity mask
# out-of-the-box (expected on Linux via sched_getaffinity, not
# separately confirmed for this OVMS image) - check `htop`/`podman top`
# during a real request to confirm only CPUs 0-7 are active; if E-cores
# also light up, an explicit thread-count env var would be needed on top
# of --cpuset-cpus.
#
# Requires: podman; the `docker.io/openvino/model_server:weekly` image
#   (see start-ovms-qwen3.5-9b-text.sh header for why `weekly`, not a
#   literal "nightly" tag, and why even that isn't a confirmed-sufficient
#   runtime version); the pre-converted IR at
#   ~/LocalAI/models/Qwen3.5-9B-int4-ov. No /dev/dri needed - CPU only.
#
# Port 8086: see start-ovms-qwen3.5-9b-text.sh's port map comment.
#
# :Z on the bind mount: same SELinux reasoning as start-ovms-qwen3-8b.sh.
#
# No --cache_dir: same tradeoff as the other OVMS scripts here.
#
# Memory note: see start-ovms-qwen3.5-9b-text.sh - running this
# alongside the GPU/text instance means ~2x this model's weights
# resident on a 16GB box that has OOM'd once before from a similar
# double-load (JOURNAL 2026-08-03). Check `free -h` first; stop whichever
# instance isn't actively in use rather than leaving both up by default.
#
# Arguments: none. Typical usage: ./start-ovms-qwen3.5-9b-vision.sh, then
# check `podman logs ovms-qwen3.5-9b-vision` for "state changed to:
# AVAILABLE" (expect a longer cold start than the GPU instance - CPU
# kernel compilation for a 9B model, not measured), then curl or point
# Open WebUI at http://127.0.0.1:8086/v3 - vision/image prompts only.

# Managed by systemd/Quadlet (~/.config/containers/systemd/ovms-qwen3.5-9b-vision.container)
# since 2026-08-14 - see JOURNAL.md that date. Not [Install]-enabled (still
# written-but-never-launched/tested - keep it that way until someone
# verifies it end-to-end). AutoUpdate=local, same :weekly-tag reasoning as
# start-ovms-qwen3.5-9b-text.sh. Edit the unit file (+
# `systemctl --user daemon-reload`) to change flags.

if systemctl --user is-active --quiet ovms-qwen3.5-9b-vision.service; then
  echo "ovms-qwen3.5-9b-vision is already running - http://127.0.0.1:8086/v3"
  exit 0
fi

systemctl --user start ovms-qwen3.5-9b-vision.service
echo "ovms-qwen3.5-9b-vision started - http://127.0.0.1:8086/v3"
