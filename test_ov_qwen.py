import gc
import time

import numpy as np
import openvino as ov
import openvino_genai as ov_genai
from PIL import Image

MODEL_DIR = "/home/onkar/LocalAI/models/Qwen3.5-9B-int4-ov"
TEXT_PROMPT = "Explain what a Vulkan compute shader is in two sentences."
VISION_PROMPT = "Describe this diagram in detail: what are the boxes, and what do the arrows between them represent?"
VISION_IMAGE = "/home/onkar/LocalAI/docs/images/architecture.png"
NUM_RUNS = 5
MAX_NEW_TOKENS = 400  # generous - Qwen3.5 is a thinking model, budget must cover <think> + answer


def load_image(path):
    img = Image.open(path).convert("RGB")
    return ov.Tensor(np.array(img).astype(np.uint8))


def bench(pipe, label, prompt, images=None, num_runs=NUM_RUNS):
    print(f"\n=== {label} ===")
    config = ov_genai.GenerationConfig()
    config.max_new_tokens = MAX_NEW_TOKENS
    config.do_sample = False

    kwargs = {"generation_config": config}
    if images is not None:
        kwargs["images"] = images

    # warmup - excluded from timing
    warmup = pipe.generate(prompt, **kwargs)

    perf = None
    last_result = None
    for i in range(num_runs):
        result = pipe.generate(prompt, **kwargs)
        last_result = result
        m = result.perf_metrics
        perf = m if perf is None else perf + m
        tp = m.get_throughput()
        print(f"  run {i + 1}: {tp.mean:.2f} tok/s, TTFT {m.get_ttft().mean:.1f}ms, "
              f"generated {m.get_num_generated_tokens()} tokens")

    tp = perf.get_throughput()
    ttft = perf.get_ttft()
    tpot = perf.get_tpot()
    load_ms = perf.get_load_time()
    print(f"  --- aggregate over {num_runs} runs ---")
    print(f"  throughput: {tp.mean:.2f} +/- {tp.std:.2f} tok/s")
    print(f"  TTFT:       {ttft.mean:.1f} +/- {ttft.std:.1f} ms")
    print(f"  TPOT:       {tpot.mean:.2f} +/- {tpot.std:.2f} ms/token")
    print(f"  load time:  {load_ms:.0f} ms")
    print(f"\n  sample response (last run, truncated to 800 chars):")
    print("  " + str(last_result)[:800].replace("\n", "\n  "))
    return tp.mean, tp.std


if __name__ == "__main__":
    device_used = None
    pipe = None
    for device in ("GPU", "CPU"):
        try:
            t0 = time.perf_counter()
            pipe = ov_genai.VLMPipeline(MODEL_DIR, device)
            load_time_s = time.perf_counter() - t0
            device_used = device
            print(f"Loaded VLMPipeline on {device} in {load_time_s:.2f}s")
            break
        except Exception as e:
            print(f"{device} init failed: {type(e).__name__}: {e}")

    if pipe is None:
        raise SystemExit("Both GPU and CPU device init failed - see errors above.")

    results = {}
    results["text-only"] = bench(pipe, "Text-only generation", TEXT_PROMPT)

    image_tensor = load_image(VISION_IMAGE)
    results["vision"] = bench(pipe, f"Vision (image: {VISION_IMAGE})", VISION_PROMPT, images=[image_tensor])

    del pipe
    gc.collect()

    print("\n=== summary ===")
    print(f"device: {device_used}")
    for label, (mean, std) in results.items():
        print(f"{label}: {mean:.2f} +/- {std:.2f} tok/s")
