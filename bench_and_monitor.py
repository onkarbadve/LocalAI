#!/usr/bin/env python3
"""
bench_and_monitor.py — Synchronized hardware telemetry and LLM inference benchmark.

Captures high-resolution (250ms) time-series telemetry while executing an OpenVINO 
or llama.cpp benchmark:
- Package Power (Watts via RAPL energy_uj differential)
- CPU Package & Core Temperatures (°C)
- CPU P-core & E-core frequencies (MHz)
- GPU Actual & Requested Frequencies (MHz via xe driver)
- GPU Throttling Flags (PL1, PL2, Thermal, Prochot)
- Model Inference Throughput (tok/s, TTFT, TPOT)

Outputs summary statistics and saves full CSV logs for baseline comparison.
"""

import os
import sys
import time
import csv
import threading
from datetime import datetime

# Hardware telemetry sysfs paths
RAPL_ENERGY_PATH = "/sys/class/powercap/intel-rapl:0/energy_uj"
RAPL_PL1_MSR = "/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw"
RAPL_PL1_MMIO = "/sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw"
RAPL_PL2_MSR = "/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw"
RAPL_PL2_MMIO = "/sys/class/powercap/intel-rapl-mmio:0/constraint_1_power_limit_uw"
RAPL_TAU_MSR = "/sys/class/powercap/intel-rapl:0/constraint_0_time_window_us"
RAPL_TAU_MMIO = "/sys/class/powercap/intel-rapl-mmio:0/constraint_0_time_window_us"

CPU_EPP_PATH = "/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"
GPU_ACT_FREQ = "/sys/class/drm/card1/device/tile0/gt0/freq0/act_freq"
GPU_CUR_FREQ = "/sys/class/drm/card1/device/tile0/gt0/freq0/cur_freq"
GPU_MIN_FREQ = "/sys/class/drm/card1/device/tile0/gt0/freq0/min_freq"
GPU_MAX_FREQ = "/sys/class/drm/card1/device/tile0/gt0/freq0/max_freq"
GPU_RP0_FREQ = "/sys/class/drm/card1/device/tile0/gt0/freq0/rp0_freq"
GPU_THROTTLE_REASONS = "/sys/class/drm/card1/device/tile0/gt0/freq0/throttle/reasons"
GPU_THROTTLE_PL1 = "/sys/class/drm/card1/device/tile0/gt0/freq0/throttle/reason_pl1"
GPU_THROTTLE_PL2 = "/sys/class/drm/card1/device/tile0/gt0/freq0/throttle/reason_pl2"
GPU_THROTTLE_THERMAL = "/sys/class/drm/card1/device/tile0/gt0/freq0/throttle/reason_thermal"
GPU_THROTTLE_PROCHOT = "/sys/class/drm/card1/device/tile0/gt0/freq0/throttle/reason_prochot"


def read_sysfs(path, default="N/A"):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except Exception:
        return default


def read_int(path, default=0):
    val = read_sysfs(path, None)
    if val is None:
        return default
    try:
        return int(val)
    except ValueError:
        return default


def get_cpu_temp():
    # Search for x86_pkg_temp or highest thermal_zone temp
    max_t = 0
    for i in range(15):
        t_path = f"/sys/class/thermal/thermal_zone{i}/temp"
        type_path = f"/sys/class/thermal/thermal_zone{i}/type"
        if os.path.exists(t_path):
            z_type = read_sysfs(type_path, "")
            t_val = read_int(t_path, 0) // 1000
            if "pkg" in z_type.lower() or "tcpu" in z_type.lower():
                return t_val
            if t_val > max_t:
                max_t = t_val
    return max_t


