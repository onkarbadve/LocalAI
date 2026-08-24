#!/usr/bin/env bash
# power-profile.sh — apply a package power-limit (RAPL PL1/PL2) profile for the
# Intel i5-12500H iGPU inference box. Findings/benchmarks: docs/kernel-and-driver-tuning.md §F.
#
# These are all transient sysfs writes (powercap, drm, cpufreq) — none of them
# survive a reboot on their own. "sweet" is applied automatically at boot via
# the localai-power-profile.service unit in this repo; run this script manually
# to switch profiles mid-session (e.g. "max" before a heavy build or long-context
# prefill, then back to "sweet" after).
#
# Usage: sudo ./power-profile.sh {sweet|max|stock}

set -euo pipefail

RAPL_PL1_MSR=/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw
RAPL_PL1_MMIO=/sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw
RAPL_PL2_MSR=/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw
RAPL_PL2_MMIO=/sys/class/powercap/intel-rapl-mmio:0/constraint_1_power_limit_uw
RAPL_TAU_MSR=/sys/class/powercap/intel-rapl:0/constraint_0_time_window_us
RAPL_TAU_MMIO=/sys/class/powercap/intel-rapl-mmio:0/constraint_0_time_window_us
RAPL_ENERGY=/sys/class/powercap/intel-rapl:0/energy_uj
GPU_MIN_FREQ=/sys/class/drm/card1/device/tile0/gt0/freq0/min_freq

case "${1:-}" in
  sweet)   PL1=48000000; PL2=90000000; TAU=56000000; GPU_MIN=1300; EPP=performance ;;
  max)     PL1=55000000; PL2=95000000; TAU=56000000; GPU_MIN=1300; EPP=performance ;;
  stock)   PL1=40000000; PL2=80000000; TAU=32000000; GPU_MIN=300;  EPP=default ;;
  *)
    echo "Usage: sudo $0 {sweet|max|stock}" >&2
    echo "  sweet  - 48W PL1 / 90W PL2 / 56s tau, GPU pinned 1300MHz (daily/agent default)" >&2
    echo "  max    - 55W PL1 / 95W PL2 / 56s tau, GPU pinned 1300MHz (heavy builds/long prefill)" >&2
    echo "  stock  - 40W PL1 / 80W PL2 / 32s tau, GPU floor back to 300MHz (revert to factory)" >&2
    exit 1
    ;;
esac

echo "$PL1" | tee "$RAPL_PL1_MSR" "$RAPL_PL1_MMIO" >/dev/null
echo "$PL2" | tee "$RAPL_PL2_MSR" "$RAPL_PL2_MMIO" >/dev/null
echo "$TAU" | tee "$RAPL_TAU_MSR" "$RAPL_TAU_MMIO" >/dev/null
echo "$GPU_MIN" | tee "$GPU_MIN_FREQ" >/dev/null
for epp_path in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
  echo "$EPP" | tee "$epp_path" >/dev/null
done
chmod 444 "$RAPL_ENERGY"

echo "Applied '$1' power profile (PL1=${PL1}uW PL2=${PL2}uW tau=${TAU}us GPU_min=${GPU_MIN}MHz EPP=${EPP})."
