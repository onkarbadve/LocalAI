#!/usr/bin/env bash
# MeTube - web UI for yt-dlp. Runs as a rootless Podman container.
#
# Same download folder as the CLI (~/Videos/yt-dlp): files saved from the
# browser UI and from `yt-dlp` on the command line end up in one place, no
# duplicate libraries.
#
# :Z on the bind mount (added 2026-08-01): the real cause of an initial
# "Permission denied" on /downloads wasn't UID/GID mapping (tried and ruled
# that out first) - it was SELinux. Fedora enforces by default, and
# ~/Videos/yt-dlp carries the `user_home_t` context, which a container
# process (running as `container_t`) is confined away from regardless of
# numeric UID/GID matching. `:Z` tells Podman to relabel the path to
# `container_file_t` (private to this container) at mount time. This is
# specific to bind-mounting an existing host directory - open-webui-data and
# searxng-data never hit this because named volumes get the correct label
# from Podman automatically.
#
# Port 8083: 8080/8081/8082 are the llama-server scripts, 8888 is SearXNG,
# 3000 is Open WebUI - picked the next free slot.
#
# YTDL_OPTIONS mirrors ~/.config/yt-dlp/config's format/retry preferences
# (JSON here since MeTube passes this straight to yt-dlp's Python API, not
# its CLI parser - key names differ slightly from CLI flags). Thumbnail/
# metadata embedding intentionally left off here - MeTube's own UI already
# has per-download checkboxes for those, no need to hardcode them.
#
# First run creates the Podman volume + container. Later runs just restart
# the existing container (fast) unless it's already running.
#
# UI: http://localhost:8083

CONTAINER=metube

if podman container exists "$CONTAINER"; then
  if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER")" = "true" ]; then
    echo "$CONTAINER is already running - http://localhost:8083"
    exit 0
  fi
  echo "Starting existing $CONTAINER container..."
  exec podman start -a "$CONTAINER"
fi

exec podman run -d \
  --name "$CONTAINER" \
  -p 127.0.0.1:8083:8081 \
  -v /home/onkar/Videos/yt-dlp:/downloads:Z \
  -e YTDL_OPTIONS='{"format":"bestvideo+bestaudio/best","merge_output_format":"mp4","restrictfilenames":true,"retries":10,"fragment_retries":10,"concurrent_fragment_downloads":4}' \
  ghcr.io/alexta69/metube
