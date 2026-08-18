#!/bin/bash
set -euo pipefail

DOMAIN="aagaumulga"
TOKEN_FILE="/etc/duckdns/token"
STATE_FILE="/var/lib/duckdns/last-ipv6"
IFACE="wlan0"

if [[ ! -r "$TOKEN_FILE" ]]; then
    echo "duckdns-update: token file $TOKEN_FILE missing or unreadable" >&2
    exit 1
fi
TOKEN="$(<"$TOKEN_FILE")"

CURRENT_IP6="$(ip -6 addr show "$IFACE" scope global dynamic 2>/dev/null \
    | awk '/inet6/{print $2}' | cut -d/ -f1 | head -n1)"

if [[ -z "$CURRENT_IP6" ]]; then
    echo "duckdns-update: no global IPv6 found on $IFACE" >&2
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
