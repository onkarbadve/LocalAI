# Architecture

How the pieces on the Fedora daily driver talk to each other. For hardware specifics see [hardware.md](hardware.md); for exact launch flags see [SETUP.md](../SETUP.md).

```mermaid
flowchart LR
    subgraph Remote["📱 Remote device"]
        Phone[Phone / laptop]
    end

    subgraph Tailnet["🔒 Tailscale VPN overlay"]
        Phone -.->|MagicDNS / tailnet IP| WebUI
    end

    subgraph Fedora["🖥️ Fedora box — daily driver"]
        WebUI["Open WebUI<br/>:3000 (Podman, host network)"]
        Term["Open Terminal<br/>:8000 (Podman, loopback only)"]
        Search["SearXNG<br/>:8888 (Podman, loopback only)"]
        MeTube["MeTube<br/>:8083 (Podman, loopback only)"]
        Qwen["llama-server: Qwen3-4B<br/>:8080 (production)"]
        QwenU["llama-server: Qwen3-4B abliterated<br/>:8081 (blunt/direct, mutually exclusive)"]
        GemmaU["llama-server: Gemma-4-E4B abliterated<br/>:8082 (blunt/direct, mutually exclusive)"]

        WebUI -->|OpenAI-compatible API| Qwen
        WebUI -->|OpenAI-compatible API| QwenU
        WebUI -->|OpenAI-compatible API| GemmaU
        WebUI -->|Integration| Term
        WebUI -->|Web Search toggle| Search
    end

    Qwen -->|Vulkan| GPU["Intel Iris Xe iGPU"]
    QwenU -->|Vulkan| GPU
    GemmaU -->|Vulkan| GPU
```

MeTube is a standalone yt-dlp browser UI — it doesn't talk to Open WebUI or any `llama-server`, it just shares the machine and the Podman/loopback-only pattern.

Static export of the diagram above, for viewers without Mermaid rendering: [`images/architecture.png`](images/architecture.png). **Stale as of 2026-08-02** — predates the SearXNG/MeTube/Gemma-uncensored additions above; regenerate from this Mermaid source once `mmdc` is available on this box (see [images/README.md](images/README.md)).

![Architecture diagram](images/architecture.png)

## Components

- **`llama-server` (×3 registered, 1 running at a time)** — the inference engine, built from `llama.cpp` source with the Vulkan backend. Production (`start-qwen3.sh`, port `8080`), an uncensored/blunt-mode Qwen3 variant (`start-qwen3-uncensored.sh`, port `8081`), and an uncensored/blunt-mode Gemma variant (`start-gemma-uncensored.sh`, port `8082`) all register as connections in Open WebUI, but only one process runs at once — combined Vulkan memory doesn't fit more than one simultaneously at their current context sizes (see each script's own memory-budget comment, and [SETUP.md](../SETUP.md#qwen3-4b-instruct-2507-heretic-av2--uncensored-bluntdirect-assistant-start-qwen3-uncensoredsh-fedora-only)). Whichever port is live just shows up in Open WebUI's model picker.
- **Open WebUI (`:3000`)** — chat frontend, rootless Podman container, `--network host` so it can reach `llama-server`'s loopback-only ports without bridge-networking gymnastics.
- **Open Terminal (`:8000`)** — shell/file API wired into Open WebUI as a first-class Integration, giving chat models a place to actually execute commands. Deliberately bound `127.0.0.1`-only, even over Tailscale — see the Direct-vs-System note in [troubleshooting.md](troubleshooting.md#open-webui-terminal-integration-terminal-server-not-found).
- **SearXNG (`:8888`)** — self-hosted metasearch, backs Open WebUI's Web Search toggle (`RAG_WEB_SEARCH_ENGINE=searxng`) so model-issued queries stay local instead of hitting a third-party search API. Loopback-only, same conservative default as Open Terminal — it's a backend JSON API with no auth in front of it, not meant for direct/LAN use.
- **MeTube (`:8083`)** — browser UI for `yt-dlp`, sharing the same download folder as the CLI tool. Standalone: doesn't connect to Open WebUI or any `llama-server`, just runs on the same box under the same rootless-Podman/loopback-only pattern.
- **Tailscale** — VPN overlay for remote access (phone, laptop away from home) without port-forwarding or public exposure. Open WebUI is reachable over the tailnet because `--network host` already binds it to `0.0.0.0:3000`; Open Terminal, SearXNG, and MeTube are deliberately *not* additionally exposed there.
- **OpenVINO Model Server (evaluated, not pictured above)** — a second inference backend (`start-ovms-qwen3-8b.sh`, port 8084, Podman) evaluated as an alternative to llama.cpp/Vulkan. Deliberately not wired into Open WebUI and not part of the daily-driver architecture above — see [SETUP.md](../SETUP.md#alternative-backend-openvino--ovms-evaluated-not-in-daily-use) and [JOURNAL.md](../JOURNAL.md) (2026-08-02/03).

## Design decisions worth calling out

- **Three chat models registered, one running**: rather than reconfigure Open WebUI's connection every time the active model changes, all three `llama-server` ports are registered as connections up front (`OPENAI_API_BASE_URLS`, semicolon-separated). Switching models is just restarting the relevant `start-*.sh` script — Open WebUI reconnects automatically.
- **Open Terminal stays loopback-only**: a shell-execution service gets a more conservative default than the chat UI, which at least has a login page in front of it. This trades away the Files/Terminal side-panel view when accessing remotely (see [troubleshooting.md](troubleshooting.md)) in exchange for zero new network exposure.
- **Podman over Docker**: Fedora's default container engine, rootless by default, no persistent root daemon on a box that's also serving an LLM and reachable over Tailscale. See [JOURNAL.md](../JOURNAL.md) (2026-07-30 entry) for the full reasoning.

## Related documents

- [SETUP.md](../SETUP.md) — flag-by-flag configuration for every script
- [hardware.md](hardware.md) — the machine this runs on
- [troubleshooting.md](troubleshooting.md) — issues hit in this architecture and how they were resolved
- [JOURNAL.md](../JOURNAL.md) — dated log of how this architecture evolved, including why each component was chosen
