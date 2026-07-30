#!/usr/bin/env bash
# Open Terminal - remote shell/file API, wired into Open WebUI as an
# Integration (Admin Settings -> Integrations -> Open Terminal), giving
# chat models a place to actually execute the code they write.
#
# Runs as a rootless Podman container, bridge networking (unlike
# start-open-webui.sh's --network host):
# -p 127.0.0.1:8000:8000: published to loopback only. Open WebUI's backend
# proxies all requests to the terminal (per upstream docs: "the terminal only
# needs to be reachable from the server"), so there's no reason to expose a
# raw shell API to the LAN the way port 3000 is - unlike the chat UI, this
# has no login page in front of it, only the API key.
# Image: slim variant (~430MB Debian base: git/curl/jq) rather than the
# ~4GB `latest` (full Node/gcc/ffmpeg/LaTeX/data-science toolkit) or the
# ~230MB alpine variant - matches the mmap-not-mlock, mind-the-footprint
# posture already used for the llama.cpp scripts on this 16GB box. Swap the
# tag to `latest` if heavier tooling (npm builds, compilers) turns out to be
# needed.
# API key: generated once with `openssl rand -hex 32`, stored at
# ~/.config/open-terminal/api-key (chmod 600), read at container start -
# not hardcoded here.
#
# First run creates the Podman volume + container. Later runs just restart
# the existing container (fast) unless it's already running.
#
# After starting: Open WebUI -> Admin Settings -> Integrations -> Open
# Terminal -> URL http://localhost:8000, API key from the file above.

CONTAINER=open-terminal
KEY_FILE="$HOME/.config/open-terminal/api-key"

if [ ! -f "$KEY_FILE" ]; then
  echo "No API key found at $KEY_FILE - generate one first:" >&2
  echo "  mkdir -p ~/.config/open-terminal && chmod 700 ~/.config/open-terminal" >&2
  echo "  openssl rand -hex 32 > $KEY_FILE && chmod 600 $KEY_FILE" >&2
  exit 1
fi

if podman container exists "$CONTAINER"; then
  if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER")" = "true" ]; then
    echo "$CONTAINER is already running - http://localhost:8000"
    exit 0
  fi
  echo "Starting existing $CONTAINER container..."
  exec podman start -a "$CONTAINER"
fi

exec podman run -d \
  --name "$CONTAINER" \
  -p 127.0.0.1:8000:8000 \
  -e OPEN_TERMINAL_API_KEY="$(cat "$KEY_FILE")" \
  -v open-terminal-data:/home/user \
  ghcr.io/open-webui/open-terminal:slim
