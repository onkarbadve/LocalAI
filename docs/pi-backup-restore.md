# Pi Backup & Restore

Goal: if the Pi's SD card dies, rebuild `raspberrypi-pihole` from a fresh SD card without
relying on memory. This covers *configuration and state*, not media — the arr-stack's
downloaded/library files are bulk and re-acquirable, and are deliberately excluded.

For the machine/network context this backs up, see [overall-setup.md](overall-setup.md).
For the incident that made SQLite-safety a design requirement here, see the 2026-08-18
Pi-hole app-password entries in [JOURNAL.md](../JOURNAL.md).

## What gets backed up

One script, `/usr/local/bin/pi-backup.sh` (root-owned, `755`, deployed manually — it isn't
in this git repo since it's Pi-local infrastructure, same reasoning as the arr-stack
config itself). It stages then tars:

| Category | Source | Method |
|---|---|---|
| App configs | `~/media-stack/config/*` (sonarr, radarr, prowlarr, qbittorrent, jellyfin, jellyseerr, homepage, uptime-kuma, flaresolverr) | `rsync`, excluding live DB files and cache/log dirs |
| SQLite DBs | jellyfin/sonarr/radarr/prowlarr/uptime-kuma/jellyseerr `.db`/`.sqlite3` files | `sqlite3 <db> ".backup <dest>"` — the online backup API, safe against a live WAL. A raw `cp`/`rsync` of a hot SQLite file can capture a torn copy; this is exactly what's suspected to have happened to Pi-hole's own DB during the 15:56 SIGKILL incident the same day this was built (`recovered 12 frames from WAL file`) |
| Pi-hole config | — | Teleporter export via `curl http://127.0.0.1:8080/api/teleporter` — Pi-hole's own official backup format (settings, lists, local DNS records), not a raw file copy |
| Quadlet units | `~/.config/containers/systemd/*.container`, `podman-*.timer`/`.service` | plain copy |
| System config | `/etc/nftables.conf`, `/etc/caddy`, `/var/lib/caddy` (ACME cert state), `/etc/systemd/journald.conf.d`, `wifi-watchdog.sh` + its service/timer, `duckdns-update.sh` + `/etc/duckdns` + its service/timer | `sudo cp`, since these are root-owned |
| Network config | `/etc/NetworkManager/system-connections/*` (**contains the WiFi PSK**), `/etc/NetworkManager/dispatcher.d/99-eth0-wlan0-arbiter` | `sudo cp` |

**Not backed up**: `~/media-stack/media` (the actual library) and the arr-stack's
download directories — bulk, re-acquirable, not configuration.

## Where it lives, and why it's not in Git

- Pi: `/home/onkar/backups/pi-backup-<timestamp>.tar.gz`, directory `chmod 700`, archive
  `chmod 600`. Runs nightly via `pi-backup.timer` (01:30, after the 00:14 auto-update and
  01:00 image-prune), keeps the last 5 locally.
- Fedora: `/home/onkar/pi-backups/` (**deliberately outside `~/LocalAI`**), pulled via
  `~/.local/bin/pi-backup-pull.sh` + `pi-backup-pull.timer` — checks 3 minutes after every
  boot/login, then hourly while up (not a fixed daily slot, since this is a laptop that
  isn't on 24/7 — the script is a cheap no-op when there's nothing new or the Pi isn't
  reachable), integrity-checked against a `.sha256` on arrival, keeps the last 7.

The archive contains real secrets — the WiFi PSK, the DuckDNS token, every arr app's API
key, Pi-hole's Teleporter export. **Never `git add` anything from `~/backups` or
`~/pi-backups`.** Both directories exist specifically outside the repo tree so an
`git add -A` in `~/LocalAI` can't reach them. This doc (the procedure) is what's tracked
in Git — the archives themselves are not, per the handover brief's "do not place actual
credentials in repository documentation."

Having two independent copies (Pi + Fedora) is the point: a dead SD card doesn't take the
only copy of the backup down with it.

## Restore procedure (fresh SD card / bare-metal rebuild)

