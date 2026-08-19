# Overall Setup — Fedora Laptop + Raspberry Pi 5

Full current-state reference across both machines, written 2026-08-18 for external review (Codex). The Pi is a separate physical box and still isn't *itself* part of this git repo, but its reproducible config shape now is — see [pi-config/](../pi-config/) — since the two machines share a LAN, a Tailscale tailnet, and — as of today — a firewall posture that was designed together. Secrets and accumulated state live only in the backup archive (see [pi-backup-restore.md](pi-backup-restore.md)), never in Git. For narrower detail: [SETUP.md](../SETUP.md) is the flag-by-flag LocalAI/llama.cpp reference (Fedora only), [JOURNAL.md](../JOURNAL.md) is the dated incident/decision log for both boxes, [network-ipv6-setup.md](network-ipv6-setup.md) is *just* today's IPv6/firewall/Caddy work in isolation.

## Network topology (applies to both boxes)

- ISP: ACT Fibernet / Beam Telecom (Hyderabad, Tarnaka POP). Router: TP-Link Archer AX1500 Wi-Fi 6, `192.168.0.1`, LAN `192.168.0.0/24`.
- **IPv4**: behind CGNAT. Router's own WAN IP `10.158.62.113` (private) is translated to the shared internet-visible `49.204.165.243`. Nothing can initiate an inbound IPv4 connection without a relay (Tailscale, etc.) — always true, unrelated to anything below.
- **IPv6**: real, globally-routable, no NAT — delegated block `2406:b400:53::/48` via SLAAC; the ISP rotates the `/64` subnet ID within that `/48` without notice (confirmed 2026-08-19), so firewall rules key off the `/48`, not a specific `/64`. Every device gets its own directly-reachable global address; this is what drove the 2026-08-18 firewall work on both machines (see [network-ipv6-setup.md](network-ipv6-setup.md) for the full detail, summarized below).
- Tailscale tailnet `tail2f4a36.ts.net`, MagicDNS on. Members: Fedora laptop (`fedora`, `100.93.33.122`), Pi (`raspberrypi-pihole`, `100.102.227.7`), phone (`a34`, Android).

---

## 1. Fedora laptop — LLM serving + daily driver

**Hardware**: Intel i5-12500H (4P+8E, 16 threads), Intel Iris Xe iGPU (no discrete GPU, Vulkan backend), 16GB RAM (~7.4–9.8GB Vulkan-visible). Fedora 44 (`~/LocalAI`), previously Windows (`C:\LocalAI`, preserved on an unmounted NTFS partition).

