# Legacy human-readable JOURNAL (archived)

This file contains the original human-readable JOURNAL.md contents preserved verbatim for historical/context purposes. The active machine-readable NDJSON journal is at JOURNAL.md.


# Original JOURNAL.md

# Local AI Journal

Running log of changes, fixes, and incidents for the `~/LocalAI` (and `C:\LocalAI`) setup. Newest entries at the top. For static reference (hardware, models, flags), see [SETUP.md](SETUP.md). For the [...]

**Entry format going forward** (not retroactively applied to entries below — this is a template for new ones, added per [AGENTS.md](AGENTS.md)'s documentation-update rules):

> ## Date — short title
>
> **Goal**: what this session set out to do.
> **Changes**: what was actually changed (scripts, config, flags).
> **Results**: what was verified working, with how it was verified.
> **Problems**: anything hit along the way, including dead ends.
> **Lessons**: what this session taught, if generalizable — candidate for [docs/lessons-learned.md](docs/lessons-learned.md).
> **Next steps**: anything left open.

Older entries below predate this template and stay in their original free-form narrative style — don't retroactively reformat them, per [AGENTS.md](AGENTS.md#repository-philosophy) (the journal's ho[...]

---

## 2026-08-11 — Moved the arr stack (Sonarr/Radarr/Prowlarr/qBittorrent/FlareSolverr) off this box, to the RPi5

**Goal**: this box isn't kept up 24/7, but the arr stack needs to be — move it to the always-on RPi5 (unrelated to LLM serving, but touches this box's `~/.config/containers/systemd/` and `~/media-st[...]

**Changes**: stopped and removed the 5 rootless-Podman containers (`sonarr`/`radarr`/`prowlarr`/`qbittorrent`/`flaresolverr`), deleted their Quadlet unit files (`~/.config/containers/systemd/{sonarr,r[...]

**Results**: verified via each app's own API (`/api/v3/health` etc., not just an HTTP 200 on `/`) that the Pi copy is healthy, and that no config referenced this box's Tailscale IP/hostname (all cross[...]

**Next steps**: none on this box. Pi-side follow-ups (USB storage, boot-persistence reboot test) are tracked in that memory, not here.

**Update, same day**: the boot-persistence reboot test is now confirmed — the arr-stack's `restart=always` + `podman-restart.service` setup survived not just a plain reboot but the Pi's full bookwor[...]

---

## 2026-08-09 — Disk cleanup: root filesystem was at 91% (5.2G free)

**Goal**: root (`/`, 54G total) was down to 5.2G free — free up space before it becomes an outage.

**Changes**: deleted `openvino-test/ov_cache/` (4.7G, OpenVINO compiled-kernel cache — regenerates automatically on next OVMS run) and `openvino-test/venv/` (308M, rebuildable). Deleted `openvino-te[...]

**Results**: root free space went from 5.2G (91% used) to 16G (71% used), verified with `df -h /`.

**Problems**: `start-ovms-qwen3-8b.sh` hardcodes `MODEL_DIR="$HOME/LocalAI/openvino-test/qwen3-8b-int4-ov"` (line 58) — that path no longer exists, so the script is now dead/broken. Left as-is pendi[...]

**Next steps**: decide whether to delete `start-ovms-qwen3-8b.sh` (dead now) or repoint it; still undecided: `~/recovered-core2duo-2015/` (2.1G, old recovered data) and duplicate podman images `openvi[...]

---

## 2026-08-07 — Key-only SSH access to Fedora and RPi5 from Android/Termius

**Goal**: reach both the Fedora box and the RPi5 (Pi-hole) over SSH from an Android phone via Termius, password auth disabled everywhere.

**Changes**: enabled and started `sshd` on Fedora (was installed but inactive); added `/etc/ssh/sshd_config.d/99-key-only.conf` with `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `Pu[...]

**Results**: Termius connects to Fedora (`100.93.33.122`) and RPi5 (`100.102.227.7`) over Tailscale using key auth only, per the user's own confirmation ("i am in" / "done"). RPi5's sshd was already k[...]

**Problems**: first connection attempt from Termius hung on "trying to connect" — cause was the phone's Tailscale client itself showing `offline` in `tailscale status` (backgrounded/killed by Androi[...]

**Lessons**: when an SSH connection over Tailscale hangs rather than failing fast, check `tailscale status` for the *client* device before touching sshd/firewall config — a phone's Tailscale VPN get[...]

**Next steps**: run `sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin'` on Fedora directly (interactive sudo) to confirm the drop-in's effective config, rather than relying on inference [...]

---

## 2026-08-06 — Arr stack (Sonarr/Radarr/Prowlarr/qBittorrent/FlareSolverr) stood up as rootless Podman containers

*Backfilled from Claude memory — this work happened in a separate session that predates this journal entry.*

**Goal**: get a media-management stack running on the same Fedora box as the LLM servers, alongside the existing Pi-hole/Tailscale and LLM-serving setups.

**Changes**: five rootless Podman containers, all `--network host` (same host-networking pattern already used for Open WebUI, so ports below are real host ports, not published mappings): `sonarr` (`li[...]

**Results**: all five containers created and running as of setup.

**Problems**: none logged.

**Lessons**: none logged.

**Next steps**: not yet checked whether any of these are additionally reachable over Tailscale — host networking plus `tailscale0` already sitting in firewalld's `trusted` zone (see the 2026-07-29 e[...]

---

## 2026-08-06 — Pi-hole phone DNS override re-enabled and confirmed routing

*Backfilled from Claude memory — this work happened in a separate session that predates this journal entry.*

**Goal**: resolve the fork left open in the 2026-07-29 Tailscale entry below — re-enable the Android phone's Tailscale "Override local DNS" (turned off earlier to avoid fighting a NextDNS Private DN[...]

**Changes**: re-enabled Tailscale DNS override on the phone (`a34`).

**Results**: confirmed via Pi-hole's own query log — client `100.69.158.115` (the phone's tailnet IP) actively querying. This holds on any network (home WiFi or mobile data), since Tailscale DNS ove[...]

**Problems**: none — this was the direct resolution of option (b) from the 2026-07-29 entry's open fork (add Pi-hole as Global Nameserver + re-enable override), rather than settling for option (a) ([...]

**Lessons**: none beyond what's already in the 2026-07-29 entry.

**Next steps**: none for this specific fix.

---

## 2026-08-05 — RPi5 stood up as dedicated Pi-hole + Tailscale DNS box for the whole tailnet

*Backfilled from Claude memory — this work happened in a separate session that predates this journal entry.*

**Goal**: stand up ad-blocking DNS for every device on the tailnet, on a separate physical box rather than the LLM-serving Fedora machine.

**Changes**: Raspberry Pi 5 (hostname `raspberrypi`, Raspberry Pi OS **with Desktop** 64-bit, Debian 12 "bookworm", kernel `6.12.47+rpt-rpi-2712`, no Docker/Podman) running Pi-hole v6 bare-metal, upst[...]

**Results**: Pi-hole dashboard (`/admin/`, self-signed cert, 47-day auto-renewal) reachable over Tailscale via both raw tailnet IP and MagicDNS name (`raspberrypi-pihole.tail2f4a36.ts.net`). SSH worki[...]

**Problems**: none logged for the initial build.

**Lessons**: `pihole-FTL` listens on `0.0.0.0:80`/`0.0.0.0:443` (all interfaces) with an empty (allow-all) ACL, and the Pi runs no host firewall (no ufw/firewalld) — the only thing actually restrict[...]

**Next steps**: planned reflash to Raspberry Pi OS **Lite** (64-bit, trixie-based) to drop the unused desktop stack (the Pi is managed SSH-only; the desktop environment is installed but never used) ��[...]

---

## 2026-08-05 — Formal PP/TG benchmark of both production llama-server instances

**Goal**: replace the incidental, single-observation tok/s figures for the two production models with a real, repeatable benchmark.

**Changes**: wrote `bench-llama-server.py` (repo root) — hits a running `llama-server`'s native `/completion` endpoint, 1 warmup + 5 timed runs per phase, `cache_prompt:false` for clean prompt-proce[...]

**Results**:
- Qwen3-4B-Instruct-2507-heretic-av2 (port 8081): PP 150.26 ± 0.34 tok/s (600 tok prompt), TG 10.41 ± 0.03 tok/s (128 forced tokens), 680MB RSS.
- Gemma-4-E4B-Uncensored-HauhauCS-Aggressive (port 8082): PP 100.61 ± 0.34 tok/s (601 tok prompt), TG 7.34 ± 0.01 tok/s (128 forced tokens), 3.07GB RSS (bigger footprint from `--swa-full` + q8_0 KV [...]
- Both runs clean — zero new `gpu-fence-alerts.log` entries, no errors in either server log.
- `docs/benchmarks.md` updated with a dedicated formal-benchmark section; two TODO items closed (formal PP numbers, a scripted harness for the llama.cpp side).

**Next steps**: no GPU-memory (Vulkan-visible) figures measured directly, only RSS. A combined harness spanning both llama.cpp and OVMS backends still doesn't exist (`test_ov_qwen.py` remains separate[...]

---

## 2026-08-05 — Censored models deleted from Fedora; `start-qwen3.sh`/`start-gemma-e4b.sh` removed and every doc reference synced

**Goal**: user confirmed only uncensored models are being kept on this Fedora box going forward (censored `Qwen3-4B-Instruct-2507`, `gemma-4-E4B-it` + `mmproj-F16.gguf` had already been deleted from `[...]

**Changes**:
- Deleted `start-qwen3.sh` and `start-gemma-e4b.sh` (both pointed at model files that no longer exist).
- `start-open-webui.sh`: dropped port 8080 from `OPENAI_API_BASE_URLS`/`OPENAI_API_KEYS` (2 URLs now, not 3) and updated its comments accordingly. **Not yet applied to the live container** — `OPENAI[...]
- `start-qwen3-uncensored.sh` / `start-gemma-uncensored.sh`: added a `STATUS (2026-08-05)` banner at the top of each noting they're now the sole production server for their respective model family, an[...]
- `SETUP.md`: directory layout, "Models in production" table, and the two Fedora/Windows per-script comparison tables (Qwen3 solo-chat, Gemma vision-chat) all updated — Fedora columns marked histori[...]
- `README.md`: Quick Start, directory tree, and benchmarks summary table updated to the 2-script/2-port lineup.
- `docs/architecture.md`: mermaid diagram's third node (`llama-server: Qwen3-4B, :8080 (production)`) removed, `×3 registered` → `×2`, "Three chat models registered" design-decision bullet → "Tw[...]
- `docs/troubleshooting.md`: the port-conflict entry now separates a Windows cause (still real, `Start-Server.bat`/`Start-Server-Gemma4-E4B.bat` both bind 8080) from a Fedora cause (historical only ��[...]
- `docs/models.md`: comparison table rows for the two deleted models struck through and marked deleted; the two uncensored variants' rows updated from "Secondary"/no explicit status to **Production**,[...]
- `docs/benchmarks.md`: left the historical per-model rows as originally measured (per this repo's stated policy of not retroactively editing recorded history) but added one clarifying note at the top[...]

**Results**: `grep -rl` for the deleted script names and deleted model filenames across all `.md`/`.sh` files came back clean except for (a) intentional historical/cross-reference mentions inside the [...]

**Problems**: none technical — this was a documentation-consistency sweep, not a code change. The main risk was scope creep (how far to chase "this file mentions a deleted script" across the repo) �[...]

**Lessons**: deleting a file that many other docs point to is not a single-file operation in a repo this cross-referenced — `grep -rl <name>` across the whole tree before considering a deletion "don[...]

**Next steps**: decide whether to recreate the `open-webui` container now (`podman rm open-webui` then rerun `start-open-webui.sh`) so its baked-in `OPENAI_API_BASE_URLS` drops the dead port-8080 entr[...]

---

## 2026-08-05 — Fedora `llama.cpp` updated to latest upstream (`d2a8182` → `61881b1`), three local crash-prevention patches carried forward

**Goal**: update the Fedora source build of `llama.cpp` to the latest upstream, since it had been sitting 143 commits behind (`d2a8182`, 2026-07-26) with no version-tracking discipline like the Window[...]

**Changes**: before touching anything, confirmed the working tree had zero local commits ahead of `origin/master` (`git log origin/master..HEAD` = 0) — only uncommitted patches to three files (`ggml[...]

**Results**:
- **Checked whether upstream had since fixed any of the three bugs before reapplying** (grepped `origin/master`'s versions of the same call sites) — none had; all three are still needed.
- Reconfigured (`cmake -B build`) and rebuilt just the `llama-server` target (the only binary any script here actually references — confirmed via `grep -rl "build/bin/llama-server" across all `star[...]
- **Smoke-tested end-to-end**, not just a version-string check: launched `start-qwen3-uncensored.sh` (the only script pointing at a model file that still exists on disk — `start-qwen3.sh`'s `Qwen3-4[...]
- Updated SETUP.md's patch note (previously said "two" patches — Gemma-specific working memory that had gone stale since the third, `ggml-vulkan.cpp` patch was added the same day (2026-07-28, later [...]

**Problems**: none — the update was uneventful. The three patches being small, self-contained `try/catch` wraps (rather than deep logic changes) is almost certainly why they merged cleanly despite r[...]

**Lessons**: `git stash` / fast-forward / `git stash pop` is sufficient for carrying small local patches across a large upstream jump (143 commits, 343 files) as long as there are zero local commits d[...]

**Next steps**: none of the three patches have been filed upstream yet (still true as of this entry — see 2026-07-28's reasoning on filing after more field-verification). The Fedora build still has [...]

---

## 2026-08-04 — OVMS tuning pass on `qwen3.5-9b-text`: cache_dir win confirmed, concurrency-ceiling explanation from the previous entry disproven

**Goal**: act on the tuning recommendations from the prior session's concurrency testing — add `--cache_dir`, `--kv_cache_precision u8`, `--cache_size 2`, `--metrics_enable` to `start-ovms-qwen3-8b.sh`[...]

**Changes**: added a writable named volume (`ovms-qwen3.5-9b-text-cache`, mounted at `/cache`) plus `--cache_dir /cache --kv_cache_precision u8 --cache_size 2 --metrics_enable` to the script.

**Results**:
- **`--cache_dir` works and delivers the expected win.** First attempt used a bind-mounted host directory and failed with `Cache directory /cache is not writable; access() result: -1` — same rootles[...]
- **`--cache_size 2` + `--kv_cache_precision u8` took effect but didn't do what the previous entry predicted.** Logs confirmed `Cache type: static, ... of 2.0 GB` (vs. the old `dynamic`/grow-on-demand[...]
- Per-request latency for the 32-request burst was essentially unchanged (max 37.4s tuned vs. 34.6s baseline) — consistent with the ceiling truly being untouched by this change, not just similar by [...]

**Problems**:
- **`--nireq` is not usable with `--task text_generation`'s quick-start CLI mode at all.** Tried it as the next candidate explanation for the fixed-15 ceiling (its `--help` text says the default is "c[...]

**Lessons**: a plausible-sounding mechanism (cache pool size) that fits the observed symptom (a fixed concurrency ceiling) is still a guess until it's actually varied and re-measured — the previous [...]

**Next steps**: the real cause of the ~15-concurrent ceiling on `qwen3.5-9b-text` is still open. Candidates not yet tried: `--max_num_batched_tokens` (untested), or switching to the `--config_path`/`s[...]

---

## 2026-08-04 — Qwen3.5-9B served via OVMS (GPU text + CPU vision scripts), thinking-loop bug found, concurrency ceiling measured

... (rest of original file preserved) ...
