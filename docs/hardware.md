# Hardware & OS

Static reference for the machine this setup runs on and how the two OS installs relate. For the directory layout and per-model launch flags, see [SETUP.md](../SETUP.md). For narrative history of how this hardware's limits were discovered, see [lessons-learned.md](lessons-learned.md).

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
