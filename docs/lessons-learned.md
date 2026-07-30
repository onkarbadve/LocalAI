# Lessons Learned

Practical conclusions drawn from real experimentation on this setup — not general advice, specific to what was actually observed here. Sourced from [JOURNAL.md](../JOURNAL.md), [SETUP.md](../SETUP.md), and [linkedin-post.md](../linkedin-post.md). See [troubleshooting.md](troubleshooting.md) for the issues these lessons came out of, and [hardware.md](hardware.md) for the machine they were observed on.

## Performance

- **Vulkan on an Intel Iris Xe iGPU is a viable inference backend, not just a fallback.** Sustained ~9–9.8 tok/s generation across multiple 4B models with no discrete GPU, confirmed GPU-resident via low process RSS after generation. See [benchmarks.md](benchmarks.md).
- **16GB system RAM is workable with the right quantization, but it's a hard ceiling, not a soft one.** Q4_K_XL/Q4_K_M quants at 4B parameters fit comfortably; running two such models concurrently at full context (~12GB combined) does not fit inside the documented ~7.4–9.8GB Vulkan-visible budget. That's a real, measured limit, not a conservative guess (see [SETUP.md](../SETUP.md#qwen3-4b-instruct-2507-heretic-av2--uncensored-bluntdirect-assistant-start-qwen3-uncensoredsh-fedora-only)).
- **A crash that becomes a graceful degradation is real progress even before the root cause is fixed.** The three local `llama.cpp` exception-handling patches (see [troubleshooting.md](troubleshooting.md#llama-server-crashes-not-just-hangs-on-a-device-lost-error)) didn't stop the underlying fence-timeout from occurring — they changed the failure mode from "silent process death" to "clean HTTP 500 until someone restarts it," a meaningfully better state for a system reachable from a phone.

## Model Selection

- **Dense models sidestep bugs that hybrid/recurrent-memory architectures hit.** Qwen3.5-4B's hybrid attention + Mamba2/SSM component had an unresolved multi-turn caching bug (`cached_tokens` stuck regardless of turn count); switching to the dense Qwen3-4B-Instruct-2507 avoided the entire bug class, not just this one instance of it.
- **An abliterated (uncensored) variant of an already-proven base model inherits that base's stability, not just its behavior change.** Choosing an abliteration of the exact model already running in production (rather than a differently-based "uncensored" model) meant it inherited the same generic tool-calling path and avoided both the Gemma-style parser bugs and the Qwen3.5 caching bug — de-risking integration was a direct consequence of the selection criteria, not luck.
- **Uncensored does not mean factually reliable.** The abliterated model confirmed it confabulates confidently on niche real-world facts it doesn't actually know, same as any 4B model — abliteration removes refusal behavior, it doesn't add knowledge or grounding.
- **Small models need explicit anti-repetition and length-cap safeguards for long-form generation.** A long-form creative-writing request degenerated into a cycling phrase loop with no repeat-penalty, no DRY sampling, and no `-n` cap set. `--repeat-penalty`, `--dry-multiplier`, and a hard `-n` ceiling were all needed together — no single one was sufficient on its own as the guaranteed backstop.
- **A small model asked to self-diagnose its own performance can sound confident and still be wrong.** When asked for tuning advice, Gemma conflated prompt-processing throughput with generation throughput, recommended a fix targeting the wrong subsystem (layer offload count instead of Vulkan submission batching), and fabricated a plausible-sounding but nonexistent cost mechanism. Full comparison in [models.md](models.md).

## Windows Experience

- **`--mlock` worked on Windows, but only for the smaller footprint.** Kept for the solo Qwen setup; on Gemma+vision (larger footprint) it fought the OS under memory pressure and crashed a browser tab once, at 0.59GB free — removed for that script specifically, relying on mmap instead.
- **A precompiled Vulkan release build upgrade (b9305 → b10107) was low-risk when re-verified properly.** Layer offload (43/43), `--swa-full` cache reuse, and generation speed (~8–9.5 tok/s) were all confirmed unchanged after the upgrade; compute buffer usage dropped by more than half (~517MB → ~187MB). The old build was kept as an instant rollback rather than deleted — cheap insurance for a change that turned out to be safe anyway.
- **The Windows install was preserved rather than wiped when moving to Fedora**, specifically because some tooling (the MCP server stack, the dual-server coding setup) hadn't been ported yet — a partial migration is a reason to keep the source environment around, not a failure of the migration.

## Fedora Experience

- **The Vulkan backend build has a package-naming trap.** `llama.cpp`'s Vulkan build needs a package named exactly `glslc`, not `glslangValidator` — a similarly-named tool that looks like a substitute but isn't. Two further CMake dependencies (`spirv-headers-devel`, `spirv-tools-devel`) were also required before the build would configure.
- **`--mlock` doesn't work at all on this Fedora install, regardless of model.** `ulimit -l` is capped at 8MB by systemd's `user@.service` hardening default, and the common `/etc/security/limits.conf` advice doesn't apply, since desktop session limits come from systemd, not PAM. Combined with the Windows mlock-under-pressure experience above, plain mmap was adopted everywhere rather than fighting either OS.
- **A VPN overlay (Tailscale) is a materially different security posture than port-forwarding, and it was worth the setup cost for a shell-execution service.** The Open Terminal integration's presence in the stack was itself the deciding factor in choosing Tailscale over simpler remote-access options.
- **"Reachable from a phone" is not one property.** Open WebUI's chat tool-calling (backend-proxied) kept working remotely over Tailscale even when the Files/Terminal side panels (client-side, direct-to-`localhost`) silently failed, because `localhost` resolves to the phone itself on the client side, not the Fedora box.
- **Integrated-GPU fence timeouts are a real, known class of bug, not a fluke on this specific machine.** The `i915`/Vulkan fence-timeout → device-lost chain matched an identical, independently-diagnosed issue on an AMD APU. Recognizing "this looks like a known upstream pattern" via search, rather than assuming a local hardware fault, was what turned an unexplained crash into an actionable mitigation.

## Open WebUI

- **Open WebUI integrates cleanly with a local llama.cpp OpenAI-compatible endpoint for chat, but "agent mode" has real, undocumented rough edges.** Structured tool-calling (Builtin Tools) worked correctly across 9/9 real tests once the underlying server-side hangs were fixed. Code Interpreter's auto-invoke, by contrast, turned out not to be wired up for local llama.cpp backends at all — a real integration gap, not a config problem, confirmed by tracing the actual outgoing prompt and finding no code-execution tool declared.
- **A frontend's default behavior can silently dominate cost and correctness.** Auto-attached Builtin Tools declarations added ~5,100 tokens of overhead to every message regardless of relevance; per-request `reasoning_format` sent regardless of a UI toggle's stated setting caused a server hang that looked at first like a function-calling-mode issue but wasn't. In both cases, the actual client request (traced directly) told a different story than the UI's settings implied.
- **A convenience feature can have two independent, unsynced configuration stores.** Open WebUI's Title/Follow-Up/Tags generation toggles exist at both an admin (site-wide) and personal (per-account) level, and the personal setting silently overrides the admin default without indicating it's doing so. Disabling only one left the behavior unchanged. The terminal-connection split (Direct vs. System, see [troubleshooting.md](troubleshooting.md#open-webui-terminal-integration-terminal-server-not-found)) is the same pattern in a different subsystem.

## llama.cpp

- **A shared chat template across model variants can produce checkpoint-specific bugs.** Qwen3-4B-Instruct-2507's template has a reasoning branch inherited from the "thinking" variant of the same model family, even though this particular checkpoint never uses it — auto-detection logic that trusts the template alone got this wrong and caused runaway generation. The fix (`--reasoning off`) had to be verified as *not* applicable to Gemma before reuse, since Gemma's template doesn't share the same mismatch.
- **`/props` can report a flag as inactive when it's actually enforced.** `-n 2048` correctly capped generation (`finish_reason:"length"`, exact token count) even though `/props` showed `n_predict: -1` — a cosmetic reporting bug in that build, confirmed only by a real generation test, not by trusting the introspection endpoint.
- **Unguarded exception paths tend to cluster around the same failure trigger.** All three uncaught-crash call sites found in the server code (`prompt_save`, `prompt_cache::load`, `ggml_vk_cleanup`) were only found one at a time, each after the previous patch's fix exposed the next unguarded call site further down the same code path during a real device-lost event.

## Vulkan

- **The integrated-GPU fence-timeout bug is a recognized upstream class, not this machine's own hardware fault.** Root-caused via a matching, independently-diagnosed issue on an AMD APU: the Vulkan backend batches up to 100 compute-graph nodes per GPU submission by default, which can exceed the kernel driver's hang-detection timeout on integrated GPUs specifically. `GGML_VK_MAX_NODES_PER_SUBMIT=1` is the validated mitigation for that class of bug, though it remains a trial fix here (fence timeouts have still been observed with it set) rather than a confirmed cure.
- **A device-lost Vulkan error is not one failure — it's several, depending on which call happens to hit it.** The identical underlying condition surfaced as a clean HTTP 500 (in `decode()`, already guarded), an uncaught process crash (in three other call sites, unguarded), and a silent empty-response corruption (no exception thrown at all) — three different symptoms from the same root cause, requiring three different investigations to fully map.

## Things I Would Do Differently

- **Track a background process by PID, not by pattern-matching its command text.** A watcher script using `pgrep -f "<the curl command text>"` to detect whether a download had finished matched its own invocation (which contained the same text as a literal argument) and looped forever even after the real process had already died. `kill -0 $PID` against a captured PID is the robust way to watch a specific background process.
- **Verify empirically with a real test, not just via an introspection endpoint.** Trusting `/props` alone would have concluded `-n 2048` wasn't being enforced; only a real generation test revealed the flag worked and the endpoint's reporting was cosmetically wrong.
- **Don't trust browser clipboard automation for secrets.** Synthetic paste (`wl-copy` + a scripted `ctrl+v`) into connection-key fields was unreliable — silent no-ops, and on two occasions old and new clipboard contents concatenated instead of replacing each other. Typing the value directly was the only fully reliable method found.
- **Reproduce the client's exact request shape before declaring a fix verified.** Several fixes in this project (the reasoning-hang, the tool-call-parser hang, Builtin Tools overhead) were only confirmed by replaying the literal request body the real client sends — a simplified curl request gave false confidence in earlier attempts at some of these same bugs.

## Related documents

- [troubleshooting.md](troubleshooting.md) — the specific issues these lessons were drawn from
- [hardware.md](hardware.md) — the machine these lessons are specific to
- [models.md](models.md) — how the model-selection lessons above played out in practice
- [../adr/](../adr/) — where a lesson hardened into a stable, documented decision
- [roadmap.md](roadmap.md) — where an open lesson turned into planned future work
