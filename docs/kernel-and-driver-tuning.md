# Kernel & Driver Tuning Reference

Technical reference for Linux kernel parameters, driver subsystem configurations, and the `i915` vs `xe` driver evaluation on the Intel Core i5-12500H (Alder Lake-P GT2 Iris Xe) unified memory architecture (UMA) setup.

Related: [hardware.md](hardware.md), [compatibility.md](compatibility.md), [troubleshooting.md](troubleshooting.md), [SETUP.md](../SETUP.md).

---

## 1. Hardware Driver Audit & Baseline

Audit conducted on Fedora 44 (Kernel 7.1.9, Mesa 26.1.7, Compute Runtime 26.22):

| Subsystem | Hardware / Device ID | In-Use Driver Stack | Status & Firmware Details |
|---|---|---|---|
| **iGPU (Graphics/Vulkan)** | Intel Alder Lake-P GT2 `[8086:46a6]` | `i915` KMD + Mesa 26.1.7 ANV (Vulkan 1.4) | **Optimal**. GuC submission (`v70.49.4`), HuC authenticated (`v7.9.3`), SLPC (Single Loop Power Control), and Render C-states active. |
| **GPGPU Compute** | Intel Iris Xe Graphics | `intel-compute-runtime` 26.22 + `intel-opencl` + `intel-level-zero` | **Operational**. Platform 0 Device 0 verified active via `clinfo`. |
| **CPU** | Intel Core i5-12500H (4P + 8E, 16T) | `intel_pstate` (HWP active) | Governed by `tuned` under `throughput-performance` profile. Intel Thread Director / HFI active. |
| **NVMe Storage** | Micron 2450 Gen4 NVMe (DRAM-less) | Intel VMD `vmd` $\rightarrow$ `nvme` | **Optimal**. Host Memory Buffer (HMB) allocated (64 MiB), I/O scheduler `[none]` (multi-queue NVMe bypass). Filesystem: Btrfs with async discard and zstd:1. |
| **WiFi / Bluetooth** | Intel Killer AX1675i 160MHz | `iwlwifi` / `btintel` | Operational, no firmware errors. |
| **Audio** | Alder Lake PCH-P HD Audio | `sof-audio-pci-intel-tgl` | Sound Open Firmware initialized with PipeWire/WirePlumber. |
| **Camera ISP** | Alder Lake Imaging Signal Processor | `intel-ipu6` | Kernel module loaded. |

---

## 2. Exploring the `xe` Kernel Driver vs `i915`

The `xe` driver (`drivers/gpu/drm/xe/`) is Intel's clean-sheet DRM graphics driver designed for Gen12 and newer architectures. On Fedora 44 with Kernel 7.1, Mesa 26.1, and Compute Runtime 26.22, both the kernel and userspace fully support switching between `i915` and `xe`.

### Architecture Comparison

```
+-------------------------------------------------------------------------+
|                              USERSPACE                                  |
|   Mesa ANV (Vulkan 1.4)           Intel Compute Runtime (Level Zero)    |
|   `anv_gem_xe` (VM_BIND)          `libze_intel_gpu` (DRM_XE IOCTLs)     |
+------------------------------------+------------------------------------+
                                     |
                                     v
+------------------------------------+------------------------------------+
|                         KERNEL DRIVER (KMD)                             |
|                                                                         |
|      i915 (Legacy Gen2-Gen12)      |         xe (Modern Gen12-Xe2)      |
|  - Custom priority scheduler       |  - Shared upstream `drm_sched`     |
|  - Execbuf-coupled memory pinning  |  - Decoupled `VM_BIND`             |
|  - Monolithic ring reset on hang   |  - Fine-grained VM context reset   |
|  - 20+ years of legacy shims       |  - Clean-sheet codebase            |
+------------------------------------+------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                  Intel Iris Xe Hardware (GuC / HuC)                     |
+-------------------------------------------------------------------------+
```

| Dimension | `i915` (Current Default) | `xe` (Candidate) | Impact on Local AI Serving |
|---|---|---|---|
| **Memory Model** | Memory objects bound/pinned inside `execbuf` submissions. | **`VM_BIND`**: Address space mapping managed asynchronously and decoupled from job dispatch. | Closer to Vulkan & Level Zero design. Eliminates kernel mapping overhead during dynamic KV-cache adjustments. |
| **Scheduler** | Custom in-tree `i915` request scheduler. | Standard Linux **`drm_sched`**. | Better preemption and fairer queue interleaving when Open WebUI, desktop compositing, and llama.cpp run simultaneously. |
| **Hang Recovery** | Heartbeat timer pulses `rcs0`; engine reset on false timeout (`DeviceLostError`). | Context/VM wedging and fine-grained engine resets. | More resilient under heavy prompt batching. |
| **Userspace Support** | `anv_gem_i915.c` in Mesa. | `anv_gem_xe.c` in Mesa + native `DRM_XE` in Level Zero. | Both drivers are compiled in and detected automatically by Mesa and Compute Runtime. |
| **Display Engine** | Native mature display stack. | Uses shared `intel_display` code backported from `i915`. | Generally identical on Alder Lake; occasionally minor laptop eDP power-saving (PSR) differences. |