1. **Flash & bring up base OS.** Raspberry Pi OS / Debian trixie, `onkar` user, SSH key
   auth (`~/.ssh/id_ed25519_raspberrypi`'s public half), Tailscale joined as
   `raspberrypi-pihole`.
2. **Pull the latest archive from Fedora** (Fedora's copy survives even if the dead SD card
   somehow made the Pi-side copy unrecoverable): `scp` `~/pi-backups/pi-backup-<latest>.tar.gz`
   to the new Pi, verify against its `.sha256`, extract to a scratch dir.
3. **Install packages**: `podman`, `nftables`, Pi-hole (official installer), Caddy,
   `sqlite3`. Re-derive versions/config from [overall-setup.md](overall-setup.md) and
   [JOURNAL.md](../JOURNAL.md) rather than guessing — several of these (nftables rule
   ordering, journald's flush-gate behavior, the eth0/wlan0 arbiter) have documented
   failure modes that are easy to reintroduce from a clean install.
4. **Restore network config first** (everything else depends on connectivity/DNS):
   - `system-connections/*.nmconnection` → `/etc/NetworkManager/system-connections/`,
     `chmod 600`, restart NetworkManager.
   - `99-eth0-wlan0-arbiter` → `/etc/NetworkManager/dispatcher.d/`, `chmod 755`.
   - `duckdns-update.sh` + `/etc/duckdns` + its service/timer → restore, enable.
5. **Restore system config**: `nftables.conf` → `/etc/`, `nft -c -f` to validate *before*
   enabling the service (a bad ruleset here can lock out the only remote-management path —
   see the 2026-08-18 SSH-closure entry in `JOURNAL.md` for how that was verified safely
   the first time). `journald.conf.d/` drop-in → restore, then `journalctl --flush`
   explicitly — the flush-gate bug documented in the 2026-08-13 journal entry means a
   config restore alone does not retroactively activate persistence. `wifi-watchdog.sh` +
   unit files → restore, enable.
6. **Restore Caddy**: config + `/var/lib/caddy`. The restored ACME state may or may not
   still be valid depending on how long the box was down — if Caddy can't resume the old
   cert, it re-issues automatically against Let's Encrypt on next start, no action needed.
7. **Restore Pi-hole**: fresh install, then import the Teleporter zip via the admin UI
   (Settings → Teleporter → Restore) or `pihole-FTL --teleporter <file>`.
8. **Restore Quadlet units + app configs**: `.container` files → `~/.config/containers/systemd/`,
   app config dirs → `~/media-stack/config/<app>/`, the `sqlite3`-backed-up `.db` files into
   their respective app config dirs (these are clean, non-WAL snapshots — safe to drop in
   directly). `systemctl --user daemon-reload`, start each service, confirm each comes up.
9. **Verify**, per service — not just "container is Up":
   - `curl http://127.0.0.1:8096/System/Ping` (Jellyfin), same pattern for each arr app's
     `/` or its API health path.
   - Pi-hole: `/admin/` loads, a test query resolves and shows in the log.
   - `nft list ruleset` shows a nonzero drop counter after a few minutes (actively
     filtering, not just loaded — see the "loaded ≠ filtering" lesson from 2026-08-18).
   - Public path: `curl https://aagaumulga.duckdns.org/System/Ping` returns `200`.
10. **Re-point DuckDNS / re-pinhole the router** if the Pi's IPv6 changed (it's SLAAC from
    the same `/64`, likely stable, but don't assume).

## Restore test actually performed (2026-08-18)

Per the handover brief's rule against claiming a test that wasn't run: **a full bare-metal
restore was not executed** — there's no spare hardware to test it against without touching
the production Pi. What *was* actually run:

- `uptime-kuma`'s config was extracted from a real backup archive into a scratch directory,
  and a second, independent `uptime-kuma` container was started from the restored config on
  a different port and container name (not touching the running production instance).
- The restored instance came up and served its real monitor history from the backup —
  proving the chain end-to-end: archive → extract → a service can actually start from the
  restored config and the data is genuinely there, not just present as bytes in a tarball.
- The scratch container and directory were removed after — this was a verification, not a
  permanent second instance.

This validates the *mechanism* (the backup is restorable, the sqlite3 snapshot approach
produces a working DB) on one representative service. It does not validate the full
bare-metal sequence above (package installs, network bring-up ordering, Pi-hole Teleporter
import, Caddy cert re-issuance) — those steps are documented from direct knowledge of how
each piece was originally built, not from having executed them in sequence on this pass.