def get_cpu_freqs():
    # CPUs 0-7: P-cores, 8-15: E-cores
    p_freqs = []
    e_freqs = []
    for c in range(16):
        path = f"/sys/devices/system/cpu/cpu{c}/cpufreq/scaling_cur_freq"
        khz = read_int(path, 0)
        mhz = khz // 1000
        if c < 8:
            p_freqs.append(mhz)
        else:
            e_freqs.append(mhz)
    max_p = max(p_freqs) if p_freqs else 0
    avg_p = sum(p_freqs) / len(p_freqs) if p_freqs else 0
    max_e = max(e_freqs) if e_freqs else 0
    avg_e = sum(e_freqs) / len(e_freqs) if e_freqs else 0
    return max_p, avg_p, max_e, avg_e


class HardwareTelemetryLogger:
    def __init__(self, sample_interval_s=0.25):
        self.sample_interval = sample_interval_s
        self.stop_event = threading.Event()
        self.records = []
        self.thread = None
        self.has_rapl_energy = os.access(RAPL_ENERGY_PATH, os.R_OK)

    def start(self):
        self.stop_event.clear()
        self.records = []
        self.thread = threading.Thread(target=self._sample_loop, daemon=True)
        self.thread.start()

    def stop(self):
        self.stop_event.set()
        if self.thread:
            self.thread.join()

    def _sample_loop(self):
        last_time = time.perf_counter()
        last_energy = read_int(RAPL_ENERGY_PATH, 0) if self.has_rapl_energy else 0

        while not self.stop_event.is_set():
            t_now = time.perf_counter()
            dt = t_now - last_time
            last_time = t_now

            power_w = 0.0
            if self.has_rapl_energy and dt > 0:
                e_now = read_int(RAPL_ENERGY_PATH, 0)
                d_energy = e_now - last_energy
                last_energy = e_now
                # handle wraparound if any
                if d_energy >= 0:
                    power_w = (d_energy / 1e6) / dt

            temp_c = get_cpu_temp()
            max_p, avg_p, max_e, avg_e = get_cpu_freqs()

            gpu_act = read_int(GPU_ACT_FREQ, 0)
            gpu_cur = read_int(GPU_CUR_FREQ, 0)
            gpu_th_reasons = read_sysfs(GPU_THROTTLE_REASONS, "none")
            th_pl1 = read_int(GPU_THROTTLE_PL1, 0)
            th_pl2 = read_int(GPU_THROTTLE_PL2, 0)
            th_thermal = read_int(GPU_THROTTLE_THERMAL, 0)
            th_prochot = read_int(GPU_THROTTLE_PROCHOT, 0)

            self.records.append({
                "timestamp": time.time(),
                "elapsed_s": round(t_now, 3),
                "power_w": round(power_w, 2),
                "cpu_temp_c": temp_c,
                "p_core_max_mhz": max_p,
                "p_core_avg_mhz": round(avg_p, 1),
                "e_core_max_mhz": max_e,
                "e_core_avg_mhz": round(avg_e, 1),
                "gpu_act_mhz": gpu_act,
                "gpu_cur_mhz": gpu_cur,
                "gpu_throttle_reasons": gpu_th_reasons,
                "th_pl1": th_pl1,
                "th_pl2": th_pl2,
                "th_thermal": th_thermal,
                "th_prochot": th_prochot,
            })

            time.sleep(self.sample_interval)

    def save_csv(self, filename):
        if not self.records:
            return
        fieldnames = list(self.records[0].keys())
        with open(filename, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(self.records)

    def summarize(self):
        if not self.records:
            return {}

        powers = [r["power_w"] for r in self.records if r["power_w"] > 0]
        temps = [r["cpu_temp_c"] for r in self.records]
        gpu_acts = [r["gpu_act_mhz"] for r in self.records if r["gpu_act_mhz"] > 0]
        p_maxes = [r["p_core_max_mhz"] for r in self.records]
        pl1_throttles = sum(1 for r in self.records if r["th_pl1"] == 1 or "pl1" in r["gpu_throttle_reasons"])
        thermal_throttles = sum(1 for r in self.records if r["th_thermal"] == 1 or "thermal" in r["gpu_throttle_reasons"] or r["th_prochot"] == 1)

        total_samples = len(self.records)
        return {
            "duration_s": round(self.records[-1]["elapsed_s"] - self.records[0]["elapsed_s"], 2),
            "samples": total_samples,
            "power_avg_w": round(sum(powers) / len(powers), 2) if powers else 0.0,
            "power_max_w": round(max(powers), 2) if powers else 0.0,
            "temp_max_c": max(temps) if temps else 0,
            "temp_avg_c": round(sum(temps) / len(temps), 1) if temps else 0,
            "gpu_avg_mhz": round(sum(gpu_acts) / len(gpu_acts), 1) if gpu_acts else 0,
            "gpu_min_mhz": min(gpu_acts) if gpu_acts else 0,
            "gpu_max_mhz": max(gpu_acts) if gpu_acts else 0,
            "p_core_avg_max_mhz": round(sum(p_maxes) / len(p_maxes), 1) if p_maxes else 0,
            "pl1_throttle_pct": round((pl1_throttles / total_samples) * 100, 1) if total_samples else 0,
            "thermal_throttle_pct": round((thermal_throttles / total_samples) * 100, 1) if total_samples else 0,
        }


def print_baseline_registers():
    print("=" * 60)
    print("BASELINE HARDWARE REGISTER CONFIGURATION")
    print("=" * 60)

    pl1_msr = read_int(RAPL_PL1_MSR, 0) / 1e6
    pl1_mmio = read_int(RAPL_PL1_MMIO, 0) / 1e6
    pl2_msr = read_int(RAPL_PL2_MSR, 0) / 1e6
    pl2_mmio = read_int(RAPL_PL2_MMIO, 0) / 1e6
    tau_msr = read_int(RAPL_TAU_MSR, 0) / 1e6
    tau_mmio = read_int(RAPL_TAU_MMIO, 0) / 1e6
    epp = read_sysfs(CPU_EPP_PATH, "unknown")

    gpu_min = read_sysfs(GPU_MIN_FREQ, "unknown")
    gpu_max = read_sysfs(GPU_MAX_FREQ, "unknown")
    gpu_rp0 = read_sysfs(GPU_RP0_FREQ, "unknown")

    has_rapl_energy = os.access(RAPL_ENERGY_PATH, os.R_OK)

    print(f"RAPL Package MSR:  PL1 = {pl1_msr:.1f}W | PL2 = {pl2_msr:.1f}W | Tau = {tau_msr:.2f}s")
    print(f"RAPL Package MMIO: PL1 = {pl1_mmio:.1f}W | PL2 = {pl2_mmio:.1f}W | Tau = {tau_mmio:.2f}s (Effective cap: {min(pl1_msr, pl1_mmio):.1f}W)")
    print(f"CPU Scaling EPP:   {epp}")
    print(f"GPU Frequencies:   Min = {gpu_min} MHz | Max = {gpu_max} MHz | RP0 = {gpu_rp0} MHz")
    print(f"RAPL Energy Acc:   {'Accessible (Live Power in Watts active)' if has_rapl_energy else 'Read-restricted (run `sudo chmod 444 /sys/class/powercap/intel-rapl:0/energy_uj` for live Watts)'}")
    print("=" * 60)


def run_openvino_benchmark(model_dir="/home/onkar/LocalAI/models/Qwen3.5-9B-int4-ov", device="GPU", num_runs=5):
    try:
        import openvino_genai as ov_genai
    except ImportError:
        print("[!] openvino_genai not found in current Python path. Running via subprocess...")
        return None

    print(f"\n[+] Initializing OpenVINO VLMPipeline on {device} ({model_dir})...")
    t0 = time.perf_counter()
    pipe = ov_genai.VLMPipeline(model_dir, device)
    load_time_s = time.perf_counter() - t0
    print(f"[+] Loaded pipeline in {load_time_s:.2f}s")

    prompt = "Explain what a Vulkan compute shader is in two sentences."
    config = ov_genai.GenerationConfig()
    config.max_new_tokens = 300
    config.do_sample = False

    print(f"[+] Running warmup pass...")
    pipe.generate(prompt, generation_config=config)

    print(f"[+] Starting {num_runs} timed benchmark runs...")
    perf = None
    runs_data = []

    for i in range(num_runs):
        res = pipe.generate(prompt, generation_config=config)
        m = res.perf_metrics
        perf = m if perf is None else perf + m
        tp = m.get_throughput()
        ttft = m.get_ttft()
        num_toks = m.get_num_generated_tokens()
        print(f"  Run {i+1}/{num_runs}: {tp.mean:.2f} tok/s | TTFT: {ttft.mean:.1f}ms | Tokens: {num_toks}")
        runs_data.append({"run": i+1, "tok_per_s": tp.mean, "ttft_ms": ttft.mean, "tokens": num_toks})

    tp = perf.get_throughput()
    ttft = perf.get_ttft()
    tpot = perf.get_tpot()
    return {
        "model": model_dir,
        "device": device,
        "load_time_s": round(load_time_s, 2),
        "throughput_mean": round(tp.mean, 2),
        "throughput_std": round(tp.std, 2),
        "ttft_mean": round(ttft.mean, 1),
        "ttft_std": round(ttft.std, 1),
        "tpot_mean": round(tpot.mean, 2),
        "tpot_std": round(tpot.std, 2),
        "runs": runs_data
    }


if __name__ == "__main__":
    print_baseline_registers()

    target_model = sys.argv[1] if len(sys.argv) > 1 else "/home/onkar/LocalAI/models/Qwen3.5-9B-int4-ov"
    target_device = sys.argv[2] if len(sys.argv) > 2 else "GPU"

    timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_csv = f"baseline_telemetry_{timestamp_str}.csv"

    logger = HardwareTelemetryLogger(sample_interval_s=0.25)
    print(f"\n[+] Starting telemetry sampling (250ms interval)...")
    logger.start()

    bench_metrics = None
    try:
        bench_metrics = run_openvino_benchmark(target_model, target_device)
    except Exception as e:
        print(f"[!] Benchmark exception: {e}")
    finally:
        print("\n[+] Stopping telemetry sampler...")
        logger.stop()

    logger.save_csv(log_csv)
    summary = logger.summarize()

    print("\n" + "=" * 60)
    print("BENCHMARK & TELEMETRY SUMMARY REPORT")
    print("=" * 60)
    if bench_metrics:
        print(f"Model:                {bench_metrics['model']}")
        print(f"Device:               {bench_metrics['device']}")
        print(f"Throughput:           {bench_metrics['throughput_mean']} +/- {bench_metrics['throughput_std']} tok/s")
        print(f"TTFT (Prefill):       {bench_metrics['ttft_mean']} +/- {bench_metrics['ttft_std']} ms")
        print(f"TPOT (Decode Latency):{bench_metrics['tpot_mean']} +/- {bench_metrics['tpot_std']} ms/tok")
        print("-" * 60)

    print(f"Benchmark Duration:   {summary.get('duration_s', 0)}s ({summary.get('samples', 0)} samples)")
    if summary.get('power_avg_w', 0) > 0:
        print(f"Package Power (Avg):  {summary.get('power_avg_w')} W")
        print(f"Package Power (Peak): {summary.get('power_max_w')} W")
    print(f"CPU Temp (Peak):      {summary.get('temp_max_c')} °C (Avg: {summary.get('temp_avg_c')} °C)")
    print(f"GPU Clock (Avg/Peak): {summary.get('gpu_avg_mhz')} MHz / {summary.get('gpu_max_mhz')} MHz (Min: {summary.get('gpu_min_mhz')} MHz)")
    print(f"P-Core Clock (Avg):   {summary.get('p_core_avg_max_mhz')} MHz")
    print(f"PL1 Power Throttled:  {summary.get('pl1_throttle_pct')} % of duration")
    print(f"Thermal Throttled:    {summary.get('thermal_throttle_pct')} % of duration")
    print(f"Detailed CSV Log:     {os.path.abspath(log_csv)}")
    print("=" * 60)