### Why Alder Lake Defaults to `i915`
In Linux 7.1, Intel routes drivers based on GPU generation:
- **Gen12 (Tiger Lake, Alder Lake `46a6`, Raptor Lake, DG1, DG2)**: Defaults to `i915`.
- **Xe-LPG / Xe2 (Meteor Lake, Lunar Lake, Battlemage)**: Defaults to `xe`.

Intel keeps Alder Lake on `i915` by default because `i915` has had over 4 years of real-world laptop validation across thousands of OEM BIOS implementations. `xe` support for Alder Lake is functional, but opt-in.

### Testing & Switching Procedure

PCI Device ID for this GPU is `46a6`.

#### Option A: Safe One-Time Boot Test (Zero Risk)
1. Reboot the laptop.
2. At the GRUB boot menu, select Fedora (kernel 7.1.9) and press `e` to edit.
3. Append `i915.force_probe=!46a6 xe.force_probe=46a6` to the end of the line starting with `linux ($root)...`.
4. Press `Ctrl+X` or `F10` to boot.
5. *If any issue occurs, a simple reboot returns to default `i915`.*

#### Option B: Persistent Switch via `grubby`
```bash
sudo grubby --update-kernel=ALL --args="i915.force_probe=!46a6 xe.force_probe=46a6"
sudo reboot
```

#### Verification Checklist After Boot
```bash
# 1. Verify kernel driver in use is 'xe'
lspci -nnk -d 8086:46a6

# 2. Check xe initialization and GuC firmware in dmesg
journalctl -k -b | grep -iE "xe|guc"

# 3. Check Mesa Vulkan ANV status
vulkaninfo --summary

# 4. Check Intel Compute Runtime (Level-Zero & OpenCL)
clinfo -l
```

#### Rollback to `i915`
```bash
sudo grubby --update-kernel=ALL --remove-args="i915.force_probe=!46a6 xe.force_probe=46a6"
sudo reboot
```

---

## 3. Recommended Kernel & System Tweaks

The following tweaks target the specific constraints of this system: **16GB shared RAM (UMA)**, **Intel 12500H hybrid CPU**, **iGPU compute workloads (llama.cpp/Vulkan/OVMS)**, and **zstd ZRAM**.

### A. iGPU Render Watchdog / Heartbeat (Preventing `DeviceLostError` / Fence Timeouts)
* **Why**: Heavy prompt processing batches on the Iris Xe can occupy the GPU for multiple seconds. The `i915` driver defaults to a 2,500 ms heartbeat interval and a 7,500 ms preemption timeout on the `rcs0` (Render/Compute) engine. If a compute shader pass takes longer than this window to yield, the kernel watchdog flags a false-positive GPU hang and resets the engine.
* **Tweak**: Increase `heartbeat_interval_ms` to 10,000 ms and `preempt_timeout_ms` to 15,000 ms via a `udev` rule.

```bash
sudo tee /etc/udev/rules.d/99-i915-timeouts.rules << 'EOF'
# Extend i915 compute engine timeouts to prevent GPU reset during heavy LLM prompt evaluation
ACTION=="add", SUBSYSTEM=="drm", KERNEL=="card*", ATTR{engine/rcs0/heartbeat_interval_ms}="10000", ATTR{engine/rcs0/preempt_timeout_ms}="15000"
EOF

sudo udevadm control --reload-rules && sudo udevadm trigger
```

### B. Virtual Memory & UMA Allocation Buffer (`sysctl`)
* **Why**:
  1. `vm.watermark_scale_factor`: Default is `10` (0.1% $\approx$ 16MB). Raising this to `100` (1% $\approx$ 160MB) forces `kswapd` to wake up earlier and asynchronously compress/swap cold anonymous pages to ZRAM before a large Vulkan GEM or KV-cache allocation triggers direct-reclaim synchronous stalls.
  2. `vm.compaction_proactiveness`: Increasing from `20` to `50` prompts `kcompactd` to defragment memory in the background, reducing page fault latency during large model allocations.
  3. Consolidate `vm.vfs_cache_pressure = 50`, `vm.swappiness = 150`, and `vm.page-cluster = 0` in a single file to eliminate rule clobbering (where `99-zram.conf` previously overrode `99-localai-tuning.conf`).

