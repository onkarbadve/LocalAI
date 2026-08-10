# Troubleshooting

Structured writeups of real issues hit while building and running this setup, converted from the narrative entries in [JOURNAL.md](../JOURNAL.md) (which has the full blow-by-blow, including dead ends). See [hardware.md](hardware.md) for the machine these were found on and [SETUP.md](../SETUP.md) for current flags.

---

## Vulkan build fails to configure on Fedora

**Problem**: `cmake` fails to configure `llama.cpp`'s Vulkan backend.

**Cause**: the build needs a package named exactly `glslc` — not `glslangValidator`, which looks like the same shader compiler but isn't. Two further CMake dependencies are also required: `spirv-headers-devel` and `spirv-tools-devel`.

**Solution**: install the correct package names before configuring:

```bash
sudo dnf install -y glslc spirv-headers-devel spirv-tools-devel
```

**Verification**: `cmake` configures cleanly and `cmake --build .` produces `llama-server` with Vulkan support (`ggml_vulkan` init messages on startup, GPU listed).

---

## `llama-server` never finishes generating (Qwen3, runaway generation)

**Problem**: a plain message like "hi" through Open WebUI never returns a response; `/slots` shows the token count climbing past 2000+ and never stopping.

**Cause**: `--reasoning` defaults to `auto`, detected from the chat template. Qwen3-4B-Instruct-2507's template has a reasoning/`<think>` branch shared with the thinking variant of the model family, even though this specific Instruct checkpoint never emits `<think>` tags. Auto-detection flags it as a reasoning model and the parser waits indefinitely for a closing think tag that never comes.

**Solution**: add `--reasoning off` to the launch flags. This is Qwen3-specific — verified it does *not* apply to Gemma before reusing it (see [SETUP.md](../SETUP.md#gemma-4-e4b-it--vision-chat-start-server-gemma4-e4bbat-windows-only) for why the flag has different implications there).

**Verification**: replicate the client's exact request shape (`stream:true`, `reasoning_format:"deepseek"`) directly against the server — response completes with `finish_reason:"stop"` in a few seconds instead of running away.

---

## `llama-server` hangs after generation finishes (`is_processing` stuck true)

**Problem**: `/slots` shows `has_next_token:false` (generation is actually done) but `is_processing:true` stays stuck indefinitely — the client never gets a response.

**Cause**: hung inside `llama-server`'s `chat_format:"peg-native"` response formatter / tool-call parser, not in generation itself. Reproducible with a tools payload present (Open WebUI's Builtin Tools, or a terminal-tool schema) even after `--reasoning off` is set.

**Solution**: added `--skip-chat-parsing` initially (dumps everything into `message.content` unparsed) — but this silently disables structured `tool_calls` extraction, breaking agent mode. Removed again once direct testing showed `--reasoning off` alone (no `--skip-chat-parsing`) doesn't hang when tools are actually present in the request, at both small and large (14-tool) declaration sizes. Current fix: `--reasoning off` only. If it recurs, kill (`SIGKILL` if `SIGTERM` doesn't respond) and restart via the relevant `start-*.sh` script.

**Verification**: replay the client's real request shape (tools block included, `stream:true`, `reasoning_format:"deepseek"`) — completes cleanly with correct `tool_calls` on trigger messages and correct abstention otherwise.

---

## Silent generation corruption — `/health` OK but every response is empty

**Problem**: `llama-server` reports `/health: ok` and returns HTTP 200, but every completion comes back empty (`predicted_n: 1`, immediate stop token, no error). No dmesg signature, no crash, no log line.

**Cause**: GPU/Vulkan compute state (or the KV cache derived from it) left corrupted by an earlier fence-timeout/device-lost episode, without the driver ever declaring a hang and without Vulkan throwing a catchable error this time. Invisible from the outside — the server considers itself healthy.

**Solution**: kill and restart the `llama-server` process. A clean restart fully resolves it (confirmed via direct `curl` test immediately before/after restart).

**Verification**: send a known-good prompt via `curl` directly (bypassing any frontend) — real token counts and correct content return after restart, versus `predicted_n: 1` / empty content before.

