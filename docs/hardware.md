# Hardware & OS

Static reference for the machine this setup runs on and how the two OS installs relate. For the directory layout and per-model launch flags, see [SETUP.md](../SETUP.md). For narrative history of how this hardware's limits were discovered, see [lessons-learned.md](lessons-learned.md). Related: [architecture.md](architecture.md), [benchmarks.md](benchmarks.md), [models.md](models.md).

## At a glance

Read this table first — it tells you whether the rest of this repository applies to your hardware.

| Component | Value |
|-----------|-------|
| CPU | Intel Core i5-12500H (4P+8E cores, 16 threads) |
| GPU | Intel Iris Xe iGPU (**no discrete GPU**) |
| RAM | 16GB (~7.4–9.8GB Vulkan-visible budget) |
| OS | Fedora 44 (daily driver), Windows (origin, preserved) |
| Inference backend | Vulkan, via `llama.cpp` built from source |
| Primary models | Qwen3-4B-Instruct-2507, Qwen3-4B-Instruct-2507-heretic-av2, Gemma 4 E4B-it |

If your machine has a discrete GPU, most of the CUDA/ROCm-specific tuning ecosystem elsewhere online will serve you better than this repo — everything documented here is specifically about getting good performance **without** one. See [Who is this repository for?](../README.md#who-is-this-repository-for) in the README.

## Machine

| | |
|---|---|
| **CPU** | Intel i5-12500H (4P+8E cores, 16 threads) |
| **GPU** | Intel Iris Xe iGPU — no discrete card, Vulkan-accelerated |
| **RAM** | 16GB system (~7.4–9.8GB Vulkan-visible budget) |
| **Daily driver** | Fedora 44 (`~/LocalAI`) |
| **Origin OS** | Windows (`C:\LocalAI`, preserved for reference) |
| **Inference engine** | [`llama.cpp`](../llama.cpp), Vulkan backend, built from source |

There is no discrete GPU anywhere in this setup. Every model runs on the integrated GPU via Vulkan, sharing system RAM as VRAM. That constraint shapes almost every decision documented here — quantization choices, context sizes, `--mlock` vs mmap, and the iGPU fence-timeout issue in [troubleshooting.md](troubleshooting.md).

## Windows vs Fedora

Windows (`C:\LocalAI`) was the original setup; Fedora (`~/LocalAI`) is the current daily driver, ported from it partly to reclaim RAM Windows was holding onto. The Windows install is preserved on a ~340GB NTFS partition (`/dev/nvme0n1p3`, not mounted by default — mount read-only at `/mnt/winc` to inspect it) rather than wiped, since some tooling (the MCP server stack, the dual-server coding setup) hasn't been ported to Fedora yet.

Full directory layout for both OSes, and what's ported vs. Fedora-only vs. Windows-only, is in [SETUP.md](../SETUP.md#directory-layout).

## Why `models/` and `llama.cpp/` aren't in Git

Both are listed in `.gitignore` and intentionally excluded from this repository:

- **`models/`** — multi-gigabyte GGUF weight files. Committing them would make the repo unclonable in practice and duplicates what's already hosted (and versioned) on Hugging Face. [SETUP.md](../SETUP.md#directory-layout) lists exactly which file each script expects and where it comes from.
- **`llama.cpp/`** — an upstream checkout built from source. Vendoring it here would fork a fast-moving upstream project inside this repo for no benefit; it's tracked instead by which build/commit is in use, noted in [SETUP.md](../SETUP.md) and [JOURNAL.md](../JOURNAL.md) where relevant.

Both directories exist locally once the setup steps in [SETUP.md](../SETUP.md) are followed, but a fresh clone of this repo will not contain them.

## Related documents

- [SETUP.md](../SETUP.md) — directory layout and per-model flags
- [architecture.md](architecture.md) — how the pieces run on this hardware
- [benchmarks.md](benchmarks.md) — what this hardware actually achieves
- [models.md](models.md) — models tested on this hardware, compared
- [lessons-learned.md](lessons-learned.md) — practical findings this hardware's constraints produced
- [compatibility.md](compatibility.md) — exact tested OS/driver versions
- [../adr/0001-fedora-over-windows.md](../adr/0001-fedora-over-windows.md) · [../adr/0004-vulkan-backend.md](../adr/0004-vulkan-backend.md) — the stable decisions this hardware drove