```bash
sudo rm -f /etc/sysctl.d/99-zram.conf

sudo tee /etc/sysctl.d/99-localai-tuning.conf << 'EOF'
# Memory & VFS tuning for 16GB UMA / Vulkan LLM serving with ZRAM

# Prioritize ZRAM swapping over dropping filesystem cache
vm.swappiness = 150
# Single 4KB page I/O for ZRAM (disables multi-page clustering overhead)
vm.page-cluster = 0
# Keep dentries and inodes hot for mmap'd GGUF models and prompt caches
vm.vfs_cache_pressure = 50

# Smooth writeback flushing to prevent direct-reclaim stalls during generation
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10

# Increase kswapd headroom to 1% of RAM (~160MB) to absorb sudden Vulkan allocations
vm.watermark_scale_factor = 100
# Proactive background memory compaction for contiguous allocations
vm.compaction_proactiveness = 50
# Support deep mmap regions for containers / multiple models
vm.max_map_count = 1048576
EOF

sudo sysctl --system
```

### C. Transparent Hugepages for Shared Memory (`shmem_enabled`)
* **Why**: `transparent_hugepage/enabled` is set to `madvise` (preventing memory bloat in small tools while allowing jemalloc/ggml to request hugepages). However, Vulkan GEM objects and container IPC map memory via `shmem`/tmpfs, where THP defaults to `never`. Setting `shmem_enabled` to `advise` allows hugepage backing for shared memory allocations that explicitly request it.

```bash
sudo tee /etc/tmpfiles.d/thp-shmem.conf << 'EOF'
w /sys/kernel/mm/transparent_hugepage/shmem_enabled - - - - advise
w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
EOF

sudo systemd-tmpfiles --create /etc/tmpfiles.d/thp-shmem.conf
```

### D. Intel P-State HWP Dynamic Boost
* **Why**: On 12th Gen hybrid CPUs, `intel_pstate/hwp_dynamic_boost=1` instructs the hardware P-state governor to momentarily boost CPU frequency when a thread unblocks from an I/O wait, lock wait, or IPC channel. This improves responsiveness when transitioning between SSE stream chunks in Open WebUI / llama-server.

```bash
sudo tee /etc/tmpfiles.d/intel-pstate-boost.conf << 'EOF'
w /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost - - - - 1
EOF

sudo systemd-tmpfiles --create /etc/tmpfiles.d/intel-pstate-boost.conf
```

### E. Network Congestion Control (BBR for Remote Tailscale Streaming)
* **Why**: TCP default is `cubic`. Switching to Google's `BBR` with `fq_codel` queuing minimizes bufferbloat and packet queue buildup when streaming tokens over Tailscale to mobile devices.

```bash
sudo tee /etc/modules-load.d/bbr.conf << 'EOF'
tcp_bbr
EOF

sudo tee /etc/sysctl.d/90-bbr.conf << 'EOF'
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = bbr
EOF

sudo modprobe tcp_bbr && sudo sysctl --system
```

### F. Package Power Limit Tuning (RAPL PL1/PL2)
* **Why**: The i5-12500H's stock 40W PL1 cap throttles 48.1% of the time under normal desktop + inference load (measured via `bench_and_monitor.py`, 2026-08-24), capping the GPU to ~1233MHz average instead of its pinned 1300MHz. Steady-state token generation itself is memory-bus bound and doesn't change with more power (~10.4 tok/s at 40W, 48W, or 55W alike) — the actual payoff is shorter model-load/prefill time and far less PL1 throttling. Full 3-way comparison: [benchmarks.md](benchmarks.md#package-power-limit-rapl-pl1pl2-profile-sweep).
* **Profile chosen**: 48W PL1 / 90W PL2 / 56s tau ("Sweet Spot") as the persistent daily/agent default — it removes most of the throttling (38.5% vs 48.1%) with no thermal cost (96°C peak either way, 0% thermal throttling). 55W PL1 / 95W PL2 ("Max Practical") is kept as an opt-in for heavy builds or very long prefill, since it's within noise of 48W on every metric except a ~9ms edge in one load-time run.
* **Mechanism**: these are transient `powercap` (RAPL), `drm` (GPU min freq), and `cpufreq` (EPP) sysfs writes — none of them survive a reboot on their own. `power-profile.sh` (repo root) applies any of the three profiles on demand; `localai-power-profile.service` (repo root, install below) reapplies the Sweet Spot profile automatically at every boot.

```bash
sudo cp /home/onkar/LocalAI/localai-power-profile.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now localai-power-profile.service
```

Switch profiles mid-session without touching the boot default:

```bash
sudo /home/onkar/LocalAI/power-profile.sh max     # before a heavy build / long-context prefill
sudo /home/onkar/LocalAI/power-profile.sh sweet   # back to the daily default
sudo /home/onkar/LocalAI/power-profile.sh stock   # revert to factory 40W/80W/300MHz floor
```
