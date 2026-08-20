#!/usr/bin/env bash
# pi-config/provision.sh
#
# Lays down the Pi's (raspberrypi-pihole) reproducible system shape onto a fresh
# Debian/Raspberry Pi OS install: packages, Quadlet units, nftables, Caddy, the WiFi
# watchdog, the eth0/wlan0 arbiter, journald persistence, DuckDNS, and this repo's own
# backup script/timer. It does NOT restore secrets or state - see the "What this does
# NOT do" section below and docs/pi-backup-restore.md in this repo.
#
# Run ON the target Pi, as the `onkar` user with NOPASSWD sudo (matching the existing
# box). Idempotent: safe to re-run. Validates nftables before enabling it, since a bad
# ruleset there can sever the only remote-management path.
#
# Usage:
#   ./provision.sh --dry-run   # print every action without touching the system
#   ./provision.sh             # actually apply
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUADLET_SRC="$SCRIPT_DIR/quadlet"
SYSTEM_SRC="$SCRIPT_DIR/system"

run() {
  if [ "$DRY_RUN" = 1 ]; then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

echo "== 1/6: packages =="
# Idempotent: apt install on an already-installed package is a no-op.
run sudo apt-get update
run sudo apt-get install -y podman nftables sqlite3 curl rsync zram-tools
run sudo systemctl disable --now dphys-swapfile 2>/dev/null || true
run sudo apt-get purge -y dphys-swapfile 2>/dev/null || true
run sudo cp "$SYSTEM_SRC/zramswap.conf" /etc/default/zramswap
run sudo systemctl enable --now zramswap
echo "  NOTE: Caddy and Pi-hole are not plain apt packages on this box - Caddy via its"
echo "  own apt repo, Pi-hole via the official installer (curl -sSL https://install.pi-hole.net)."
echo "  Run those interactively per their own docs before continuing if this is a fresh box;"
echo "  this script does not automate either (both prompt for choices worth making deliberately)."

echo "== 2/6: Quadlet units =="
run mkdir -p ~/.config/containers/systemd
for f in "$QUADLET_SRC"/*.container; do
  run cp "$f" ~/.config/containers/systemd/
done
run systemctl --user daemon-reload

echo "== 3/6: nftables (validate BEFORE enabling - this can sever the only remote path) =="
if [ "$DRY_RUN" = 1 ]; then
  echo "DRY-RUN: sudo cp $SYSTEM_SRC/nftables.conf /etc/nftables.conf"
  echo "DRY-RUN: sudo nft -c -f /etc/nftables.conf"
  echo "DRY-RUN: sudo systemctl enable --now nftables"
else
  sudo cp "$SYSTEM_SRC/nftables.conf" /etc/nftables.conf
  sudo nft -c -f /etc/nftables.conf || { echo "nftables.conf failed validation - NOT enabling, fix before retrying" >&2; exit 1; }
  sudo systemctl enable --now nftables
fi

echo "== 4/6: Caddy, journald persistence, WiFi watchdog, eth0/wlan0 arbiter, DuckDNS =="
run sudo mkdir -p /etc/caddy
run sudo cp "$SYSTEM_SRC/Caddyfile" /etc/caddy/Caddyfile
run sudo mkdir -p /etc/systemd/journald.conf.d
run sudo cp "$SYSTEM_SRC/zz-persistent-storage-override.conf" /etc/systemd/journald.conf.d/
run sudo cp "$SYSTEM_SRC/wifi-watchdog.sh" /usr/local/bin/wifi-watchdog.sh
run sudo chmod 755 /usr/local/bin/wifi-watchdog.sh
run sudo cp "$SYSTEM_SRC/wifi-watchdog.service" "$SYSTEM_SRC/wifi-watchdog.timer" /etc/systemd/system/
run sudo cp "$SYSTEM_SRC/99-eth0-wlan0-arbiter" /etc/NetworkManager/dispatcher.d/
run sudo chmod 755 /etc/NetworkManager/dispatcher.d/99-eth0-wlan0-arbiter
run sudo cp "$SYSTEM_SRC/duckdns-update.sh" /usr/local/bin/duckdns-update.sh
run sudo chmod 755 /usr/local/bin/duckdns-update.sh
run sudo cp "$SYSTEM_SRC/duckdns-update.service" "$SYSTEM_SRC/duckdns-update.timer" /etc/systemd/system/
echo "  NOTE: duckdns-update.sh needs /etc/duckdns/token (the secret itself, NOT in this"
echo "  repo) restored from the backup archive before its timer can succeed."
run sudo cp "$SYSTEM_SRC/99-tailscale-forwarding.conf" /etc/sysctl.d/99-tailscale-forwarding.conf
run sudo sysctl --system
echo "  NOTE: this enables IP forwarding for Tailscale subnet routing but does not itself"
echo "  advertise or approve a route - run 'sudo tailscale set --advertise-routes=192.168.0.0/24'"
echo "  and approve it at https://login.tailscale.com/admin/machines (per-box, not scripted here)."

echo "== 5/6: this repo's own backup script + timer =="
run sudo cp "$SYSTEM_SRC/pi-backup.sh" /usr/local/bin/pi-backup.sh
run sudo chmod 755 /usr/local/bin/pi-backup.sh
run sudo cp "$SYSTEM_SRC/pi-backup.service" "$SYSTEM_SRC/pi-backup.timer" /etc/systemd/system/

echo "== 6/6: enable everything except journald (needs a flush, not just enable - see below) =="
run sudo systemctl daemon-reload
run sudo systemctl enable --now wifi-watchdog.timer duckdns-update.timer pi-backup.timer

cat <<'EOF'

== What this script does NOT do (by design - see docs/pi-backup-restore.md) ==
- Does not restore secrets: /etc/NetworkManager/system-connections/*.nmconnection (WiFi
  PSK), /etc/duckdns/token, any app's API key inside its config. These exist only in the
  600-mode backup archive, never in this repo.
- Does not restore state: arr-stack databases, Jellyfin library metadata, uptime-kuma
  history, Pi-hole's settings (restore Pi-hole's Teleporter export separately).
- Does not install Caddy or Pi-hole themselves (see the note under step 1) or flush
  journald after the persistence drop-in lands - run `sudo journalctl --flush` once,
  explicitly, per the 2026-08-13 JOURNAL.md entry on why a config change alone doesn't
  retroactively activate persistence.
- Does not restore ~/media-stack/config/* app configs or media - copy those in from the
  backup archive, per docs/pi-backup-restore.md's restore procedure.

Next: restore the latest backup archive's secrets/state per docs/pi-backup-restore.md,
then start each Quadlet service and verify per that doc's step 9.
EOF