---

## `i915` iGPU fence-timeout / GPU hangs

**Problem**: intermittent `Fence expiration time out` in `dmesg`, escalating to `vk::Device::waitForFences: ErrorDeviceLost` in `llama-server`, sometimes crashing the process, once freezing the whole OS (uptime reset, hard power-off required).

**Cause**: identified via upstream research as a known class of bug on integrated GPUs — the Vulkan backend batches up to 100 compute-graph nodes into a single GPU submission (`GGML_VK_MAX_NODES_PER_SUBMIT`, default 100); on an iGPU this can take long enough to exceed the kernel driver's hang-detection timeout, triggering a false-positive "hang" and a driver-level reset. Matched against an identical failure chain on an AMD APU ([ggml-org/llama.cpp#21724](https://github.com/ggml-org/llama.cpp/issues/21724)), where the same fix was validated.

**Solution**: `export GGML_VK_MAX_NODES_PER_SUBMIT=1` before launching `llama-server` (already set in all `start-*.sh` scripts). No measured performance penalty. Status: trial mitigation, not a confirmed upstream fix — fence timeouts have continued to be observed even with this set, so it's evaluated primarily as harm reduction alongside the crash-prevention patches below, not a guaranteed cure.

**Verification**: monitor `dmesg`/`journalctl -k` for `Fence expiration time out` over real usage; a `gpu-fence-watch` systemd user service tails the kernel log live and alerts (`notify-send`) on recurrence.

---

## `llama-server` crashes (not just hangs) on a device-lost error

**Problem**: after a fence-timeout/device-lost event, `llama-server` doesn't just fail the in-flight request — it crashes the entire process (`SIGABRT`, coredump), taking down service until someone notices and restarts it manually.

**Cause**: found via coredump analysis (`coredumpctl` + `gdb`) that three separate call sites in `llama.cpp`'s server code make unguarded Vulkan calls that throw once the device is already lost, uncaught, straight into `std::terminate`/`abort()`:
1. `server_slot::prompt_save()` (`tools/server/server-context.cpp`) — evicting a prompt to the on-disk cache when a new chat claims the slot.
2. `server_prompt_cache::load()` (`tools/server/server-task.cpp`) — restoring a cached prompt for the next request.
3. `ggml_vk_cleanup()` (`ggml/src/ggml-vulkan/ggml-vulkan.cpp`) — waiting on pending command buffers during shutdown/restart.

**Solution**: three local, unsubmitted patches wrapping each call site in the same `try { ... } catch (const std::exception & e) { SRV_ERR(...); return false; }` pattern already used elsewhere in the same files. Not filed upstream yet — needs more field verification and a search for existing issues/PRs first, per `llama.cpp/AGENTS.md`'s guidance on respecting maintainer time. **These patches do not survive a `git pull`/rebuild of `llama.cpp/` and must be reapplied by hand.**

**Verification**: validated live against a real device-lost event — server logged `prompt_save() failed: ...` / `failed to restore state: ...` and stayed alive, serving clean HTTP 500s instead of crashing, across dozens of consecutive requests during the outage window.

---

## Open WebUI: 33 "Builtin Tools" declarations bloat every request

**Problem**: a trivial message like "test" takes 170+ seconds and returns a non-answer ("I'm not sure what you'd like me to do").

**Cause**: when a model's Capabilities → Builtin Tools is enabled, Open WebUI auto-attaches ~33 native tool declarations (Knowledge Base, Memory, Notes, Tasks, Automations, Calendar, Chat History, Time/Date) to *every* request, regardless of whether the message needs any of them — roughly 5,100 tokens of pure overhead the model then has to reason over.

**Solution**: disable Builtin Tools per-model where agent-mode isn't needed (Admin → Models → Capabilities), or accept the overhead where it is needed — the cost is mostly paid once per conversation, not once per message, since the tool-declaration prefix gets cached (see [benchmarks.md](benchmarks.md#multi-turn-cache-reuse-qwen3-4b-instruct-2507-production)).

