# Security

This is a personal, single-user local inference setup — shell scripts and configuration, not a hosted service. Security issues here are almost always about the *documented configuration choices* (network exposure, container privileges, API keys), not exploitable code.

Vulnerabilities in `llama.cpp`, Open WebUI, Open Terminal, SearXNG, or MeTube themselves belong upstream, not here — this repo only owns the launch scripts and flags wrapping them.

## Found something in this repo's own scripts or config?

Email **<onkarbadve@gmail.com>** with what you found, which script/doc it's in, and why it's a security issue rather than a documented trade-off (see below). This is maintained solo in spare time, so response times vary.

## Already-known trade-offs, not new findings

- **Open Terminal, SearXNG, and MeTube bind `127.0.0.1` only, even over Tailscale** — Open Terminal is shell execution, SearXNG has no auth of its own, and MeTube can write arbitrary files; none are worth exposing beyond localhost.
- **Open WebUI binds `0.0.0.0:3000`** as a side effect of `--network host` — mitigated by keeping `WEBUI_AUTH` on and relying on Tailscale as the only realistic path to that port from outside the LAN.
- **API keys stored as plaintext files** (e.g. `~/.config/open-terminal/api-key`, `chmod 600`) — fine for a single-user local machine, not a shared-hosting posture.

If one of these is actually unsafe even under that threat model (a single trusted user, Tailscale-gated), that's still a valid report — explain the scenario where it fails.
