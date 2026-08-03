<div align="center">

# 🧠 LocalAI

**Dual-OS (Windows + Fedora) local LLM serving, built around `llama.cpp` — no discrete GPU, just an Intel iGPU and Vulkan.**

[![OS](https://img.shields.io/badge/Fedora_44-51A2DA?style=flat-square&logo=fedora&logoColor=white)](docs/hardware.md)
[![OS](https://img.shields.io/badge/Windows-0078D6?style=flat-square&logo=windows&logoColor=white)](docs/hardware.md)
[![llama.cpp](https://img.shields.io/badge/llama.cpp-Vulkan_backend-black?style=flat-square)](llama.cpp)
[![Vulkan](https://img.shields.io/badge/Vulkan-iGPU_offload-AC162C?style=flat-square&logo=vulkan&logoColor=white)](docs/hardware.md)
[![Podman](https://img.shields.io/badge/Podman-rootless-892CA0?style=flat-square&logo=podman&logoColor=white)](#quick-start)
[![Open WebUI](https://img.shields.io/badge/Open_WebUI-chat_frontend-1a1a1a?style=flat-square)](#quick-start)
[![Tailscale](https://img.shields.io/badge/Tailscale-remote_access-242424?style=flat-square&logo=tailscale&logoColor=white)](#quick-start)
[![Status](https://img.shields.io/badge/status-active_daily_driver-brightgreen?style=flat-square)](JOURNAL.md)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE)

</div>

---

## Overview

No discrete GPU, no cloud API, no subscription — a 16GB laptop with an Intel iGPU serving multiple local models through llama.cpp's Vulkan backend, fronted by a real chat UI, reachable from a phone over Tailscale. Started on Windows, ported to Fedora as the daily driver.

This repo is both a working setup and its own documentation: every bug, workaround, and dead end along the way is logged in [`JOURNAL.md`](JOURNAL.md), and the polished, structured version of that history lives in [`docs/`](docs/).

## Who is this repository for?

**Suitable for:**
- Developers running local models on Intel integrated graphics (no discrete GPU)
- `llama.cpp` users looking for real Vulkan-backend flags and gotchas, not just defaults
- Open WebUI users wiring up agent-mode tool-calling or the Open Terminal integration
- Anyone learning local AI serving from a documented, working end-to-end setup
- Self-hosted AI enthusiasts wanting remote access (Tailscale) without exposing anything publicly

**Not intended for:**
- CUDA-specific optimization (there is no discrete NVIDIA GPU anywhere in this setup)
- Multi-GPU inference or tensor-parallel serving
- Enterprise AI infrastructure or multi-tenant deployment
- Distributed/clustered serving across multiple machines

## Key Takeaways

- **Zero cloud dependency** — every model runs locally on integrated graphics, nothing leaves the machine.
- **Vulkan iGPU offload** — full-layer GPU offload on an Intel Iris Xe iGPU, no discrete card required, sustaining ~9–9.8 tok/s (full numbers in [`docs/benchmarks.md`](docs/benchmarks.md)).
- **Three chat models, one UI** — a production agent-mode model plus separate uncensored Qwen3 and Gemma variants, all registered in Open WebUI, run mutually exclusively without reconfiguration.
- **Agent tooling** — real tool-calling (Builtin Tools) and a shell/file Integration (Open Terminal), verified end-to-end through Open WebUI in 9/9 real tests, not just curl.
- **Local web search** — self-hosted SearXNG backs Open WebUI's web search/RAG toggle, so model-issued queries stay on the box instead of hitting a third-party search API.
- **Remote access** — reachable from a phone over a Tailscale VPN overlay, no port-forwarding or public exposure.
- **Documented crash hardening** — local patches and mitigations for a real iGPU fence-timeout bug, turning silent crashes into clean, recoverable errors (see [`docs/troubleshooting.md`](docs/troubleshooting.md)).

## Architecture

```mermaid
flowchart TD
    Laptop["Laptop<br/>Intel iGPU, no discrete GPU"] --> Server["llama-server<br/>(llama.cpp, Vulkan backend)"]
    Server --> API["OpenAI-compatible API"]
    API --> WebUI["Open WebUI"]
    WebUI --> Tools["Builtin Tools"]
    WebUI --> Term["Open Terminal"]
    WebUI --> Search["SearXNG<br/>(local web search)"]
    WebUI --> TS["Tailscale"]
    TS --> Remote["Browser / Mobile"]
```

This is the simplified shape of it. For the full diagram — all three `llama-server` ports, container networking, and why the chat models run mutually exclusively — see [`docs/architecture.md`](docs/architecture.md). Hardware specs: [`docs/hardware.md`](docs/hardware.md).

## Quick Start

```bash
# Fedora — start the production chat model
./start-qwen3.sh

# ...or an uncensored variant (mutually exclusive with the above and each other)
./start-qwen3-uncensored.sh
./start-gemma-uncensored.sh

# Chat frontend (Podman, idempotent — creates once, starts thereafter)
./start-open-webui.sh          # → http://localhost:3000

# Shell/file access for the models, wired in as an Open WebUI Integration
./start-open-terminal.sh       # → http://localhost:8000

# Local web search backing Open WebUI's Web Search toggle
./start-searxng.sh             # → http://localhost:8888

# Browser UI for yt-dlp downloads
./start-metube.sh              # → http://localhost:8083
```

Models aren't checked into this repo (multi-GB GGUF files). Building `llama.cpp` from source, placing model weights, Tailscale setup, and every flag's reasoning are in [`SETUP.md`](SETUP.md) — start there for anything beyond running an already-built setup.

## Repository at a Glance

| | |
|---|---|
| **Hardware** | Intel i5-12500H · Intel Iris Xe iGPU · 16GB RAM — no discrete GPU |
| **OS** | Fedora 44 (daily driver) · Windows (origin, preserved) |
| **Inference** | `llama.cpp`, Vulkan backend, full-layer GPU offload |
| **Chat frontend** | Open WebUI + Open Terminal, rootless Podman |
| **Remote access** | Tailscale VPN overlay |
| **License** | MIT |
| **Status** | Active daily driver ([`JOURNAL.md`](JOURNAL.md)) |

```text
LocalAI/
├── llama.cpp/                    # upstream checkout, built from source (Vulkan) — gitignored, see docs/hardware.md
├── models/                       # GGUF weights — gitignored, multi-GB binaries, see docs/hardware.md
├── start-qwen3.sh                # production chat/coding/agent model
├── start-qwen3-uncensored.sh     # abliterated blunt/direct-assistant variant
├── start-gemma-e4b.sh            # vision chat (deprioritized)
├── start-gemma-uncensored.sh     # abliterated Gemma variant, own port, mutually exclusive with the above
├── start-open-webui.sh           # Open WebUI, rootless Podman
├── start-open-terminal.sh        # shell/file API for the models, rootless Podman
├── start-searxng.sh              # self-hosted metasearch, backs Open WebUI's Web Search toggle, rootless Podman
├── start-metube.sh               # yt-dlp browser UI, rootless Podman
├── start-ovms-qwen3-8b.sh        # Qwen3-8B via OpenVINO Model Server — evaluated backend, not the daily driver
├── docs/                         # topic-specific reference docs and screenshots (see Documentation below)
├── SETUP.md                      # hardware, flags, models, full technical reference
├── JOURNAL.md                    # dated log of every change, fix, and incident — the source of truth
└── AGENTS.md                     # conventions for AI coding agents working in this repo
```

`llama.cpp/` and `models/` exist locally once [`SETUP.md`](SETUP.md)'s steps are followed, but aren't checked into Git — see [`docs/hardware.md`](docs/hardware.md#why-models-and-llamacpp-arent-in-git) for why.

## Screenshots

Not yet captured — placeholders below and capture checklist in [`docs/images/`](docs/images/). Replace the files in place as real screenshots are taken.

| Open WebUI home | Chat interface | Model selection |
|:---:|:---:|:---:|
| ![Open WebUI homepage placeholder](docs/images/openwebui-home.png) | ![Chat interface placeholder](docs/images/chat.png) | ![Model selection placeholder](docs/images/model-selection.png) |

| Mobile access (Tailscale) | Open Terminal integration |
|:---:|:---:|
| ![Mobile access placeholder](docs/images/mobile.png) | ![Open Terminal integration placeholder](docs/images/open-terminal.png) |

## Benchmarks

| Model | Quant | Context | Speed | RAM | GPU Memory | Notes |
|-------|-------|---------|-------|-----|------------|-------|
| Qwen3-4B-Instruct-2507 | Q4_K_XL | 24576 | ~9–9.8 tok/s | ~530MB RSS | ~6GB | Production, port 8080 |
| Qwen3-4B-Instruct-2507-heretic-av2 | Q4_K_M | 24576 | ~9–11.6 tok/s | TODO | ~6GB | Blunt/direct, port 8081 |
| Gemma 4 E4B-it + mmproj | Q4_K_XL | 8192 | ~9–9.8 tok/s | TODO | TODO | Deprioritized fallback |
| Gemma-4-E4B-Uncensored-HauhauCS-Aggressive | Q4_K_P | 16384 | ~7.4 tok/s gen, ~41 tok/s prompt | TODO | ~5.3GB | Blunt/direct, port 8082 |

Full numbers, multi-turn cache-reuse data, and agent-mode round-trip timings: [`docs/benchmarks.md`](docs/benchmarks.md). An OpenVINO/OVMS backend was also evaluated on the same iGPU (not the daily driver) — see the [OpenVINO section there](docs/benchmarks.md#openvino--ovms-evaluated-backend-not-in-daily-use).

## Documentation

| File | What's in it |
|---|---|
| [`SETUP.md`](SETUP.md) | Hardware, directory layout, per-model flags, every issue hit and how it was resolved |
| [`docs/architecture.md`](docs/architecture.md) | Component breakdown and design rationale |
| [`docs/hardware.md`](docs/hardware.md) | Machine specs, Windows vs. Fedora, why `models/`/`llama.cpp/` aren't in Git |
| [`docs/models.md`](docs/models.md) | Every model tested, compared side by side |
| [`docs/benchmarks.md`](docs/benchmarks.md) | Full performance numbers |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Structured Problem/Cause/Solution/Verification writeups |
| [`docs/lessons-learned.md`](docs/lessons-learned.md) | Practical conclusions from real experimentation, by topic |
| [`docs/roadmap.md`](docs/roadmap.md) | Completed / upcoming / future-idea work, in more detail than below |
| [`docs/compatibility.md`](docs/compatibility.md) | Tested versions of every OS/tool in the stack |
| [`JOURNAL.md`](JOURNAL.md) | Dated running log — newest entries first, the historical source of truth |
| [`AGENTS.md`](AGENTS.md) | Conventions for AI coding agents working in this repo |
| [`llama.cpp/AGENTS.md`](llama.cpp/AGENTS.md) | Upstream contribution rules (only relevant inside `llama.cpp/`) |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to propose changes to this repo |
| [`SECURITY.md`](SECURITY.md) | Reporting a security issue, and documented network-exposure trade-offs |

## Roadmap

Framed as independent "chapters," each worth going deep on rather than a backlog to clear in order. Summary below; full detail (including future ideas beyond this list) in [`docs/roadmap.md`](docs/roadmap.md):

- [x] Web-search grounding via self-hosted SearXNG (see [`JOURNAL.md`](JOURNAL.md), 2026-08-01)
- [ ] Close the remaining hallucination gap with document RAG
- [ ] Port the Windows-only MCP tool stack (filesystem/git/memory/fetch/shell) to Fedora
- [ ] Resolve the iGPU fence-timeout bug upstream, not just mitigate it
- [ ] Proper concurrent serving instead of manual model swapping
- [ ] Voice via `whisper.cpp`, routed around Gemma's dead-end audio path
- [ ] A small personal LoRA fine-tune
- [ ] Turn crash monitoring into real self-healing infrastructure
- [ ] A repeatable, scripted model-evaluation pipeline

---

<div align="center">
<sub>Built and maintained by <a href="https://github.com/onkarbadve">onkar</a> — a one-person, one-laptop local inference lab.</sub>
</div>