**Verification**: traced the literal outgoing prompt via `llama-server --log-prompts-dir` and the literal request JSON via a `window.fetch` hook — token count for an identical trivial message dropped from ~5,100+ to ~174 with Builtin Tools off.

---

## Open WebUI terminal Integration: "Terminal server not found"

**Problem**: asking a model to run a shell command via the Open Terminal integration fails with `Terminal unavailable: Terminal server 'http://localhost:8000' not found`, even though the personal Settings → Integrations page shows the terminal connected and the Files/Terminal side panels work fine.

**Cause**: Open WebUI has two independent terminal-connection stores. The personal "Direct" one (`user.settings.ui.terminalServers`) only powers the client-side Files/Terminal side panels and has no `id` field. Chat-based tool-calling resolves against a completely separate system-level list (`Config` key `terminal_server.connections`, admin-only, with real `id` fields) — and the Settings UI's personal connection dialog has no path to populate that list. The admin-level page exists in the backend (`/api/v1/configs/terminal_servers`) but isn't linked from the settings sidebar.

**Solution**: add the connection at the system level directly via the backend API (e.g. `fetch()` in the browser's own JS console, reusing the logged-in session) instead of only the personal Settings dialog. In the chat composer's terminal-attach dropdown, select the entry under **SYSTEM**, not **DIRECT**.

**Verification**: a real chat-triggered tool call (e.g. `run_command` → `get_process_status`) round-trips correctly and surfaces real output in the final answer.

---

## Open Terminal side panels fail over Tailscale (remote access)

**Problem**: the Files/Terminal side panels work fine locally but fail silently when accessed remotely (e.g. from a phone over Tailscale) — no error in the backend logs at all.

**Cause**: the personal "Direct" connection's side panels make *client-side* browser requests straight to their configured URL (`http://localhost:8000`). From a remote device, "localhost" resolves to that device, not the Fedora box — so the request never even reaches the server. Chat-based tool use (the System connection, which is backend-proxied) is unaffected.

**Solution**: given a deliberately conservative posture (an open shell API is a bigger attack surface than a chat UI), the personal Direct connection was deleted entirely rather than exposing Open Terminal on the Tailscale interface. Trade-off: no Files/Terminal side-panel view when remote, but Open Terminal stays fully `127.0.0.1`-only with zero new network exposure. Chat-based terminal tool use is unaffected either way.

**Verification**: confirmed chat-based `run_command` calls still work over Tailscale from a phone (mobile data, WiFi off) after the Direct connection was removed.

---

## Phone can't resolve `*.ts.net` MagicDNS name

**Problem**: Open WebUI is reachable from a phone via the raw Tailscale IP (`100.x.x.x:3000`) but not via the MagicDNS hostname (`fedora.<tailnet>.ts.net:3000`).

**Cause**: MagicDNS names only resolve through Tailscale's own internal resolver (`100.100.100.100`). With "Override local DNS" turned off on the phone (done separately to stop Tailscale fighting a NextDNS Private DNS profile), Tailscale no longer intercepts DNS queries on that device, so it has no path to resolve `*.ts.net` at all. This is a direct, expected consequence of that earlier DNS fix, not a new bug.

**Solution**: two options, neither applied automatically since it needs the user's own NextDNS resolver details: (a) use the raw tailnet IP on the phone and the MagicDNS name from desktop only, no further changes; (b) add the NextDNS resolver as a Global Nameserver in the Tailscale admin console, then re-enable DNS override on the phone, so Tailscale forwards `.ts.net` queries to itself and everything else to NextDNS.

**Verification**: `getent hosts fedora.<tailnet>.ts.net` resolves and `curl` returns HTTP 200 from a machine where DNS override is on.

---

## Port conflicts between models

**Problem**: two `llama-server` processes can't both bind the same port.

**Cause (Windows)**: `Start-Server.bat` and `Start-Server-Gemma4-E4B.bat` both bind `8080` by design — running two models on the same port simultaneously isn't supported.

**Cause (Fedora, historical)**: `start-qwen3.sh` and `start-gemma-e4b.sh` used to both bind `8080` the same way, before both were deleted 2026-08-05 (only uncensored models are kept on this box now). The two surviving Fedora scripts don't actually port-conflict with each other — `start-qwen3-uncensored.sh` (`8081`) and `start-gemma-uncensored.sh` (`8082`) are run mutually exclusively for a memory-budget reason, not a port one (see [SETUP.md](../SETUP.md#qwen3-4b-instruct-2507-heretic-av2--uncensored-bluntdirect-assistant-start-qwen3-uncensoredsh-fedora-only)) — starting both at once would OOM/thrash before it would ever hit a bind error.

**Solution**: stop the other server before starting a new one on the same port — `pkill -f llama-server` on Fedora, or close the other server window on Windows.

**Verification**: `ss -tlnp | grep <port>` shows only the intended process holding the port.

---

## Model won't offload to GPU / silently falls back to CPU

**Problem**: generation is much slower than expected, or memory usage pattern doesn't match GPU-resident behavior.

**Cause**: no `-ngl` set explicitly can, on some builds, not offload as expected — though on the build documented here, `-ngl` unset defaults to `auto` and offloads every layer that fits.

**Solution**: verify offload indirectly via process RSS after a real generation — a low RSS (~500MB) confirms the model lives in Vulkan/GPU memory, not process RAM, versus a multi-GB RSS if it fell back to CPU. If it did fall back, set `-ngl` explicitly to the model's full layer count.

**Verification**: `ps -o rss= -p <pid>` immediately after a completed generation.

---

## OVMS container: `Permission denied` reading mounted model files

**Problem**: OpenVINO Model Server (OVMS, Podman) fails to read the bind-mounted model directory even though the host path and permissions look correct.

**Cause**: SELinux, same root cause as MeTube's downloads mount — Fedora enforces by default, and a bind-mounted host directory keeps its `user_home_t` context, which a container process (`container_t`) is confined away from regardless of matching UID/GID.

**Solution**: add `:Z` to the volume mount to relabel the path to `container_file_t`, private to that container: `-v /path/to/model:/models/name:ro,Z`. Already applied in `start-ovms-qwen3-8b.sh`.

**Verification**: container logs reach `state changed to: AVAILABLE` instead of a permission error during model load.

---

## Podman rootless port forwarding: `curl http://localhost:PORT` resets, `127.0.0.1` works

**Problem**: `curl http://localhost:8084/...` against a Podman-forwarded port fails with "Connection reset by peer" — for GET requests to the model-list endpoint (worked) and separately for streaming POST requests to a generate endpoint (failed differently) — while `curl http://127.0.0.1:8084/...` succeeds immediately for both.

**Cause**: `localhost` resolves to `::1` (IPv6) first on this box, and Podman's rootless port-forwarding helper (`pasta`) only handles IPv4. Open WebUI hit the same bug from its own backend: its persisted connection URLs used `localhost`, so model-list calls (one code path) and generate calls (a separate code path) failed independently even after the first was traced and "fixed" — they're different request flows through the same underlying resolution bug, so fixing one doesn't fix the other.

**Solution**: use `127.0.0.1` instead of `localhost` for any client — script, curl, or another service's config — talking to a Podman-forwarded port on this box.

**Verification**: identical request succeeds against `127.0.0.1` and fails against `localhost` on the same running container.

---

## Open WebUI ignores `OPENAI_API_BASE_URLS` after first-ever container startup

**Problem**: recreating the Open WebUI container with an updated `OPENAI_API_BASE_URLS`/`OPENAI_API_KEYS` env var has zero effect on the connections shown in the model picker.

**Cause**: Open WebUI persists its connection list in its own sqlite DB (`config` table, `openai.api_base_urls`/`openai.api_keys`/`openai.api_configs` keys) once the data volume has prior state — the env var is only a seed for a brand-new volume, not a live override. Confirmed by reading `open_webui/routers/openai.py` and `open_webui/models/config.py` directly inside the container: `get_openai_runtime_config()` / `Config.get_many()` do a fresh DB read on every call, no caching layer, so the env var genuinely never gets consulted again after first init.

**Solution**: update the `config` table's `openai.*` rows directly (a raw DB `UPDATE`) rather than recreating the container. Takes effect immediately, no restart needed, since the backend reads fresh from the DB every call.

**Verification**: model-picker connections change immediately after the DB update, with no container restart.

---

## Compiling multiple OpenVINO device configs in one process without releasing the prior one → OOM

**Problem**: a Python script that compiles the same model for one device string, then compiles it again for a second device string in the same process (e.g. testing `HETERO:GPU,CPU` then `AUTO:GPU,CPU` back to back) gets killed with no application-level error.

**Cause**: each `core.compile_model()` call produces its own device-specific weight buffers; nothing releases the first compiled model just because a second compile starts. On this box's integrated GPU (UMA — no dedicated VRAM), "GPU memory" is system RAM allocated by the `i915` driver, so two ~4.8GB resident copies of an 8B-class model compete for the same 16GB pool the OS and everything else also needs. Confirmed via `dmesg`: `oom_reaper: reaped process <pid> (python)`.

**Solution**: explicitly `del` (or let go out of scope, with a checked `gc.collect()` if needed) a compiled model before compiling the same weights again for a different device, when working with models large relative to available RAM on a UMA box. Not needed on a discrete-GPU machine, where a CPU copy and a GPU copy would live in genuinely separate memory pools.

**Verification**: `free -h` / `dmesg` before and after — confirmed ~13GB free before, OOM during the second compile, ~13GB free again within seconds of the kill (no lasting damage).

---

## Qwen3.5-9B vision output is hallucinated on GPU, not just imprecise

**Problem**: asking Qwen3.5-9B (OpenVINO IR, GPU) to describe a real image returns well-formed, grammatical, confidently-wrong text with no crash or exception — e.g. describing this repo's own architecture diagram (a flowchart with named boxes and labeled arrows) as "a grid of identical-looking boxes... woven fabric... soil sample... filter media." Throughput/TTFT numbers look completely normal; only comparing the output against the actual image content reveals the bug.

**Cause**: FP16 precision issue in the vision-embeddings merger's graph execution on the GPU plugin specifically — confirmed by rerunning the identical model/image/prompt on CPU, which produced a near-perfect description (correct box names, correct port numbers, correct arrow labels). A structurally similar bug was already fixed upstream for Qwen2.5-VL ([openvino#33491](https://github.com/openvinotoolkit/openvino/pull/33491)/[#33880](https://github.com/openvinotoolkit/openvino/pull/33880), an FP16-overflow-into-NaN issue in that model's SwiGLU/RMSNorm merger block), but checking the exported IR directly (`grep -c` on `openvino_vision_embeddings_merger_model.xml`) found zero `Swish`/`RMS` ops — Qwen3.5's merger uses MVN + GELU, a structurally different graph the existing fix's pattern-matcher doesn't cover.

