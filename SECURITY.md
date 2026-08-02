# Security Policy

## Scope

This repository documents a **personal, single-user local inference setup** — shell scripts and configuration, not a hosted service or a library other software depends on. There is no packaged release, no dependency tree consumers pull in, and no multi-tenant deployment. Security issues here are almost always about the *documented configuration choices* (network exposure, container privileges, API key handling), not about a codebase with exploitable input parsing.

Relevant components, for context on what a report might touch:
- Three `llama-server` processes, one running at a time (llama.cpp, upstream project — report llama.cpp-specific vulnerabilities to [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) directly, not here).
- Open WebUI, Open Terminal, SearXNG, and MeTube, all run as containers (upstream projects — same note applies for vulnerabilities in their code itself).
- This repo's own contribution: the launch scripts, flag choices, and network-exposure decisions wrapping those components.

## Reporting a vulnerability

If you find a real security issue in **this repository's own scripts or documented configuration** (for example: a script that would expose a service more broadly than documented, an API key handled unsafely, or a documented mitigation that's actually ineffective), please report it privately rather than opening a public issue:

**<onkarbadve@gmail.com>**

Include:
- What you found and why it's a security issue (not just a bug).
- Which script/document it's in.
- A suggested fix if you have one.

Expect an acknowledgment within a reasonable timeframe — this is a personal project maintained in spare time, not a funded security response team.

## What's already a known, deliberate trade-off (not a new finding)

A few things that might look like issues at first glance are documented, intentional decisions — see [docs/architecture.md](docs/architecture.md) and [docs/troubleshooting.md](docs/troubleshooting.md) for the reasoning:

- **Open Terminal binds `127.0.0.1` only, even over Tailscale** — a deliberate trade-off (loses remote Files/Terminal side-panel access) to avoid exposing a shell-execution API beyond localhost.
- **SearXNG and MeTube also bind `127.0.0.1` only** — same reasoning as Open Terminal: SearXNG is a backend JSON API with no auth of its own, and MeTube can write arbitrary files to the download folder, so neither is exposed beyond localhost even over Tailscale.
- **Open WebUI binds `0.0.0.0:3000`** as a side effect of `--network host` — mitigated by keeping `WEBUI_AUTH` on and relying on Tailscale as the only path to that port from outside the LAN, not a public-internet exposure.
- **API keys stored as plaintext files** (`~/.config/open-terminal/api-key`, `chmod 600`) — acceptable for a single-user local machine, not a multi-user or shared-hosting posture.

If you believe one of these trade-offs is actually unsafe even under its stated threat model (a single trusted user, access gated by a personal Tailscale network), that's a valid report — explain the specific scenario where it fails.

## What's out of scope

- Vulnerabilities in `llama.cpp`, Open WebUI, or Open Terminal themselves — report those upstream.
- Vulnerabilities in model weights (`models/`, not checked into this repo).
- General hardening advice not tied to a specific exploitable issue in this repo's own scripts.
