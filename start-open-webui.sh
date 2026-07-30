#!/usr/bin/env bash
# Open WebUI - chat frontend for the local llama.cpp server.
# Runs as a rootless Podman container.
#
# --network host: llama-server binds to 127.0.0.1:8080 only (not 0.0.0.0), so
# bridge networking + host.containers.internal can't reach it. Host networking
# sidesteps that - the container sees localhost exactly like the host does.
# PORT=3000: Open WebUI defaults to 8080 internally, which would collide with
# llama-server on the host network. Moved to 3000 instead.
# OPENAI_API_KEY: llama-server doesn't check it, but Open WebUI's connection
# form requires a non-empty value to treat the endpoint as configured.
# OPENAI_API_BASE_URLS (plural, semicolon-separated, added 2026-07-30): also
# registers the uncensored model's server (start-qwen3-uncensored.sh, port
# 8081) as a second connection, so it shows up in the model picker without
# reconfiguring Open WebUI each time you switch which llama-server is running.
# The two llama-server processes are still run mutually exclusively (see
# start-qwen3-uncensored.sh's own comment - combined Vulkan memory doesn't fit
# both at once) - whichever one isn't currently running will just show as
# unreachable in the model picker rather than error at Open WebUI's own startup.
# ENABLE_OLLAMA_API=false: no Ollama running on this box; skips its
# unreachable-endpoint warnings in the logs.
# ENABLE_KB_EXEC=true: gives Native-mode models a filesystem-style interface
# (ls/tree/grep/cat) over attached Knowledge instead of just search tools -
# capable models chain this more reliably. No effect on Legacy-mode models,
# and irrelevant until a Knowledge base actually exists, but harmless to set
# now (docs: https://docs.openwebui.com/getting-started/essentials).
# WEBUI_AUTH left at its default (on): with --network host this binds
# 0.0.0.0:3000, reachable from the whole LAN, not just localhost - so the
# first-visit signup/login stays on rather than leaving an open chat UI
# exposed to the network.
#
# First run creates the Podman volume + container. Later runs just restart the
# existing container (fast) unless it's already running.
#
# UI: http://localhost:3000 (first visit creates the local admin account)

CONTAINER=open-webui

if podman container exists "$CONTAINER"; then
  if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER")" = "true" ]; then
    echo "$CONTAINER is already running - http://localhost:3000"
    exit 0
  fi
  echo "Starting existing $CONTAINER container..."
  exec podman start -a "$CONTAINER"
fi

exec podman run -d \
  --name "$CONTAINER" \
  --network host \
  -e PORT=3000 \
  -e OPENAI_API_BASE_URLS="http://localhost:8080/v1;http://localhost:8081/v1" \
  -e OPENAI_API_KEYS="sk-no-key-required;sk-no-key-required" \
  -e ENABLE_OLLAMA_API=false \
  -e ENABLE_KB_EXEC=true \
  -v open-webui-data:/app/backend/data \
  ghcr.io/open-webui/open-webui:main