**Solution**: none available yet — filed upstream as [openvino#37223](https://github.com/openvinotoolkit/openvino/issues/37223) with full repro, side-by-side GPU/CPU output, and the IR-grep evidence; unowned as of 2026-08-04. The practical workaround used in this repo: route vision requests to CPU only, never GPU — see `start-ovms-qwen3.5-9b-vision.sh` in [SETUP.md](../SETUP.md#qwen35-9b-via-ovms-start-ovms-qwen35-9b-textsh--start-ovms-qwen35-9b-visionsh). A blanket `INFERENCE_PRECISION_HINT=ov.Type.f32` fix attempt OOM-killed the process during model compilation on this 15Gi UMA box before it could even be tested for correctness, so full-precision GPU inference isn't a viable workaround here either.

**Verification**: same model, same image, same prompt — GPU output bears no relation to the real image; CPU output is accurate. Confirms GPU-specific, not a preprocessing bug (image-loading code double-checked against the official `openvino.genai` sample).

---

## Related documents

- [SETUP.md](../SETUP.md) — current flags for every script
- [JOURNAL.md](../JOURNAL.md) — the full narrative account each entry above is condensed from
- [architecture.md](architecture.md) — how these components fit together
- [lessons-learned.md](lessons-learned.md) — the general takeaways drawn from these issues
- [compatibility.md](compatibility.md) — which versions each issue above was found on
