#!/usr/bin/env bash
# SearXNG - self-hosted metasearch engine, backs Open WebUI's "Web Search"
# chat toggle (see start-open-webui.sh). Runs as a rootless Podman container.
#
# Local-first choice: queries stay on this box and its upstream engines
# rather than going through a third-party search API (Tavily/Serper/Brave)
# that would see every query the model gets asked to look up.
#
# -p 127.0.0.1:8888:8080: loopback-only. This is a backend JSON API for
# Open WebUI, not a UI meant for direct/LAN use (no auth in front of it).
# Open WebUI reaches it via plain localhost even though open-webui itself
# runs with --network host - a published container port is visible on the
# host's loopback either way.
#
# -v searxng-data (named volume, not a bind mount): rootless Podman's UID
# mapping made a host bind-mount unwritable by the container's internal user
# (chown via `podman unshare` didn't line up with the image's actual uid) -
# a named volume sidesteps that entirely, same pattern as open-webui-data.
#
# search.formats [html, json] (baked into the volume's settings.yml, added
# 2026-08-01): SearXNG ships with the JSON API disabled by default (it's
# meant to be scraped by clients like this, not exposed openly) - Open
# WebUI's SEARXNG_QUERY_URL needs `&format=json` support to parse results,
# so this was added via `podman cp` into /etc/searxng/settings.yml on first
# run. If this volume is ever recreated from scratch, that edit needs
# redoing (see JOURNAL.md 2026-08-01) or Web Search will fail silently.
#
# Managed by systemd/Quadlet (~/.config/containers/systemd/searxng.container)
# since 2026-08-14 - see JOURNAL.md that date. Config changes go in that unit
# file (+ `systemctl --user daemon-reload`), not this script. The
# settings.yml JSON-format edit above lives in the searxng-data volume,
# untouched by this migration.
#
# API: http://localhost:8888/search?q=<query>&format=json

if systemctl --user is-active --quiet searxng.service; then
  echo "searxng is already running - http://localhost:8888"
  exit 0
fi

systemctl --user start searxng.service
echo "searxng started - http://localhost:8888"