### LLM serving (llama.cpp, Vulkan)
Two uncensored models, run mutually exclusively (combined Vulkan memory doesn't fit both):
- **Qwen3-4B-Instruct-2507-heretic-av2** (abliterated) — chat/coding/agent-mode, port 8081, `start-qwen3-uncensored.sh`, ~9–11.6 tok/s
- **Gemma-4-E4B-Uncensored-HauhauCS-Aggressive** — chat, text-only, port 8082, `start-gemma-uncensored.sh`, ~9–9.8 tok/s

Censored variants (port 8080) were deleted 2026-08-05 — this box now only serves uncensored models. Full flag-by-flag tuning history, upstream bugs worked around (Qwen3.5-4B caching bug, Gemma SWA/reprocessing, mlock limits, iGPU fence-timeout mitigation, reasoning/tool-call parser fixes), and benchmarks are in [SETUP.md](../SETUP.md) — not reproduced here.

**Secondary/evaluated backend**: OpenVINO Model Server (OVMS) on the same iGPU — Qwen3-8B (port 8084), Qwen3.5-9B text (port 8085, registered in Open WebUI) + vision (port 8086, CPU-only, written but never launched). Not the daily driver; see SETUP.md for why (GPU vision-merger hallucination bug, no HETERO device-split support confirmed).

### Container stack (rootless Podman, Quadlet units, `~/.config/containers/systemd/*.container`)
| Container | Port | Purpose |
|---|---|---|
| open-webui | 3000 | Chat frontend, `--network host`, registered against ports 8080/8081/8082 |
| open-terminal | 8000 (127.0.0.1 only) | Shell/file tool access for chat models |
| searxng | 8888 | Self-hosted search, backs Open WebUI's Web Search toggle |
| metube | 8083 | yt-dlp browser UI, standalone |
| ovms-qwen3-8b / -text / -vision | 8084/8085/8086 | OVMS models above |

All 7 converted to Quadlet 2026-08-14 (fresh `podman run --replace` every start, fixing a stale-container-on-image-update bug the old hand-rolled scripts had). `AutoUpdate=registry` on the first four, `local` on the three OVMS ones (deliberate — GPU-runtime freshness needs a manual check first). None boot-autostart; `start-*.sh` wrapper scripts unchanged. `podman-auto-update.timer` + a companion `podman-image-prune.timer` (daily) both enabled — **fixed 2026-08-18**: the prune service ran `podman image prune -af`, which (since these services are on-demand + Quadlet's `--rm`) deleted every image daily instead of just dangling ones, forcing a full re-pull on every start; now `-f` only.

**Remote access**: Tailscale (`tailscale0` in firewalld's `trusted` zone), Open WebUI reachable at `http://fedora.tail2f4a36.ts.net:3000` from any tailnet device. `open-terminal` deliberately stays `127.0.0.1`-only (shell-execution service, not worth the exposure even over Tailscale).

### Network / firewall (hardened 2026-08-18, see [network-ipv6-setup.md](network-ipv6-setup.md) for full detail)
`firewalld`, zone `FedoraWorkstation`. Current state:
```
services: dhcpv6-client samba-client ssh
ports:    51413/tcp 51413/udp                          # Transmission peer port, deliberate
rich:     192.168.0.0/24 → tcp/udp 1716 accept          # KDE Connect, LAN-only
```
Removed today: a pre-existing `1025-65535/tcp+udp` rule (effectively "allow everything") — harmless under IPv4 CGNAT, a full exposure once IPv6 arrived. Cockpit (9090) disabled+stopped. AnyDesk fully removed (was on 7070). DNS confirmed routed through Tailscale MagicDNS → Pi-hole, no leak.

**Known unrelated issue**: mDNS (`raspberrypi.local`) doesn't resolve from this laptop (`resolvectl mdns` → `no` globally, `systemd-resolved`-side, pre-existing, not caused by anything above). Workaround: `ssh -i ~/.ssh/id_ed25519_raspberrypi -o IdentitiesOnly=yes onkar@raspberrypi-pihole` (Tailscale hostname).

---

## 2. Raspberry Pi 5 — DNS resolver + media server (`raspberrypi`, Debian 13 trixie)

`192.168.0.199` / `raspberrypi.local` (mDNS, broken from the laptop specifically, works elsewhere) / Tailscale `raspberrypi-pihole` (`100.102.227.7`). In-place upgraded bookworm→trixie 2026-08-11 (deliberate, unsupported-but-successful path; two recoverable dpkg conflicts, both fixed).

### Pi-hole (DNS)
Core v6.4.3, upstream via DNS-over-TLS. Blocking mode `NULL` (blocked domains → `0.0.0.0`). Set as the tailnet's **Global Nameserver** (Cloudflare `1.1.1.1`/`1.0.0.1` as silent fallback if the Pi is ever down — no ad-block/encryption when that happens, worth remembering). Admin UI **moved from `80`/`443` to `8080`/`8443` today** to free the standard ports for Caddy — `http://192.168.0.199:8080/admin/`. A second router on the LAN (ACT-supplied Archer C5, `192.168.0.10`) transparently intercepts DNS for devices connected to it, polluting Pi-hole's per-client stats — no fix available (no remote-management/proxy toggle on that router's firmware, reflashing ruled out as too risky/undocumented).

### arr-stack + media server (rootless Podman, `--network host --restart always`, config under `~/media-stack/config/<app>`)
| Container | Port | Notes |
|---|---|---|
| sonarr | 8989 | TV management |
| radarr | 7878 | Movie management |
| prowlarr | 9696 | Indexer management |
| qbittorrent | 8090 | Download client |
| flaresolverr | 8191 | Proxy for Cloudflare-protected indexers |
| jellyfin | 8096 | Media server — **now the only service exposed to the public internet**, via Caddy (see below) |
| homepage | 3000 | Dashboard, widgets for most of the above |
| seerr (container name; app is Jellyseerr) | 5055 | Request management — image is `ghcr.io/seerr-team/seerr:latest`, migrated from `fallenbagel/jellyseerr` at some point without a docs update; verified live 2026-08-18 |
| uptime-kuma | 3001 | Uptime monitoring |

All 9 on Quadlet, `WantedBy=default.target` (boot-autostart, unlike Fedora's on-demand services — this stack needs to be 24/7). `AutoUpdate=registry` + a daily `podman-image-prune.timer`, set up 2026-08-14. Client device: a Mi Box S (HW-decodes H.264/HEVC to 4K/HDR10) — Pi 5 has no H.264 encode block, so the library strategy is direct-play-first, not server-transcode.

**Storage**: still just the 29GB SD card (SD-card rootfs, 11G free / 61% used as of 2026-08-18 — confirmed no external drive attached, `lsblk` shows only `mmcblk0`). Expansion planned, not finalized: a 120GB USB SSD + two old 512GB HDDs were being evaluated, then reconsidered in favor of a new 4TB HDD as primary (better capacity, no unknown-wear risk) with the old HDDs demoted to maybe-secondary pending a SMART check. Nothing purchased/wiped yet. Key constraint whichever drive(s) win: Sonarr/Radarr import via hardlink, so downloads and library must share one filesystem or every import silently degrades to a full copy.

### WiFi reliability (extensive troubleshooting history, condensed — full account in JOURNAL.md/memory)
The Pi's onboard `brcmfmac` WiFi had multiple outage incidents (power-save bug, AP roaming/co-channel interference, a firmware scan-engine wedge with no log trace, three failed BSSID-pinning attempts including one full lockout needing physical console access). **Settled state**: connection left unpinned/roaming (pinning is ruled out — the primary AP gets power-cycled sometimes, and BSSID pinning on this router has caused a full lockout before), `roamoff=1` applied to suppress opportunistic mid-session hops, journald persistent storage fixed (was silently volatile-only), a `wifi-watchdog.service`/`.timer` auto-recovery script installed (ping-based escalation: reconnect → radio bounce → NetworkManager restart → reboot, capped at 2 reboots/hour). **Long-term fix agreed but not yet done**: move the Pi to ethernet — an `eth0-static` profile + a NetworkManager dispatcher arbiter script exist and are tested/safe to use the moment a cable is actually run to the Pi's location.

### Network / firewall (hardened 2026-08-18 — full detail in [network-ipv6-setup.md](network-ipv6-setup.md))
Had **no firewall at all** before today. Now `nftables`, default-deny, enabled + persists reboot:
- Trusted unconditionally: loopback, `tailscale0`, LAN (`192.168.0.0/24` + the full `/64` IPv6 prefix, not just link-local), established/related connections
- Open to the world: SSH (22), and Caddy (80/443, deliberate)
- Everything else — Pi-hole's DNS, the whole arr-stack, Homepage, Uptime Kuma, FlareSolverr — LAN/Tailscale only

**New this session, on top of the firewall**:
- **DuckDNS** (`aagaumulga.duckdns.org`) — tracks the Pi's IPv6 via a 3-minute systemd timer, `AAAA`-only (the stale CGNAT'd `A` record was cleared, it was breaking cert issuance).
- **Caddy** — reverse-proxies `aagaumulga.duckdns.org` → Jellyfin only. Real Let's Encrypt cert, auto-renewing. Jellyfin's `KnownProxies` was empty until **2026-08-18** (every request, including real public users, was logging as `127.0.0.1`); now set to `127.0.0.1` so it trusts Caddy's forwarded client IP.
- **Router IPv6 firewall pinholes** — TCP 80/443 → the Pi, added in the Archer's admin UI (a second, independent blocker found along the way: the router itself was silently dropping unsolicited inbound IPv6 even with the Pi's own firewall open).
- Homepage's Pi-hole widget fixed (was pointed at the now-relocated port 80).

---

## Access reference

| What | From LAN/Tailscale | From the public internet |
|---|---|---|
| Jellyfin | `http://192.168.0.199:8096` | `https://aagaumulga.duckdns.org/` |
| Pi-hole admin | `http://192.168.0.199:8080/admin/` | not reachable (by design) |
| Homepage dashboard | `http://192.168.0.199:3000/` | not reachable |
| Sonarr/Radarr/Prowlarr/qBittorrent/etc. | `http://192.168.0.199:<port>` | not reachable |
| Open WebUI (Fedora) | `http://fedora.tail2f4a36.ts.net:3000` | not reachable |
| SSH to Pi | `ssh -i ~/.ssh/id_ed25519_raspberrypi -o IdentitiesOnly=yes onkar@raspberrypi-pihole` | not reachable — closed 2026-08-18, LAN/Tailscale only now |

## Backup & recovery

Nightly automated backup (Pi, 01:30) + daily off-box pull (Fedora, 09:00), both timers
enabled. Two independent copies (`~/backups` on the Pi, `~/pi-backups` on Fedora —
deliberately outside this git repo, contains secrets). Full detail, restore procedure,
and the restore test actually performed: [pi-backup-restore.md](pi-backup-restore.md).

## Known open items (both boxes)

1. Jellyfin account password strength unverified — check manually now that it's genuinely internet-facing.
2. mDNS broken on the Fedora laptop (pre-existing, `systemd-resolved`-side) — root cause not fixed, workaround (Tailscale hostname) in place.
3. Pi-hole's API/admin auth was found already broken (empty `app_pwhash`, cause not fully pinned down) then deliberately set to a **blank password** 2026-08-18, i.e. auth disabled entirely — confirmed `/api/auth` and `/api/stats/summary` both return full data unauthenticated. Still LAN/Tailscale-only (not internet-facing) per the nftables ruleset, but any LAN/tailnet device can now read/modify Pi-hole's config with no credential. Open question: is this intentional/permanent, or should a real app password be set again? Homepage's widget key updated to match (`key: ""`).
4. No external vantage-point port scan performed — everything was verified via Let's Encrypt's validators succeeding (a real external signal) plus LAN-side testing, not a deliberate scan from outside.
5. Transmission's UPnP/NAT-PMP setting should be turned off (dead weight now, never worked under CGNAT) — not verified done.
6. Storage expansion for the arr-stack (4TB HDD decided in principle, not purchased) and the Pi's ethernet migration (parts tested and ready, cable not yet run) are both open, unrelated to networking.
7. Only Jellyfin is intentionally public. Exposing anything else (the arr-stack, Open WebUI/LocalAI on the Fedora side) should follow the same pattern: narrow firewall rule + Caddy site block + real auth on the service itself.
