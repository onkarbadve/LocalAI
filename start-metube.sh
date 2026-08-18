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
# Managed by systemd/Quadlet (~/.config/containers/systemd/metube.container)
# since 2026-08-14 - see JOURNAL.md that date. Config changes go in that unit
# file (+ `systemctl --user daemon-reload`), not this script.
#
# UI: http://localhost:8083

if systemctl --user is-active --quiet metube.service; then
  echo "metube is already running - http://localhost:8083"
  exit 0
fi

systemctl --user start metube.service
echo "metube started - http://localhost:8083"
