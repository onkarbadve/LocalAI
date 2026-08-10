NDJSON Journal — one JSON object per line. Newest entries first.

Schema (fields):
- date: ISO 8601 date (YYYY-MM-DD)
- time: optional ISO 8601 time (HH:MM:SS) or timestamp
- title: short title
- tldr: one-line summary
- goal: short goal string
- changes: array of strings (files/commands/flags changed)
- results: array of strings (what was verified)
- problems: array of strings (issues encountered)
- lessons: array of strings (generalizable takeaways)
- next_steps: array of strings (followups)
- tags: array of short tags
- refs: array of URLs or strings (issues/PRs/file links)
- metadata: object for arbitrary structured info (benchmarks, ports, pids, models, services)

How agents should use this file:
- Append a single JSON object (compact, single-line) representing a completed session.
- Newest entries SHOULD be prepended (but appending is acceptable if enforced post-processing sorts by date). To keep append-only and safe for concurrent writers, agents SHOULD append lines and include `date` and an `entry_id` if necessary. A nightly job can re-sort into newest-first order if required.

Example entries (two most recent converted from legacy):

{"date":"2026-08-11","title":"Moved the arr stack to RPi5","tldr":"arr stack migrated to always-on RPi5; containers removed from this box","goal":"Move Sonarr/Radarr/Prowlarr/qBittorrent/FlareSolverr to RPi5","changes":["stopped rootless podman containers: sonarr, radarr, prowlarr, qbittorrent, flaresolverr","deleted Quadlet unit files in ~/.config/containers/systemd/"],"results":["Verified each app via API (/api/v3/health)","No configs referenced this box's Tailscale IP/hostname"],"problems":[],"lessons":["Offload always-on services to an always-on device to reduce local uptime demands"],"next_steps":[],"tags":["podman","rpi","arr-stack"],"refs":[],"metadata":{"migrated_to":"raspberrypi-pi5","verify_method":"api_endpoints"}}

{"date":"2026-08-09","title":"Disk cleanup: root at 91%","tldr":"Recovered ~11GB by deleting caches and rebuildable venvs; some scripts now point at missing paths","goal":"Free root space before outage","changes":["deleted openvino-test/ov_cache (4.7G)","deleted openvino-test/venv (308M)","deleted two coredumps"],"results":["root free space improved from 5.2G to 16G (df -h /)"],"problems":["start-ovms-qwen3-8b.sh hardcodes MODEL_DIR path that no longer exists"],"lessons":[],"next_steps":["decide whether to delete or repoint start-ovms-qwen3-8b.sh"],"tags":["disk","cleanup","openvino"],"refs":[],"metadata":{"freed_bytes":11000000000}}

# Append guidelines for agents
- Write a single-line JSON object and append to this file.
- Required fields: date, title, goal, changes, results.
- Optional: tldr, problems, lessons, next_steps, tags, refs, metadata.
- Use arrays of short strings for list fields; keep messages concise.

# Helper script (scripts/add_journal_entry_ai.sh) is included in the repo for convenience.
