#!/usr/bin/env bash
# /usr/local/bin/pi-backup.sh
#
# Full-environment backup for the Pi (raspberrypi-pihole), per docs/pi-backup-restore.md
# in the LocalAI repo (Fedora side). Captures everything needed to rebuild this box from
# a dead SD card: app configs, SQLite DBs (safely, via sqlite3's online backup API so a
# hot WAL file can't produce a torn copy - see the 2026-08-18 JOURNAL.md entry on the
# pihole-FTL WAL-recovery incident for why this matters), Pi-hole's own config via its
# Teleporter export, Quadlet units, and the root-owned system config (nftables, Caddy,
# NetworkManager profiles + the eth0/wlan0 arbiter, journald persistence drop-in, the
# WiFi watchdog, DuckDNS). Does NOT back up media/downloads - those are bulk, re-acquirable,
# and not "configuration" in the sense this exists to protect.
#
# Output is a single tar.gz under /home/onkar/backups/, permissions locked to the owner
# only (it contains secrets: WiFi PSK, DuckDNS token, app API keys). Never copy this
# archive into the LocalAI git repo - see docs/pi-backup-restore.md.
set -euo pipefail

DEST_DIR="/home/onkar/backups"
STAGE="$DEST_DIR/.stage"
TS="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="$DEST_DIR/pi-backup-$TS.tar.gz"
RETAIN=5   # keep the last 5 local copies; Fedora's pull side keeps its own retention

mkdir -p "$DEST_DIR"
chmod 700 "$DEST_DIR"   # contains secrets (WiFi PSK, DuckDNS token, app API keys) - owner-only
rm -rf "$STAGE"
mkdir -p "$STAGE"/{configs,dbs,pihole,quadlet,system,network}

echo "[1/6] App configs (excluding live DB files - those are snapshotted safely below)"
# sudo: some files (e.g. ASP.NET DataProtection keys) are owned by in-container UIDs
# that don't map back to onkar on the host, even though the dirs are bind-mounted.
sudo -n rsync -a \
  --exclude='*.db' --exclude='*.db-shm' --exclude='*.db-wal' \
  --exclude='*.sqlite3' --exclude='*.sqlite3-shm' --exclude='*.sqlite3-wal' \
  --exclude='cache/' --exclude='logs/' --exclude='Cache/' \
  /home/onkar/media-stack/config/ "$STAGE/configs/"

echo "[2/6] SQLite DBs (online backup API - safe against a live WAL, unlike a raw cp)"
for db in \
  /home/onkar/media-stack/config/jellyfin/data/data/jellyfin.db \
  /home/onkar/media-stack/config/sonarr/sonarr.db \
  /home/onkar/media-stack/config/radarr/radarr.db \
  /home/onkar/media-stack/config/prowlarr/prowlarr.db \
  /home/onkar/media-stack/config/uptime-kuma/kuma.db \
  /home/onkar/media-stack/config/jellyseerr/db/db.sqlite3 ; do
  [ -f "$db" ] || { echo "  skip (not found): $db"; continue; }
  name="$(echo "$db" | sed 's#/home/onkar/media-stack/config/##; s#/#_#g')"
  sudo -n sqlite3 "$db" ".backup '$STAGE/dbs/$name'"
done
sudo -n chown "$(id -u):$(id -g)" "$STAGE"/dbs/* 2>/dev/null || true

echo "[3/6] Pi-hole config (Teleporter export - the officially supported backup format)"
curl -sf -o "$STAGE/pihole/teleporter.zip" --max-time 30 http://127.0.0.1:8080/api/teleporter \
  || echo "  WARNING: Teleporter export failed - if API auth has been re-enabled since this script was written, this curl call needs a session key added"

echo "[4/6] Quadlet units + auto-update/prune timers"
cp -a /home/onkar/.config/containers/systemd/*.container "$STAGE/quadlet/"
cp -a /home/onkar/.config/systemd/user/podman-*.timer /home/onkar/.config/systemd/user/podman-*.service "$STAGE/quadlet/" 2>/dev/null || true

echo "[5/6] Root-owned system config (nftables, Caddy, journald, watchdog, DuckDNS)"
sudo -n cp /etc/nftables.conf "$STAGE/system/"
sudo -n cp -a /etc/caddy "$STAGE/system/caddy-etc"
sudo -n cp -a /var/lib/caddy "$STAGE/system/caddy-var-lib" 2>/dev/null || true
sudo -n cp -a /etc/systemd/journald.conf.d "$STAGE/system/journald.conf.d"
sudo -n cp /usr/local/bin/wifi-watchdog.sh "$STAGE/system/"
sudo -n cp /etc/systemd/system/wifi-watchdog.service /etc/systemd/system/wifi-watchdog.timer "$STAGE/system/"
sudo -n cp /usr/local/bin/duckdns-update.sh "$STAGE/system/"
sudo -n cp -a /etc/duckdns "$STAGE/system/duckdns-etc"
sudo -n cp /etc/systemd/system/duckdns-update.service /etc/systemd/system/duckdns-update.timer "$STAGE/system/"

echo "[6/6] Network config (NM profiles - CONTAINS THE WIFI PSK - + the eth0/wlan0 arbiter)"
sudo -n cp /etc/NetworkManager/dispatcher.d/99-eth0-wlan0-arbiter "$STAGE/network/"
sudo -n cp -a /etc/NetworkManager/system-connections "$STAGE/network/system-connections"

sudo -n chown -R "$(id -u):$(id -g)" "$STAGE"
chmod -R go-rwx "$STAGE"

tar -C "$STAGE" -czf "$ARCHIVE" .
chmod 600 "$ARCHIVE"
# Bare filename in the checksum file (not an absolute path) so `sha256sum -c`
# still works after the archive is pulled to a different machine/directory.
( cd "$DEST_DIR" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256" )
rm -rf "$STAGE"

# Retention: keep the last N local copies
ls -1t "$DEST_DIR"/pi-backup-*.tar.gz 2>/dev/null | tail -n +$((RETAIN+1)) | while read -r old; do
  rm -f "$old" "$old.sha256"
done

echo "Backup complete: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
