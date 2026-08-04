# Compatibility Matrix

What this setup has actually been run against, not a general support statement. Sourced from [SETUP.md](../SETUP.md), [JOURNAL.md](../JOURNAL.md), and [hardware.md](hardware.md). Per [AGENTS.md](../AGENTS.md#documentation-standards), unmeasured values are left as `TODO` rather than guessed — if you run this setup on a version not listed here and confirm it works (or doesn't), see [CONTRIBUTING.md](../CONTRIBUTING.md) for how to report it.

| Component | Tested version | Notes |
|---|---|---|
| Fedora | 44 | KDE Plasma spin, current daily driver. See [hardware.md](hardware.md). |
| Windows | TODO — edition/build not recorded | Origin OS, preserved on a separate NTFS partition. See [hardware.md](hardware.md#windows-vs-fedora). |
| Podman | TODO — Fedora 44's default repo version, exact version not recorded | Rootless, no daemon. See [architecture.md](architecture.md#design-decisions-worth-calling-out). |
| Open WebUI | `ghcr.io/open-webui/open-webui:main` (floating tag, not pinned) | Deployed via [`start-open-webui.sh`](../start-open-webui.sh). A `:main` tag means "whatever's current" — pin to a release tag if reproducibility matters more than staying current. |
| Open Terminal | `ghcr.io/open-webui/open-terminal:slim` (floating tag, not pinned) | Deployed via [`start-open-terminal.sh`](../start-open-terminal.sh). Same floating-tag caveat as above. |
| `llama.cpp` (Fedora) | Built from source, Vulkan backend (`GGML_VULKAN=ON`) | Commit/tag in use not currently recorded — see [hardware.md](hardware.md#why-models-and-llamacpp-arent-in-git). |
| `llama.cpp` (Windows) | Precompiled Vulkan release, upgraded b9305 → b10107 | See [benchmarks.md](benchmarks.md#build-upgrade-impact-windows-b9305--b10107) for the re-verification after upgrade. |
| Vulkan | TODO — SDK/driver version not recorded | Backend confirmed working via GPU-resident inference (low RSS) on both OSes; see [JOURNAL.md](../JOURNAL.md). |
| Intel graphics driver | TODO — Mesa/`i915` version not recorded | Relevant to the fence-timeout bug in [troubleshooting.md](troubleshooting.md#i915-igpu-fence-timeout--gpu-hangs); worth recording if that bug is ever revisited upstream. |
| Tailscale | 1.98.8 (Fedora, installed from Fedora's own repos) | See [SETUP.md](../SETUP.md) for the firewalld zone configuration needed alongside it. |
| OpenVINO / `openvino-genai` | 2026.2.1-21919-ede283a88e3 | Evaluated secondary backend, not daily driver. See [SETUP.md](../SETUP.md#alternative-backend-openvino--ovms-evaluated-not-in-daily-use). |
| `intel-compute-runtime` / `intel-opencl` / `intel-level-zero` (Fedora dnf packages) | 26.22.38646.6-4.fc44 | Separate GPU driver stack from the Mesa Vulkan driver above — needed for OpenVINO's GPU plugin to see the iGPU at all (`Core().available_devices` was `['CPU']` only beforehand). See [hardware.md](hardware.md). |
| `docker.io/openvino/model_server` | `latest-gpu` tag (floating, image built 2026-06-17) — used for Qwen3-8B; `weekly` tag (floating, tracks `main`) — used for Qwen3.5-9B, whose GPU kernels needed OpenVINO nightly wheels elsewhere in this stack (see [openvino#36151](https://github.com/openvinotoolkit/openvino/issues/36151)); `weekly` confirmed working (reaches `AVAILABLE`, no `CL_OUT_OF_RESOURCES`), `latest-gpu` not separately tested against this model | OVMS container image. Same floating-tag caveat as Open WebUI/Open Terminal above. No tag literally called "nightly" exists on Docker Hub for this image; `weekly` is the closest equivalent. |

## Why this exists

Every fix and workaround in [troubleshooting.md](troubleshooting.md) is tied to a specific version combination, even where that version isn't pinned down precisely yet — a driver update, a Vulkan SDK bump, or an Open WebUI release could change or resolve any of them. This table exists so a future reader (including future-self) can tell whether a fix is still expected to apply, and so gaps (the `TODO`s above) are visible instead of silently assumed.

## Related documents

- [hardware.md](hardware.md) — the machine these versions run on
- [troubleshooting.md](troubleshooting.md) — issues tied to specific versions above
- [SETUP.md](../SETUP.md) — full flag-by-flag configuration
- [AGENTS.md](../AGENTS.md#documentation-standards) — why unmeasured values stay `TODO` instead of guessed
