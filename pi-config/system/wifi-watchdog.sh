#!/bin/bash
# wifi-watchdog.sh - recover wlan0 when the default gateway stops answering.
#
# Why this exists: the onboard brcmfmac radio wedges silently - carrier stays 1,
# operstate goes dormant, and the driver logs nothing at all. Recovery has so far
# needed a manual reboot. See JOURNAL.md on the Fedora box for the investigation.
#
# Escalation ladder, driven by consecutive failed checks (timer runs every 2 min):
#   2 failures (~4 min)  -> nmcli connection up Badve
#   4 failures (~8 min)  -> nmcli radio wifi off/on
#   6 failures (~12 min) -> systemctl restart NetworkManager
#   8 failures (~16 min) -> reboot, capped at 2 reboots per rolling hour
#
# Recovery actions are dispatched detached via systemd-run, so running this script
# by hand over SSH does not kill its own transport partway through a bounce.
#
# Two failure modes fixed here after a real 2026-08-15 lockout (see JOURNAL.md /
# rpi5_pihole_tailscale_setup.md memory for the full incident):
#   1. Every dispatched step now clears any stale BSSID pin first. A pin left over
#      from manual troubleshooting (e.g. a transient rollback timer that never got
#      to run because a reboot killed it first) can make EVERY recovery step fail
#      silently, including the reboot itself, since the box comes back up still
#      pinned to a BSSID that may not exist. Clearing it is a no-op when there's no
#      pin, so this is always safe.
#   2. The radio off/on step used to be `nmcli radio wifi off; sleep 5; ...on` -
#      not atomic. If that process was killed mid-sleep (e.g. by the watchdog's own
#      reboot happening around the same time), the radio was left OFF, and
#      NetworkManager persists that across reboots - a headless box with no
#      keyboard/monitor then has no way to bring WiFi back up on its own. Now
#      wrapped in a trap so `wifi on` fires even on SIGTERM (which is what a
#      shutdown/reboot sends before SIGKILL).

set -u

CONN=Badve
STATE=/run/wifi-watchdog.fails
REBOOTLOG=/var/lib/wifi-watchdog/reboots

mkdir -p "$(dirname "$REBOOTLOG")"

gw=$(ip route show default 2>/dev/null | awk '/^default/ {print $3; exit}')

# ping exits 0 if at least one reply came back. That tolerance is deliberate: the
# fallback AP runs ~5% loss at -74 dBm, and this check exists to spot a dead radio,
# not to measure link quality. Demanding zero loss would bounce a working link.
ok=0
if [ -n "${gw:-}" ] && ping -c5 -W2 -q "$gw" >/dev/null 2>&1; then
    ok=1
fi

fails=$(cat "$STATE" 2>/dev/null || echo 0)

if [ "$ok" = 1 ]; then
    if [ "$fails" -gt 0 ]; then
        echo "gateway $gw reachable again after $fails failed check(s)"
    fi
    echo 0 > "$STATE"
    exit 0
fi

fails=$((fails + 1))
echo "$fails" > "$STATE"
echo "gateway ${gw:-<none found>} unreachable (consecutive failures: $fails)"

dispatch() {
    echo "recovery step: $1"
    # Clear any stale BSSID pin first, every time - cheap no-op if unset, and it's
    # the one thing that can otherwise make every step below silently fail.
    systemd-run --no-block --collect --unit="wifi-wd-$(date +%s)" bash -c \
        "nmcli connection modify $CONN 802-11-wireless.bssid '' 2>/dev/null; $1"
}

case "$fails" in
    2) dispatch "nmcli connection up $CONN" ;;
    4) dispatch 'trap "nmcli radio wifi on" EXIT TERM INT; nmcli radio wifi off; sleep 5' ;;
    6) dispatch "systemctl restart NetworkManager" ;;
esac

if [ "$fails" -ge 8 ]; then
    now=$(date +%s)

    # Reboot budget lives in /var/lib (survives reboot) - a counter in /run would
    # reset on every reboot and so could never actually cap a boot loop.
    recent=$(awk -v c="$now" '$1 > c-3600' "$REBOOTLOG" 2>/dev/null | wc -l)
    if [ "$recent" -ge 2 ]; then
        echo "REFUSING to reboot: already rebooted $recent time(s) in the last hour."
        echo "The network is not recovering on its own - this needs a human."
        exit 0
    fi

    up=$(awk '{print int($1)}' /proc/uptime)
    if [ "$up" -lt 900 ]; then
        echo "uptime ${up}s < 900s - holding off reboot to avoid a fast loop"
        exit 0
    fi

    # Belt and braces: clear the pin synchronously, right here, so the box never
    # reboots into a state it can't recover from even if the dispatched steps above
    # never got a chance to run.
    nmcli connection modify "$CONN" 802-11-wireless.bssid "" 2>/dev/null

    echo "$now" >> "$REBOOTLOG"
    echo "rebooting now (failure count $fails, $recent prior reboot(s) this hour)"
    systemctl reboot
fi
