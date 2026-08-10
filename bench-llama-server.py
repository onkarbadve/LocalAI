#!/usr/bin/env python3
#
# Purpose: benchmark a running llama-server instance's prompt-processing (PP)
#   and token-generation (TG) throughput via its native /completion endpoint,
#   which returns a "timings" object (prompt_per_second / predicted_per_second)
#   - no need to hand-time requests.
# Requires: a llama-server instance already running and reachable (start it
#   with the relevant start-*.sh script first - this doesn't launch anything).
# Arguments: --port (required), --label (required, just an output tag),
#   --pp-repeat (default 60 - sentence repeats to build the PP prompt),
#   --tg-predict (default 128 - tokens forced per generation run),
#   --runs (default 5 - timed repetitions per phase, plus 1 untimed warmup).
# Expected output: human-readable PP/TG mean +/- stdev lines, then one JSON
#   summary line (parseable, for scripting/comparison across runs).
# Typical usage: ./bench-llama-server.py --port 8081 --label "Qwen3-4B-heretic"
# Failure cases: connection refused if no server is listening on --port;
#   a request timeout (180s) if the model hangs - matches other timeout
#   values used elsewhere in this repo for runaway-generation protection.
#
# Methodology: 1 warmup run + 5 timed runs (default) for each of PP and TG -
# same "N timed + 1 warmup" convention already used in this repo's OVMS
# benchmark (test_ov_qwen.py), for consistency across the project's
# benchmarking scripts.
#
# cache_prompt: false is set on every request so each run does a full,
# uncached prompt evaluation - otherwise a repeated/overlapping prompt would
# hit the server's prompt cache (`-np 1` keeps one persistent slot) and
# prompt_per_second would reflect a cache hit, not real prompt-processing
# throughput. Verified directly: without this flag, a repeated prompt's
# tokens_evaluated dropped to near-zero on the 2nd+ request.
#
# ignore_eos: true on the TG runs forces exactly n_predict tokens to be
# generated every run, so token count (and therefore tok/s) is directly
# comparable across runs and across models - without it, a model that stops
# early (hits its own EOS) would generate a different token count than one
# that doesn't, making the tok/s figures not apples-to-apples.
#
# Not a llama-bench replacement: llama-bench loads the GGUF directly and
# bypasses the HTTP server entirely, which is the more standard way to
# compare raw model/quant throughput. This script instead measures the
# server as it's actually run in production (same flags, same port, same
# -np 1 single-slot behavior) - the two will disagree somewhat and that's
# expected; this one answers "what does the real deployed server do."

import argparse
import json
import statistics
import urllib.request


def post(base_url, payload):
    req = urllib.request.Request(
        f"{base_url}/completion",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        return json.loads(resp.read())


def run_pp(base_url, prompt_text, n_runs):
    payload = {"prompt": prompt_text, "n_predict": 1, "cache_prompt": False}
    warm = post(base_url, payload)  # warmup, not counted
    results = [post(base_url, payload)["timings"]["prompt_per_second"] for _ in range(n_runs)]
    return warm["timings"]["prompt_n"], results


def run_tg(base_url, prompt_text, n_predict, n_runs):
    payload = {
        "prompt": prompt_text,
        "n_predict": n_predict,
        "cache_prompt": False,
        "ignore_eos": True,
    }
    warm = post(base_url, payload)  # warmup, not counted
    results = [post(base_url, payload)["timings"]["predicted_per_second"] for _ in range(n_runs)]
    return warm["timings"]["predicted_n"], results


def summarize(label, values, unit="tok/s"):
    mean = statistics.mean(values)
    stdev = statistics.stdev(values) if len(values) > 1 else 0.0
    print(f"{label}: {mean:.2f} +/- {stdev:.2f} {unit}  (runs: {[round(v, 2) for v in values]})")
    return mean, stdev


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--label", required=True, help="model label for output")
    ap.add_argument("--pp-repeat", type=int, default=60, help="sentence repeats to build the PP prompt")
    ap.add_argument("--tg-predict", type=int, default=128)
    ap.add_argument("--runs", type=int, default=5)
    args = ap.parse_args()

    base_url = f"http://127.0.0.1:{args.port}"
    pp_prompt = " ".join(["The quick brown fox jumps over the lazy dog."] * args.pp_repeat)
    tg_prompt = "Write a short paragraph about the history of the Roman Empire."

    print(f"=== {args.label} (port {args.port}) ===")

    pp_n, pp_vals = run_pp(base_url, pp_prompt, args.runs)
    print(f"PP prompt size: {pp_n} tokens")
    pp_mean, pp_std = summarize("Prompt processing", pp_vals)

    tg_n, tg_vals = run_tg(base_url, tg_prompt, args.tg_predict, args.runs)
    print(f"TG tokens generated per run: {tg_n}")
    tg_mean, tg_std = summarize("Generation", tg_vals)

    print(json.dumps({
        "label": args.label,
        "port": args.port,
        "pp_tokens": pp_n,
        "pp_mean_tok_s": round(pp_mean, 2),
        "pp_stdev_tok_s": round(pp_std, 2),
        "tg_tokens": tg_n,
        "tg_mean_tok_s": round(tg_mean, 2),
        "tg_stdev_tok_s": round(tg_std, 2),
    }))


if __name__ == "__main__":
    main()
