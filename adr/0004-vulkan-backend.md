# ADR 0004: Vulkan as the llama.cpp inference backend

**Status**: Accepted (implemented) — `llama.cpp` built from source with `GGML_VULKAN=ON` on both OSes.
**Date**: Predates [JOURNAL.md](../JOURNAL.md) — in place from the original Windows setup, carried over to the Fedora port.

## Context

There is no discrete GPU anywhere in this setup — the only GPU-class compute device available is the Intel Iris Xe integrated GPU (see [docs/hardware.md](../docs/hardware.md)). Running models at usable speed on a 16GB machine requires real GPU offload rather than falling back to CPU-only inference.

## Decision

Build `llama.cpp` with the Vulkan backend (`GGML_VULKAN=ON`) and run every model with GPU layer offload (`-ngl`, left unset/`auto` on this build, which offloads every layer that fits).

## Alternatives considered

- **CPU-only inference.** Not a real contender given the goal — the entire premise of this setup is usable local inference on integrated graphics; CPU-only would abandon that goal rather than serve it.
- **Intel's own SYCL/oneAPI backend.** No evaluation of this is documented anywhere in [JOURNAL.md](../JOURNAL.md) or [SETUP.md](../SETUP.md) — it's not recorded as having been tried, compared, or explicitly rejected. Noted here for completeness rather than claimed as a considered-and-rejected alternative; genuinely unknown whether it would perform differently on this hardware.

## Consequences

- **Positive**: full-layer GPU offload achieved and verified — Gemma reports 43/43 layers, Qwen3's `-ngl auto` offloads everything that fits, confirmed indirectly via low process RSS (~500MB) after real generation, meaning the model lives in Vulkan/GPU memory rather than process RAM.
- **Positive**: sustained ~9–9.8 tok/s generation across every model tried, on both Windows and Fedora, with near-identical performance between the two OSes once ported (see [docs/benchmarks.md](../docs/benchmarks.md)).
- **Negative**: surfaced a real, non-trivial class of bug — `i915`/Vulkan fence timeouts on the integrated GPU, escalating to device-lost errors, crashes, and once a full OS freeze. Root-caused via a matching issue on an AMD APU (not something specific to this exact chip), mitigated with `GGML_VK_MAX_NODES_PER_SUBMIT=1` as an unconfirmed trial fix, and required three local, unsubmitted exception-handling patches to `llama.cpp`'s server code to stop crashes outright (see [docs/troubleshooting.md](../docs/troubleshooting.md)).
- **Negative**: Fedora's build has its own dependency trap — needs the package named exactly `glslc`, not the similarly-named `glslangValidator`, plus `spirv-headers-devel`/`spirv-tools-devel`.

## Related

[docs/hardware.md](../docs/hardware.md) · [docs/troubleshooting.md](../docs/troubleshooting.md#i915-igpu-fence-timeout--gpu-hangs) · [docs/lessons-learned.md](../docs/lessons-learned.md#vulkan) · [docs/benchmarks.md](../docs/benchmarks.md)
