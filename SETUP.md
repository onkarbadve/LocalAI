# Local AI Setup — Technical Reference

Dual-OS (Windows + Fedora) local LLM serving via llama.cpp, GPU-accelerated on an integrated GPU with no discrete card. Windows setup (`C:\LocalAI`) came first; Fedora (`~/LocalAI`) is the current daily driver, ported from it.

This is the full flag-by-flag reference. For narrower, topic-specific docs, see [`docs/`](docs/): [architecture](docs/architecture.md), [hardware](docs/hardware.md), [models](docs/models.md), [benchmarks](docs/benchmarks.md), [troubleshooting](docs/troubleshooting.md), [lessons learned](docs/lessons-learned.md), [roadmap](docs/roadmap.md). For the dated history behind every decision here, see [`JOURNAL.md`](JOURNAL.md), or [`adr/`](adr/) for the same decisions distilled into stable records.

## Hardware / OS

| | |
|---|---|
| CPU | Intel i5-12500H (4P+8E cores, 16 threads) |
| GPU | Intel Iris Xe iGPU (no discrete GPU), via Vulkan |
| RAM | 16GB system RAM (~7.4-9.8GB Vulkan-visible budget) |
| Current OS | Fedora 44 (`~/LocalAI`) |
| Prior OS | Windows (`C:\LocalAI`, preserved on a ~340GB NTFS partition, `/dev/nvme0n1p3` — not mounted by default; mount read-only at `/mnt/winc` to inspect) |
| Inference engine | llama.cpp, Vulkan backend (`GGML_VULKAN=ON`) |

## Directory layout

**Fedora (`~/LocalAI`)**
- `llama.cpp/` — built from source, Vulkan backend
- `models/` — `Qwen3-4B-Instruct-2507-UD-Q4_K_XL.gguf`, `gemma-4-E4B-it-UD-Q4_K_XL.gguf`, `mmproj-F16.gguf`, `Qwen3-4B-Instruct-2507-heretic-av2.Q4_K_M.gguf`
- `start-qwen3.sh`, `start-gemma-e4b.sh` — llama.cpp launch scripts
- `start-qwen3-uncensored.sh` — abliterated Qwen3-4B-Instruct-2507 (arnomatic/heretic-av2), separate blunt/direct-assistant role, port 8081, see below
- `start-open-webui.sh` — launches Open WebUI (Podman container) as a chat frontend, see below
- `start-open-terminal.sh` — launches Open Terminal (Podman container), a shell/file API wired into Open WebUI as an Integration, see below
- `linkedin-post.md` — write-up of the Windows→Linux port
- `SETUP.md` — this document

**Windows (`C:\LocalAI`)**
- `bin/` — precompiled official Vulkan release (currently b10107), `bin-b9305-backup/` — prior build kept for instant rollback
- `models/` — same two models plus `qwen2.5-coder-1.5b-instruct-q4_k_m.gguf` (autocomplete) and `Qwen3.5-4B-UD-Q4_K_XL.gguf` (retired, see below)
- `Start-Server.bat`, `Start-Server-Gemma4-E4B.bat` — single-server launch scripts
- `startCoding.bat` — dual-server coding setup (chat + autocomplete)
- `startMCP.bat` — 5 MCP servers for a coding-agent workflow
- `sarvam-translate/` — unrelated side project (Sarvam AI translation API wrapper)
- `Debloat-Windows.ps1` — unrelated Windows debloat script
- Various `server_out.*.log` files — tuning/verification session logs referenced below

## Models in production

