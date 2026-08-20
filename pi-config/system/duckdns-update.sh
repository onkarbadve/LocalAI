#!/bin/bash
set -euo pipefail

DOMAIN="aagaumulga"
TOKEN_FILE="/etc/duckdns/token"
STATE_FILE="/var/lib/duckdns/last-ipv6"

if [[ ! -r "$TOKEN_FILE" ]]; then
    echo "duckdns-update: token file $TOKEN_FILE missing or unreadable" >&2
    exit 1
fi
TOKEN="$(<"$TOKEN_FILE")"

# Whichever interface is active (the 99-eth0-wlan0-arbiter can switch this, and
# either radio can be disabled entirely) - prefer the interface currently holding
# the IPv6 default route, then fall back to checking eth0 and wlan0 directly.
DEFAULT_IFACE="$(ip -6 route show default 2>/dev/null \
    | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
CANDIDATES=()
[[ -n "$DEFAULT_IFACE" ]] && CANDIDATES+=("$DEFAULT_IFACE")
CANDIDATES+=(eth0 wlan0)

CURRENT_IP6=""
for IFACE in "${CANDIDATES[@]}"; do
    ip6="$(ip -6 addr show "$IFACE" scope global dynamic 2>/dev/null \
        | awk '/inet6/{print $2}' | cut -d/ -f1 | head -n1)"
    if [[ -n "$ip6" ]]; then
        CURRENT_IP6="$ip6"
        break
    fi
done

if [[ -z "$CURRENT_IP6" ]]; then
    echo "duckdns-update: no global IPv6 found on any of: ${CANDIDATES[*]}" >&2
    exit 1
fi

mkdir -p "$(dirname "$STATE_FILE")"
LAST_IP6=""
[[ -f "$STATE_FILE" ]] && LAST_IP6="$(<"$STATE_FILE")"

if [[ "$CURRENT_IP6" == "$LAST_IP6" ]]; then
    exit 0
fi

RESPONSE="$(curl -fsS "https://www.duckdns.org/update?domains=${DOMAIN}&token=${TOKEN}&ipv6=${CURRENT_IP6}")"

if [[ "$RESPONSE" == OK* ]]; then
    echo "$CURRENT_IP6" > "$STATE_FILE"
    echo "duckdns-update: updated ${DOMAIN}.duckdns.org -> $CURRENT_IP6"
else
    echo "duckdns-update: DuckDNS update failed: $RESPONSE" >&2
    exit 1
fi
