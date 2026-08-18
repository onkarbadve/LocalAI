# Network / IPv6 Setup

Current-state reference for the home network's IPv6 exposure and the hardening built around it, covering both the Fedora laptop and the RPi5. Written 2026-08-18 for external review (Codex). For the investigative narrative (what broke, what was tried, why), see [JOURNAL.md](../JOURNAL.md)'s 2026-08-18 entry — this doc is the distilled "what's true right now."

## Topology

- ISP: ACT Fibernet / Beam Telecom (Hyderabad, Tarnaka POP).
- **IPv4**: behind CGNAT. Router's own WAN IP is `10.158.62.113` (private, RFC 1918); the internet-visible address is `49.204.165.243` (part of `49.204.128.0/18`, "ACTFIBERNET-Tarnaka"). Nothing can initiate an inbound IPv4 connection to this network without a relay (Tailscale, etc.) — this was always true and hasn't changed.
- **IPv6**: real, globally-routable, no NAT. Prefix `2406:b400:53:1e77::/64` via SLAAC. Every device on the LAN gets its own directly-reachable global address — this is what changed and what everything below responds to.
- Router: TP-Link Archer AX1500 Wi-Fi 6, admin at `192.168.0.1`, LAN `192.168.0.0/24`.
- Both boxes' addresses have been stable in practice across the session despite a short (~300s) SLAAC lease lifetime; not guaranteed static, hence the DDNS setup below.

## Fedora laptop (`fedora`, `wlp0s20f3`, `192.168.0.126`)

`firewalld`, zone `FedoraWorkstation` (applies to `wlp0s20f3`, both IPv4 and IPv6):

```
services: dhcpv6-client samba-client ssh
ports:    51413/tcp 51413/udp          # Transmission peer port, deliberate
rich rules:
  source 192.168.0.0/24 → tcp/udp 1716 accept   # KDE Connect, LAN-only
```

Changed this session:
- **Removed** `1025-65535/tcp+udp` — a pre-existing rule of unknown origin that amounted to "allow every unprivileged port." This was the critical finding: harmless under CGNAT (IPv4 never reachable from WAN anyway), but a full exposure the moment IPv6 went live.
- **Cockpit** (`cockpit.socket`, port 9090): was enabled+active, now `disabled`+stopped. Reachable via Tailscale if ever needed again (`tailscale0` is a `trusted` firewalld zone).
- **AnyDesk**: fully removed — rpm package, `anydesk.service`, `~/.config/anydesk`, `/etc/anydesk`, `/var/lib/anydesk`. Was listening on `7070/tcp+udp`, a temporary install no longer needed.
- **KDE Connect** (1716): was wildcard-open, now scoped to LAN via the rich rule above.

DNS: routed through Tailscale MagicDNS (`~.` default routing domain → `fd7a:115c:a1e0::53`) → Pi-hole. No leak to the ISP's advertised IPv6 DNS servers.

