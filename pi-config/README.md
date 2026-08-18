# pi-config

Reproducible, secret-free system config for the Raspberry Pi (`raspberrypi-pihole`) —
the *shape* of the box, not its accumulated state or any credential. See
[docs/pi-backup-restore.md](../docs/pi-backup-restore.md) for the full backup/restore
story and [docs/overall-setup.md](../docs/overall-setup.md) for what the Pi actually
runs and why.

## What's here

- `quadlet/*.container` — the 9 Quadlet unit definitions for the arr-stack + Jellyfin +
  Homepage + Uptime Kuma. Image references, ports, volumes, `AutoUpdate` policy. No
  secrets — API keys live inside each app's own config, not the unit file.
- `system/nftables.conf` — the default-drop firewall ruleset (LAN/Tailscale trusted,
  80/443 public for Caddy, SSH closed to the public internet as of 2026-08-18).
- `system/Caddyfile` — reverse-proxies the public DuckDNS hostname to Jellyfin only.
- `system/wifi-watchdog.sh` + `.service`/`.timer` — ping-based WiFi auto-recovery,
  escalating reconnect → radio bounce → NetworkManager restart → capped reboot.
- `system/99-eth0-wlan0-arbiter` — NetworkManager dispatcher script preventing
  `eth0`/`wlan0` from both claiming `192.168.0.199` at once.
- `system/zz-persistent-storage-override.conf` — journald persistence drop-in (needs the
  vendor-drop-in-precedence + flush-gate fixes documented in `JOURNAL.md`'s 2026-08-13
  entry to actually take effect after a fresh copy — `provision.sh` doesn't run the
  flush for you, see its own output).
- `system/duckdns-update.sh` + `.service`/`.timer` — updates the public `AAAA` record
  from the Pi's current global IPv6. Reads its token from `/etc/duckdns/token`, which is
  **not** in this repo.
- `system/pi-backup.sh` + `.service`/`.timer` — this repo's own backup script (see
  `docs/pi-backup-restore.md`), included here so provisioning a fresh box also restores
  the ability to back it up again immediately.
- `provision.sh` — lays all of the above onto a fresh box. `--dry-run` prints every
  action without touching the system. Idempotent. Validates `nftables.conf` with `nft -c`
  *before* enabling it, since a bad ruleset here can sever the only remote-management
  path.

## What's deliberately NOT here

- **Secrets**: the WiFi PSK (`/etc/NetworkManager/system-connections/*.nmconnection`),
  the DuckDNS token (`/etc/duckdns/token`), every app's API key (inside
  `~/media-stack/config/<app>/`). These exist only in the backup archive
  (`~/backups/pi-backup-*.tar.gz` on the Pi, `~/pi-backups/` on Fedora), which is `600`
  permissions and never committed to Git.
- **State**: arr-stack databases, Jellyfin's library metadata, uptime-kuma's monitor
  history, Pi-hole's settings. Also archive-only — see `docs/pi-backup-restore.md`'s
  restore procedure for how these come back.
- **Pi-hole and Caddy's own installation**: both are installed via their upstream
  installers (Pi-hole's official script, Caddy's apt repo), not apt/config-file-copyable
  the way everything else here is. `provision.sh` notes this rather than automating past
  it — both installers make choices worth confirming interactively, not scripting blind.

## Rebuilding a dead Pi

1. Fresh Debian/Raspberry Pi OS install, `onkar` user, this repo cloned (or `pi-config/`
   copied over), Tailscale joined.
2. Install Pi-hole and Caddy per their own docs (see the note above).
3. `./pi-config/provision.sh --dry-run` to see what it'll do, then `./pi-config/provision.sh`
   for real.
4. Pull the latest backup archive from Fedora's `~/pi-backups/` (survives even if the
   dead SD card took the Pi's own copy with it), restore secrets/state per
   `docs/pi-backup-restore.md`.
5. `sudo journalctl --flush` (see the note on `zz-persistent-storage-override.conf` above).
6. Verify per `docs/pi-backup-restore.md`'s step 9 — real health checks, not just
   "container is Up."