| Model | Quant | Use | Speed (iGPU) | Status |
|---|---|---|---|---|
| Qwen3-4B-Instruct-2507 | Unsloth Dynamic Q4_K_XL | Chat / coding / agent-mode | ~9-9.8 tok/s | Production (port 8080) |
| Qwen3-4B-Instruct-2507-heretic-av2 (arnomatic, abliterated) | mradermacher Q4_K_M | Blunt/direct assistant, no refusals on sensitive-but-legal topics | ~9-11.6 tok/s | Secondary, port 8081 - mutually exclusive with the two above (combined Vulkan memory doesn't fit; see JOURNAL 2026-07-30) |
| Gemma 4 E4B-it + mmproj-F16 | Unsloth Dynamic Q4_K_XL | Vision chat | ~9-9.8 tok/s | **Deprioritized** (2026-07-30) - more crash/hang-prone than Qwen3 beyond the shared iGPU fence-timeout bug, and vision is no longer a hard requirement; kept as a fallback, not actively used |
| Qwen2.5-Coder-1.5B (Windows only) | Q4_K_M | Autocomplete | — | Production (Windows only) |

## Steps followed (chronological)

1. **Windows**: tuned Qwen3.5-4B + Gemma 4 E4B on `C:\LocalAI` with Vulkan offload, quantized KV cache, flash attention, thread counts matched to the P-core/E-core split.
2. **Windows**: hit a multi-turn caching bug on Qwen3.5-4B (see Issues #1) and switched to Qwen3-4B-Instruct-2507 (2026-07-26).
3. **Windows**: upgraded the llama.cpp build from b9305 to b10107 (precompiled Vulkan zip), re-verified layer offload, `--swa-full` behavior, and generation speed were unchanged; kept the old build as a rollback folder.
4. **Windows**: added Gemma vision support via `--mmproj`, discovered and worked around the multi-turn reprocessing bug with `--swa-full`, confirmed audio does not work.
5. **Windows**: built a secondary coding-assistant setup (`startCoding.bat`, two servers) and an MCP server stack (`startMCP.bat`) for agentic coding workflows.
6. **Fedora**: switched OS this past weekend (partly to reclaim RAM Windows was holding onto).
7. **Fedora**: built llama.cpp from source with the Vulkan backend, working through the build dependency issues below.
8. **Fedora**: placed the same GGUF models under `~/LocalAI/models` and ported the tuned flags into two shell scripts.
9. **Fedora**: verified GPU offload indirectly (low RSS after generation confirms the model lives in Vulkan memory, not process RAM).
10. **Fedora**: wrote up the port (`linkedin-post.md`).

## Per-script configuration

### Qwen3-4B-Instruct-2507 — solo chat (`start-qwen3.sh` / `Start-Server.bat`)

| Flag | Fedora | Windows |
|---|---|---|
| Port | 8080 | 8080 |
| `-t` (threads) | 8 | 8 |
| `-c` (context) | 24576 | 24576 |
| `-ngl` | unset (auto, defaults to full offload) | 37 (explicit — output layer was left on CPU at 36) |
| `-fa` | on | on |
| `--mlock` | not used (see Issues #2) | used — kept, small footprint |
| Sampling | `--temp 0.7 --top-p 0.8 --top-k 20 --min-p 0` (Qwen non-thinking defaults) | same |

### Gemma 4 E4B-it — vision chat (`start-gemma-e4b.sh` / `Start-Server-Gemma4-E4B.bat`)

| Flag | Fedora | Windows |
|---|---|---|
| Port | 8080 | 8080 |
| `-t` | 8 | 8 |
| `-c` | 16384 (reduced from 32768 to fit mmproj) | 16384 (same reasoning) |
| `-ngl` | unset (auto full offload) | unset (`--fit` auto-detects 43/43 layers) |
| `-ctk`/`-ctv` | q8_0 (quantized KV cache) | q8_0 |
| `-fa` | on | on |
| `--swa-full` | yes — required, see Issues #3 | yes |
| `--mmproj` | mmproj-F16.gguf (vision) | same |
| `--mlock` | not used | **removed** — crashed a browser tab once under memory pressure |
| Sampling | Google's published Gemma defaults: `--temp 1.0 --top-p 0.95 --top-k 64 --min-p 0.0` | same |
| `GGML_VK_MAX_NODES_PER_SUBMIT` (env, Fedora only) | `1` (default 100) — trial fix for `i915` fence-timeout/GPU-hang incidents, see JOURNAL.md 2026-07-28 | not set |

Both single-server scripts (both OSes) bind port 8080 — only one server runs at a time.

Fedora's `start-gemma-e4b.sh` also carries two local, unsubmitted patches to the `llama.cpp` source (`tools/server/server-context.cpp`, `tools/server/server-task.cpp`) that catch a Vulkan `DeviceLostError` in the prompt-cache save/load path instead of crashing the server — see JOURNAL.md 2026-07-28 for the two coredump traces that led to them. These do not survive a `git pull`/rebuild of `llama.cpp/` and must be reapplied by hand.

### Qwen3-4B-Instruct-2507-heretic-av2 — uncensored blunt/direct assistant (`start-qwen3-uncensored.sh`, Fedora only)

Abliterated via the "Heretic" tool (arnomatic/Qwen3-4B-Instruct-2507-heretic-av2, GGUF from mradermacher). Chosen over other uncensored candidates specifically because it shares the exact base model/chat template already proven stable in production (`Qwen3-4B-Instruct-2507`), so it inherits the same generic-autoparser tool-calling path rather than a bespoke, bug-prone parser. Verified via the UGI Leaderboard (highest UGI/NatInt of same-base options as of 2026-01-02) — see JOURNAL.md 2026-07-30 for the full selection reasoning.

| Flag | Value |
|---|---|
| Port | 8081 (separate from production's 8080) |
| `-t` | 8 |
| `-c` | 24576 |
| `-fa` | on |
| `--reasoning off` | yes — same shared-template reasoning-branch bug as production Qwen3 |
| `GGML_VK_MAX_NODES_PER_SUBMIT=1` | yes — same iGPU fence-timeout mitigation, backend-level not model-specific |
| `--repeat-penalty` / `--repeat-last-n` | 1.1 / 256 — added after a long-form generation test degenerated into a repeated-phrase loop |
| `--dry-multiplier` | 0.8 — DRY sampling, penalizes repeated phrase sequences specifically |
| `-n` | 2048 — hard cap on tokens per response (~1,500-1,700 words), the guaranteed backstop against runaway/looping generation |
| Sampling | `--temp 0.7 --top-p 0.8 --top-k 20 --min-p 0` (same Qwen3 non-thinking defaults) |

**Role and limits**: a deliberately separate, occasional-use model for blunt/direct engagement on sensitive-but-legal topics — not agent-mode duty (untested against Open WebUI's real tool-calling request shape) and not a factual reference (confirmed to confabulate confidently on niche real-world facts, same as any 4B model). **Run mutually exclusively with production Qwen3** — both at `-c 24576` would be ~12GB Vulkan-visible combined, over the ~7.4-9.8GB budget (see JOURNAL.md 2026-07-30).

### Open WebUI — chat frontend (`start-open-webui.sh`, Fedora only)

Rootless Podman container (`ghcr.io/open-webui/open-webui:main`), point at whichever llama.cpp server is currently running.

- `--network host`: llama-server binds `127.0.0.1:8080` (loopback only, not `0.0.0.0`), so bridge networking + `host.containers.internal` can't reach it. Host networking sidesteps that — the container sees `localhost` exactly like the host does.
- `PORT=3000` (container env): Open WebUI defaults to 8080 internally, which would collide with llama-server on the host network.
- `OPENAI_API_BASE_URLS="http://localhost:8080/v1;http://localhost:8081/v1"`, `OPENAI_API_KEYS="sk-no-key-required;sk-no-key-required"` (plural, semicolon-separated — added 2026-07-30): registers both the production Qwen3 server (8080) and the uncensored model's server (8081, `start-qwen3-uncensored.sh`) as connections at once, so whichever one is actually running shows up in the model picker without reconfiguring Open WebUI each time. The two `llama-server` processes are still run mutually exclusively (combined Vulkan memory doesn't fit both, see JOURNAL.md 2026-07-30) — whichever port is down just appears unreachable in the picker rather than erroring at Open WebUI startup.
- `WEBUI_AUTH` left at its default (on): with `--network host`, port 3000 binds `0.0.0.0`, reachable from the whole LAN — so the signup/login screen stays on rather than exposing an open chat UI to the network.
- Data persisted in a named Podman volume (`open-webui-data`), not bind-mounted.
- Script is idempotent: first run creates the container, later runs just `podman start` the existing one.

UI: http://localhost:3000 — first visit creates the local admin account. Switching which llama.cpp model is active just means restarting the underlying `start-*.sh` script for the port you want live; Open WebUI already has both 8080 and 8081 registered as connections (see above), so it reconnects automatically rather than needing reconfiguration.

Not yet ported to Windows (no Podman/Docker there currently).

### Open Terminal — shell/file access for chat models (`start-open-terminal.sh`, Fedora only)

Rootless Podman container (`ghcr.io/open-webui/open-terminal:slim`), giving Open WebUI's models a remote shell + file browser, wired in as a first-class Open WebUI Integration (Admin/personal Settings → Integrations → Open Terminal) rather than a generic OpenAPI tool server.

- `-p 127.0.0.1:8000:8000` (bridge networking, not `--network host` like Open WebUI's script): Open WebUI's backend proxies requests to it, so it only needs to be reachable from the host, not the LAN — unlike port 3000, this has no login page in front of it, just the API key.
- `slim` image tag (~430MB) over `latest` (~4GB, full Node/gcc/ffmpeg/LaTeX toolkit) — matches the footprint-conscious posture used elsewhere on this 16GB box. Swap the tag if heavier tooling is ever needed.
- API key generated once (`openssl rand -hex 32`) and stored at `~/.config/open-terminal/api-key` (`chmod 600`), read by the script at launch — not hardcoded.
- Data persisted in a named Podman volume (`open-terminal-data`), mounted at `/home/user`.
- Same idempotent-restart pattern as `start-open-webui.sh`.

Configure once in Open WebUI: Settings → Integrations → Open Terminal → URL `http://localhost:8000`, paste the API key from the file above. Not yet ported to Windows.

**Important**: that personal Settings page only creates a "Direct" connection (`user.settings.ui.terminalServers`), which powers the Files/Terminal side panels but is *not* visible to chat tool-calling — the backend resolves terminal tool calls against a separate system-level list (`Config` key `terminal_server.connections`, admin-only, no linked UI page as of v0.11.0). For the model to actually invoke terminal commands from chat, that system-level entry must exist too (see JOURNAL.md 2026-07-29 for how it was added via a direct API call). In the chat composer's terminal-attach dropdown, pick the entry under "SYSTEM", not "DIRECT".

**Remote access (Tailscale) implication**: the Direct connection's Files/Terminal side panels make client-side browser requests straight to its configured URL (`http://localhost:8000`) — that only resolves correctly when the browser and the Fedora box are the same machine. Accessed remotely (e.g. over Tailscale from a phone), "localhost" is the phone, not the server, so the panels fail even though chat tool-calling (System connection, backend-proxied) keeps working fine. Resolution: the personal Direct entry was deleted entirely (2026-07-29) rather than exposing `open-terminal` on the Tailscale interface — trades away the Files/Terminal side-panel view when remote in exchange for keeping `open-terminal` fully `127.0.0.1`-only (no new network exposure). Chat-based terminal tool use is unaffected either way.

### Remote access (Tailscale, Fedora only)

Access Open WebUI from outside the home network (phone, laptop) without exposing anything to the public internet — a VPN overlay rather than port-forwarding, since one of the things sitting behind it (Open Terminal) is a shell-execution service.

- Installed via Fedora's own repos (already present as of Fedora 44 / package `tailscale` 1.98.8 — the separate `pkgs.tailscale.com` repo wasn't actually needed): `sudo dnf install -y tailscale`, `sudo systemctl enable --now tailscaled`, `sudo tailscale up` (prints a one-time browser URL to authorize the device).
- Fedora box's tailnet IP: `100.93.33.122` (stable — persists across reboots as part of `tailscaled`'s state, doesn't need re-authorizing). Phone already joined the same tailnet as `a34`.
- firewalld is active on this box; `tailscale0` wasn't in any zone by default, so traffic to it wasn't guaranteed to pass. Explicitly set: `sudo firewall-cmd --permanent --zone=trusted --change-interface=tailscale0 && sudo firewall-cmd --reload`. Safe to trust fully — only devices you've personally authorized into your own tailnet can reach that interface at all.
- No changes needed to `start-open-webui.sh` — it already binds `0.0.0.0:3000` (a consequence of `--network host`, see above), so anything reachable on the tailscale interface just works once the firewalld zone is set.
- `open-terminal` deliberately was **not** additionally exposed on the tailscale interface — see the Direct-vs-System note above. It remains `127.0.0.1`-only.

Access from another tailnet device: `http://fedora.<tailnet-name>.ts.net:3000` (MagicDNS — was already enabled tailnet-wide, no setup needed) or the raw IP `http://100.93.33.122:3000`.

### Windows-only: coding-assistant dual server (`startCoding.bat`)

- Qwen3-4B-Instruct-2507 on port 8080 (`-c 16384`, reduced from the solo 24576 to leave VRAM headroom for the second server), chat/edit/agent
- Qwen2.5-Coder-1.5B on port 8081 (`-t 4 -c 4096 -ngl 99`, full offload — tiny model), autocomplete
- Not yet ported to Fedora.

### Windows-only: MCP server stack (`startMCP.bat`)

Five MCP servers via `mcp_proxy` (streamablehttp transport), backing a coding-agent workflow against a project called "SpringAI":

| Server | Port | Target |
|---|---|---|
| Filesystem | 3001 | `C:\Users\onkar\SpringAI` |
| Memory | 3002 | — |
| Git | 3003 | `C:\Users\onkar\SpringAI` |
| Fetch | 3004 | — |
| Shell (`super-shell-mcp`) | 3005 | — |

Not yet ported to Fedora.

## Issues encountered and resolutions

Narrative account below, in the order encountered. For the same issues in a scannable Problem/Cause/Solution/Verification format, see [`docs/troubleshooting.md`](docs/troubleshooting.md).

### 1. Qwen3.5-4B multi-turn caching bug → switched models
Qwen3.5-4B's hybrid attention + Mamba2/SSM architecture hit an upstream llama.cpp bug: `cached_tokens` stuck at 82 regardless of turn number on multi-turn requests (`ggml-org/llama.cpp#21831`, open/unresolved as of build b10107, 2026-07-24). It's a checkpoint-*restore-selection* bug, not a checkpoint-frequency one, so `-cpent`/`-ctxcp` tuning didn't help. **Resolution**: switched to dense Qwen3-4B-Instruct-2507, which has no recurrent memory and isn't subject to the bug (2026-07-26).

### 2. `--mlock` behavior — different failure modes on each OS
- **Windows**: worked for the smaller Qwen footprint; kept there. For Gemma+vision (larger footprint), it fought the OS under memory pressure and crashed a browser tab once (at 0.59GB free) — removed for that script specifically, relying on mmap instead.
- **Fedora**: fails uniformly regardless of model — `ulimit -l` is capped at 8MB by systemd's `user@.service` unit (a default hardening limit). The common advice to edit `/etc/security/limits.conf` doesn't apply on modern Fedora, since desktop session limits come from systemd, not PAM.
- **Resolution**: given the Windows experience already showed mlock is risky under pressure on this 16GB machine, decided not to fight the Linux systemd limit either — both Fedora scripts use plain mmap, letting the kernel page cold parts out instead of risking a hard OOM.

### 3. Gemma reprocessing the full conversation every turn
Without `--swa-full`, every multi-turn request logged "forcing full prompt re-processing due to lack of cache data" and reprocessed the entire conversation from scratch (verified: `cached_tokens=0` on turn 2). This build already contains the underlying fix (`ggml-org/llama.cpp#22288`) but it's opt-in. **Resolution**: added `--swa-full`; verified a 2-turn test correctly reused the cached prefix (`cached_tokens=18/45` on turn 2). Cost: SWA KV cache grows from ~293MB to ~952MB.

### 4. Gemma + audio does not work
Two independent upstream blockers:
1. llama-server's HTTP API has no audio input routing at all (`ggml-org/llama.cpp#21868`, closed "not planned" by upstream).
2. `llama-mtmd-cli` (the CLI workaround) crashes (`0xC0000409`/abort) loading this model+mmproj combination before it even reaches the audio processing step. Tried `-ub 2048` and `--no-warmup` (fixes for two *other* known audio bugs, `#21825` and an mtmd-cli warmup crash) — neither resolved it.

**Resolution**: accepted as a limitation — vision-only for now.

### 5. Fedora Vulkan build dependencies
llama.cpp's Vulkan backend needs a package named exactly `glslc` — not `glslangValidator`, which looks like the same tool but isn't. Two further missing CMake dependencies (`spirv-headers-devel`, `spirv-tools-devel`) were needed before the build would configure. **Resolution**: installed the correct package names.

### 6. Qwen3-4B-Instruct-2507 hangs / runaway generation via Open WebUI's reasoning + tool-call request params (Fedora, found via Open WebUI)
After wiring up Open WebUI (see below), a plain "hi" never returned a response. Two layered issues, both stemming from Open WebUI unconditionally sending `"reasoning_format":"deepseek"` per-request against a non-thinking model whose template still has reasoning/tool-call branches (Qwen3-4B-Instruct-2507's template is shared with the thinking variant, but this checkpoint never emits `<think>` tags):
1. **First symptom - true runaway generation**: `--reasoning` defaulted to `auto` (detected from the chat template), which flagged the model as reasoning-capable; the parser waited indefinitely for a closing think tag that never came, so generation never resolved into a stopped "content" state (`/slots` showed 2000+ tokens decoded and climbing). Adding `--reasoning off` stopped that specific runaway, but per-request `reasoning_format` sent by the client still overrides the CLI default, so the underlying mismatch wasn't fully closed.
2. **Second symptom - post-generation hang**: with `--reasoning off` alone, a later request showed `/slots` with `"has_next_token":false` (generation had actually finished) while `"is_processing":true` stayed stuck forever - hung in llama-server's `chat_format:"peg-native"` response formatter/tool-call parser, not in generation itself.

Not related to Open WebUI's function-calling mode (confirmed already set to Default, not Native) - the client sends `reasoning_format` regardless of that toggle. **Resolution**: added `--skip-chat-parsing` (forces a pure content parser, dumping everything into `message.content` unparsed, bypassing the native reasoning/tool-call formatter entirely) alongside `--reasoning off` in `start-qwen3.sh`. Verified fixed by replicating Open WebUI's exact request shape directly (`stream:true, reasoning_format:"deepseek"`) - clean SSE stream, `finish_reason:"stop"`, ~1.6s.

Side effect encountered while debugging: killing a stuck llama-server mid-generation freed a large chunk of page-cache-resident model memory, and the next launch needed a fresh Vulkan shader warm-up - a plain relaunch took 25s+ before `/health` responded, easily mistaken for a second hang. Not a bug, just cold-start cost repeating.

**This fix is Qwen3-specific, not a general "add to every model" rule.** When switching to Gemma 4 E4B, tested it directly against Open WebUI's exact request shape before assuming the same flags applied: plain chat, chat with a `tools` block present, and multi-turn recall, all with `stream:true, reasoning_format:"deepseek"`. All three completed cleanly (`finish_reason:"stop"`, 1-5s, no `/slots` hang) *without* `--reasoning off` / `--skip-chat-parsing` - and with a `tools` block present, Gemma correctly separated its reasoning into `reasoning_content` and its answer into `content`, something `--skip-chat-parsing` would flatten and lose. Root cause was Qwen3-4B-Instruct-2507's specific template/checkpoint mismatch (template supports thinking, checkpoint never uses it); Gemma's template doesn't have that mismatch, so `start-gemma-e4b.sh` intentionally does not carry these flags. Re-test before adding them to any other model rather than assuming this fix generalizes.

### 7. Port collision (both platforms)
Both single-server scripts bind port 8080 by design — running Qwen and Gemma simultaneously isn't supported as-is on either OS. **Workaround**: `pkill -f llama-server` (Linux) / close the other server window (Windows) before switching.

## Verified performance notes

See [`docs/benchmarks.md`](docs/benchmarks.md) for the fuller table (multi-turn cache reuse, agent-mode round-trip timings) built from these same numbers.

- Both models: ~9-9.8 tok/s generation on the iGPU, on both OSes.
- Cold start (fresh boot, one-time Vulkan shader compilation):
  - Windows: ~30-90s first load, ~7s on subsequent restarts once the driver's shader cache is warm.
  - Fedora: ~2.5 tok/s prompt processing on the very first request, ~28 tok/s once Mesa's shader cache is warm.
- Windows build upgrade b9305 → b10107: re-verified 43/43 layer offload unchanged, `--swa-full` cache reuse still works, generation speed unchanged (~8-9.5 tok/s), compute buffer shrank ~517MB → ~187MB (more headroom). Old build kept at `bin-b9305-backup` as an instant rollback (swap the folder back to `bin`).
- Qwen offload verified via low RSS (~530MB) after a real generation — confirms the model lives in Vulkan/GPU memory, not process RAM.

## Path forward

Roadmap discussion held 2026-07-30, framed as "chapters" — each is its own project, not a backlog to clear in order. Picking one to go deep on at a time, rather than spreading thin across all of them, was the explicit intent.

1. **Close the loop on hallucination (RAG)**: the uncensored model confirmed it confabulates confidently on real-world facts it doesn't actually know (JOURNAL.md 2026-07-30). Open WebUI already supports document upload / web-search grounding — wiring that in properly would fix the actual weakness rather than just documenting it.
2. **Port the Windows-only MCP tooling to Fedora**: the dual-server coding setup (`startCoding.bat`) and the five-server MCP stack (`startMCP.bat`, filesystem/git/memory/fetch/shell) never made the jump — Fedora's agent currently only has Open Terminal's shell access, not the fuller toolkit already proven out on Windows.
3. **Actually resolve the iGPU fence-timeout bug, not just mitigate it**: `GGML_VK_MAX_NODES_PER_SUBMIT=1` is still an unconfirmed trial fix (JOURNAL.md 2026-07-28). Validate it over real extended use, then file the upstream `i915` bug properly with the dmesg traces/coredumps already gathered, rather than leaving it as a private workaround.
4. **Concurrent serving, done properly**: mutual exclusivity between production and the uncensored model rests on an unexamined assumption (both at full `-c 24576`, ~12GB combined, over budget — see JOURNAL.md 2026-07-30). Shrinking contexts and/or adding a lightweight router in front of both ports could get genuine concurrency instead of manual swapping.
5. **Voice, routed around Gemma's dead-end audio path**: Gemma's audio has two separate unfixable upstream blockers (Issues #4 above). `whisper.cpp` (same ggml/llama.cpp ecosystem) could bolt speech-in/speech-out onto the existing chat setup independently of Gemma entirely — supersedes the old "wait for upstream to fix Gemma audio" plan below.
6. **Fine-tune something actually personal**: everything so far is off-the-shelf (Unsloth quants, community abliterations). A LoRA fine-tune on personal data/writing style, on a small model, is feasible on this hardware and would be a different kind of "full potential" than swapping pre-made models.
7. **Turn the monitoring habit into real infrastructure**: `gpu-fence-watch.service` is currently just an alert script. Leveling up to auto-restart-on-crash, plus a phone push notification over Tailscale when a server dies, closes the gap between "I noticed it crashed" and "it healed itself."
8. **A repeatable model-evaluation pipeline**: today's rigor (UGI Leaderboard cross-check, GitHub issue verification, llama.cpp source checks before trusting a model) was all manual and ad-hoc. Turning it into a standing script/checklist run against every new model candidate would make "should I adopt this" a five-minute repeatable process instead of a fresh investigation each time.

Smaller, still-open items not folded into a chapter above:
- **Qwen3.5-4B**: revisit once `ggml-org/llama.cpp#21831` is fixed upstream — confirmed still open and broader than originally scoped as of 2026-07-30 (also affects Qwen 3.5-35B, Gemma-4-26B). May become viable again in place of Qwen3-4B-Instruct-2507.
- **`--mlock` reconsideration**: if ever moving to a machine with more RAM headroom, consider raising systemd's `LimitMEMLOCK` for `user@.service` and re-enabling mlock.
- **Automation**: a small supervisor/menu script to switch models without manually remembering the kill+relaunch sequence — narrower in scope than chapter 7's auto-healing, more about day-to-day ergonomics.