SSH to the Pi: `~/.ssh/config` has a `Host raspberrypi pi` block pointing at `raspberrypi.local` (mDNS) with `IdentityFile ~/.ssh/id_ed25519_raspberrypi`. **mDNS resolution is currently broken** on this laptop (`resolvectl mdns` shows `Global: no` and both links `no` — a pre-existing `systemd-resolved` setting, unrelated to any firewall change made this session, root cause not yet fixed). Working fallback used throughout this session:
```
ssh -i ~/.ssh/id_ed25519_raspberrypi -o IdentitiesOnly=yes onkar@raspberrypi-pihole
```
(`raspberrypi-pihole` is the Pi's Tailscale MagicDNS name.)

## RPi5 (`raspberrypi`, Debian 13 trixie, `192.168.0.199`, Tailscale `raspberrypi-pihole` / `100.102.227.7`)

Had **no firewall at all** before this session (`nft`/`iptables`/`ufw`/`firewalld` all absent or inactive) — every listening service was directly reachable from the internet the moment IPv6 arrived, most seriously Pi-hole's own DNS (port 53, bound `0.0.0.0`+`[::]`, a literal open recursive resolver).

`nftables` (`/etc/nftables.conf`, service enabled + active, survives reboot):

```nft
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        iif "lo" accept

        # Trust these sources before any conntrack-state checks — multicast/
        # broadcast (mDNS etc.) commonly shows as ct state "invalid", so this
        # ordering matters (an earlier version had it after and broke mDNS).
        iifname "tailscale0" accept
        ip saddr 192.168.0.0/24 accept
        ip6 saddr fe80::/10 accept
        ip6 saddr 2406:b400:53:1e77::/64 accept

        ct state established,related accept
        ct state invalid drop

        icmpv6 type { destination-unreachable, packet-too-big, time-exceeded,
                       parameter-problem, nd-router-advert, nd-router-solicit,
                       nd-neighbor-solicit, nd-neighbor-advert, mld-listener-query,
                       mld-listener-report, mld-listener-reduction, echo-request,
                       echo-reply } accept
        icmp type { destination-unreachable, time-exceeded, parameter-problem,
                     echo-request, echo-reply } accept

        tcp dport 22 accept              # SSH, open to the world (deliberate)
        tcp dport { 80, 443 } accept     # Caddy, deliberate — see below

        counter drop
    }
    chain forward { type filter hook forward priority 0; policy accept; }
    chain output  { type filter hook output priority 0; policy accept; }
}
```

Effect: everything except SSH (22) and Caddy (80/443) is reachable only from LAN, the whole `2406:b400:53:1e77::/64` prefix (covers LAN devices using their own global IPv6, not just `fe80::` link-local), or Tailscale. This closed off Pi-hole's DNS, the entire arr-stack (Sonarr/Radarr/Prowlarr/qBittorrent/FlareSolverr), Jellyfin, Homepage, Uptime Kuma — all previously wildcard-bound and internet-reachable.

**Pi-hole** (Core v6.4.3): admin webserver moved from `80`/`443` to `8080`/`8443` to free the standard ports for Caddy —
```
sudo pihole-FTL --config webserver.port "8080o,8443os,[::]:8080o,[::]:8443os"
```
Admin UI is now at `http://192.168.0.199:8080/admin/` (plain) or `https://192.168.0.199:8443/admin/` (self-signed cert, browser warning expected). Blocking mode is `NULL` (blocked domains resolve to `0.0.0.0`), so the port move has **no effect** on ad-blocking — Pi-hole was never using its own webserver for a blockpage.

**DuckDNS**: `aagaumulga.duckdns.org`, tracks the Pi's IPv6.
- Token: `/etc/duckdns/token` (`600 root:root`), never passed through shell history or chat.
- Updater: `/usr/local/bin/duckdns-update.sh` — reads token, reads current global IPv6 off `wlan0`, compares against `/var/lib/duckdns/last-ipv6`, calls `https://www.duckdns.org/update?domains=aagaumulga&token=...&ipv6=...` only on change.
- `duckdns-update.service` (oneshot) + `duckdns-update.timer` (every 3 min, `OnBootSec=30s`), both enabled + active.
- The domain's **`A` (IPv4) record was explicitly cleared** — DuckDNS auto-populated it from the browser's CGNAT'd address when the domain was first created, and Let's Encrypt kept trying (and failing) to validate over that unreachable IPv4 until it was removed. Only `AAAA` is maintained going forward.

**Caddy** (`apt install caddy`, Debian repo, v2.6.2): `/etc/caddy/Caddyfile`:
```
aagaumulga.duckdns.org {
	reverse_proxy localhost:8096
}
```
Fronts **Jellyfin only** (`localhost:8096`) — nothing else on the Pi is exposed through it. Automatic HTTPS via Let's Encrypt succeeded; cert valid Aug 18 → Nov 16 2026, auto-renews. `caddy.service` enabled + active.

**Router IPv6 Firewall Rules** (TP-Link Archer, `192.168.0.1` → IPv6 → Firewall Rules): two rules, `caddy-http` (TCP 80) and `caddy-https` (TCP 443), source `Any`, destination the Pi selected via the device picker (not a hardcoded address, so it survives renumbering). This was a second, independent blocker found during setup: even with the Pi's own firewall open on 80/443 and a real IPv6 address, the router was silently dropping unsolicited inbound — Let's Encrypt's validators couldn't reach the Pi until these were added. (Symptom at the time: LAN-sourced requests to the Pi worked, internet-sourced ACME validation got flat connection failures — that split is the signature of a router-level stateful IPv6 firewall, separate from CGNAT and separate from the Pi's own `nftables`.)

**Homepage dashboard** (container `homepage`, config `/home/onkar/media-stack/config/homepage/services.yaml`): Pi-hole widget's `url:` was `http://192.168.0.199` (implicit port 80, which now hits Caddy/Jellyfin instead of Pi-hole after the port move) — fixed to `http://192.168.0.199:8080`, container restarted. Note: this config file has the Pi-hole API key in plaintext (`key: ...`) — it was read during this session's diagnosis and appeared in tool output; not itself compromised by that, but worth rotating (`pihole -a -p`) if that matters to you.

**Jellyfin**: `Users/Public` (unauthenticated login-screen endpoint) returns `[]` — "display all users on login page" is off, so an anonymous visitor can't enumerate usernames. `StartupWizardCompleted: true`. **Not verified**: individual account password strength / any blank passwords — can't check without logging in, worth a manual look now that it's genuinely internet-facing (Dashboard → Users).

## Access reference

| What | URL / command |
|---|---|
| Jellyfin (public) | `https://aagaumulga.duckdns.org/` |
| Pi-hole admin | `http://192.168.0.199:8080/admin/` (LAN/Tailscale only) |
| SSH to Pi (mDNS broken, use this) | `ssh -i ~/.ssh/id_ed25519_raspberrypi -o IdentitiesOnly=yes onkar@raspberrypi-pihole` |
| Homepage dashboard | `http://192.168.0.199:3000/` |

## Known open items

1. **mDNS broken on the laptop** (`raspberrypi.local` doesn't resolve) — pre-existing, `systemd-resolved`-side, not caused by or fixed during this session. Workaround in place (Tailscale hostname); root fix and/or an `~/.ssh/config` fallback host entry not yet done.
2. **Jellyfin password strength** unverified — check manually.
3. **Pi-hole API key** was exposed in this session's tool output while diagnosing the Homepage widget — rotate if desired.
4. **No external vantage-point scan performed** — everything above was verified from Let's Encrypt's validators succeeding (a real external signal) and from LAN-side testing, but no deliberate port scan from outside the network (e.g. phone on mobile data) was run.
5. **Transmission's UPnP/NAT-PMP setting** — recommended to turn off (dead weight now that the port is opened explicitly at the firewall, and never worked under CGNAT anyway) — not verified done.
6. Only Jellyfin is intentionally public. Any future decision to expose another service (the arr-stack, Open WebUI, the LocalAI/llama.cpp endpoint — the latter two run on the laptop, not the Pi, and would need their own DDNS name and firewall rules) should go through the same pattern: narrow firewall rule + Caddy site block + real auth on the service itself, not a broader port range.
