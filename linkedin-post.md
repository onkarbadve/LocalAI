# LinkedIn Posts — LocalAI Series

Working archive of the post series on this setup. Status noted per post — LIVE posts are published as-is and should not be edited here; DRAFT posts are still being iterated on.

**This is a chapter-by-chapter deep dive, not a one-off "I set it up" story** — each post below is one chapter in an ongoing push past "simple setup and chat works" toward this hardware's actual ceiling. Posts 1-7 are the chapters already covered (coding assistant → cache bugs → OS port → tool-calling bugs → Gemma's deprioritization → Tailscale remote access → uncensored-model evaluation). The next chapters (8+) are already scoped in `SETUP.md`'s "Path forward" section — RAG to close the hallucination gap, resolving the GPU-hang bug upstream instead of just mitigating it, real concurrent serving, voice via `whisper.cpp`, a personal fine-tune, auto-healing infrastructure, and a repeatable model-evaluation pipeline. Each of those is a future post in this same series, not a separate project.

---

## Post 1 — Local coding assistant on integrated graphics (LIVE)

"Local AI coding assistant on integrated graphics" sounds like a contradiction. No discrete GPU, 16GB shared RAM, a 3 year old laptop. On paper it shouldn't be usable for real work.

I built one anyway this month. Zero cloud, zero subscription, nothing leaves the machine.

llama.cpp on Vulkan, running on the i5-12500H's Iris Xe iGPU. Two models running together, not one. Qwen3.5-4B handles chat, edit and agent mode. Qwen2.5-Coder-1.5B sits alongside it for autocomplete only, because waiting on a 4B model to finish a single-line completion defeats the point of autocomplete. Both fit inside 8GB of shared VRAM at the same time. Wired into Continue.dev in VS Code.
8-9 tok/s from the 4B model. 25 tok/s from the 1.5B one.

The harder part wasn't inference speed. It was getting the agent to actually do things. MCP tools for filesystem, git, memory, web fetch, shell. It can check git history, pull the Spring docs it needs, run a Maven build, without me stepping in at each point. That's the actual difference between autocomplete and an agent.

Being honest about what this is: it does not replace GitHub Copilot or Claude Code. A 4B model is not going to plan a migration, reason across a sprawling legacy codebase, or catch the architectural mistake you were about to make. That is still where the large models earn their keep.
What it does replace is everything downstream of the decision. Once the approach is settled, most of the remaining work is mechanical. Write the method, apply the pattern, wire the config, run the build. A 4B model handles that fine, and it handles it on code that never leaves my laptop.

Large models as advisors and planners. Local models as the implementation layer. That split turns out to be more useful than trying to force one tool to be both.

Two things didn't go cleanly. The MCP proxy setup broke on npm on Windows. Never root-caused it, switched to the Python implementation instead. And Qwen3.5's hybrid SWA architecture has a cache-miss bug I'm still working through. Not fixed yet, just tracked.

If you're running local models alongside cloud ones, curious where you've drawn the line between them.

#AIEngineering #LocalAI #llamacpp #MCP #SoftwareEngineering

---

## Post 2 — The cache-miss bug, in full (LIVE)

Last post I mentioned a cache-miss bug I was still working through. Here's what was actually behind it.

The general chat setup: Qwen3-4B-Instruct-2507 and Gemma 4 E4B, via llama.cpp on the i5-12500H, Iris Xe iGPU, no discrete GPU. Vulkan backend, 8 threads, flash attention, quantized KV cache. Gemma auto-detects full offload at 43 of 43 layers. Qwen needed an explicit -ngl 37 on this build, one layer short of full, with the output layer left on CPU.

Full technical breakdown, flags, configs, every issue with the upstream reference in the first comment.

Two separate upstream bugs, not one.
The first was on the original chat model, Qwen3.5-4B: hybrid attention plus a Mamba2/SSM recurrent-memory component, and cached_tokens got stuck at 82 no matter how many turns passed. Not a checkpoint-frequency problem, a checkpoint-restore-selection problem, so the usual flags did nothing. Still open upstream as of this build. Switched to Qwen3-4B-Instruct-2507, dense, no recurrent memory, the bug doesn't apply to it.

The second was on Gemma: without --swa-full, every multi-turn request reprocessed the entire conversation from scratch, cached_tokens=0 on turn two, every time. The fix already existed in the build, just opt-in. Turned it on, verified turn two actually reused the cached prefix this time. Cost: the SWA cache footprint more than triples, roughly 293MB to 952MB.

Vision worked once that flag was in place. Audio didn't, for two separate reasons. The server's HTTP API has no audio input routing at all, closed upstream as not planned. The CLI workaround crashes loading this model with its vision projector file before it even reaches the audio step. Tried the two flags people suggested for adjacent bugs. Neither touched it. Vision-only, and that's where it stays.

--mlock behaved differently by model, not just by OS. Kept it on the smaller Qwen footprint. On Gemma with vision loaded, it fought the OS hard enough to crash a browser tab once, with under 0.6GB free at the time. Pulled it for that script specifically, mmap handles it instead.

Also upgraded the llama.cpp build mid-way through this. Re-checked what mattered after: layer offload unchanged, the --swa-full fix still worked, generation speed unchanged. Compute buffer usage dropped by more than half. Kept the old build folder anyway, in case something I hadn't tested broke.

None of this shows up in a benchmark chart. Tok/s tells you the model is fast. It says nothing about whether turn three of a conversation still remembers turn one.

If you're running local models: how much of your setup time actually goes to upstream bugs versus your own config?

#LLM #LocalAI #llamacpp #AIEngineering #SoftwareEngineering

---

## Post 3 — Windows to Fedora port (DRAFT — use this version, not any earlier draft)

Local AI series — chapter 3. Chapters 1 and 2 are pinned in my Featured section.

Same models, same flags, same laptop. Windows and Fedora ran this local LLM setup at nearly identical speed. Getting there cost one wrong package name and a RAM limit nobody expects to find on a desktop OS.

Moved a tuned llama.cpp setup off Windows onto Fedora. Same laptop, same Iris Xe iGPU, no discrete GPU. Picked Fedora 44 with KDE Plasma specifically for the lower idle RAM footprint over GNOME. On a 16GB box running an LLM, every GB the desktop environment holds onto is a GB the model doesn't get. Build failed on the first attempt:

CMake Error: Could NOT find Vulkan (missing: glslc)

Not glslangValidator, looks like the same tool, isn't. Two more missing before it would configure: spirv-headers-devel, spirv-tools-devel.

--mlock, which had been fine on Windows, did this instead:

warning: failed to mlock 412090368-byte buffer: Cannot allocate memory
$ ulimit -l
8192

8MB cap, set by systemd's `user@.service`, not `/etc/security/limits.conf` like every search result claims. Fedora desktop sessions get their limits from systemd, not PAM. That one cost real time to track down.

Didn't fight it. Windows testing had already shown mlock gets risky under memory pressure on 16GB anyway. Both platforms run on plain mmap now.

Result once everything's ported: 9.2 tok/s Fedora vs 9.4 tok/s Windows, same models, same flags, effectively identical. Cold start is the actual difference. Fedora starts at ~2.5 tok/s while Mesa compiles shaders for the first request, climbs to ~28 once cached. Windows takes 30-90s to first token cold, ~7s on every restart after.

#Linux #LocalAI #llamacpp #Fedora

---

## Post 4 — Open WebUI tool-calling bugs (DRAFT)

Local AI series — chapter 4.

Turning on all 26 tools at once didn't just slow one model down. It broke two different models in two completely different ways, and one of the breaks was completely silent.

llama.cpp serves the model on a local port. Open WebUI is the layer that turns that into something with tools: notes, calendar, memory, search. That layer is also where most of the real bugs live.

Turned on the full Builtin Tools set, 26 declarations, and Gemma started returning this instead of a response:

unused2171 unused2127 unused2094 ...

One tool, fine. 26 tools plus --reasoning off, broken. Not degraded. Unusable.

Switched to Qwen3-4B-Instruct-2507. It needed --reasoning off too, for an unrelated bug. This checkpoint's chat template has a reasoning branch it never emits, so auto-detection waits forever for a closing tag. A second flag was stacked on top of that fix, --skip-chat-parsing. Looked harmless. It silently disables structured tool_calls extraction. Same symptom as Gemma, completely different mechanism, no error, no log line.

Dropped that second flag, retested at 2-tool and 14-tool scale against the exact conditions that had caused problems before:

finish_reason: stop
tool_calls: get_current_timestamp

Clean. Then actually validated it. 9 tests through the real UI, not curl, across 6 tool categories. Checked that outputs persisted, not just that responses looked right:

turn 1: prompt_tokens 5824, cached 0, 15.3s
turn 2: prompt_tokens 5990, cached 5857, 23.8s (tool call, 2 passes)

98% of that ~5,800-token tool-declaration prefix reused from cache on turn two. Every single-message benchmark you'll see for a setup like this is a fresh-chat worst case. Real conversations are cheaper once the cache warms.

One gap that isn't fixable from this side: Open WebUI's Code Interpreter never sends a code-execution tool declaration to a llama.cpp backend at all. Traced the actual request payload to confirm. The model correctly says it can't run code instead of hallucinating output. That auto-invoke path is wired for specific cloud models, not local backends, full stop.

#AIAgents #LocalAI #llamacpp #OpenWebUI

---

## Post 5 — Gemma deprioritization (DRAFT — corrected, renumbered to slot into the sequence)

Local AI series — chapter 5.

Gemma 4 E4B checked every box on paper. Vision, audio, agent mode. In practice, four separate issues stacked up until it wasn't worth defending as the primary model.

Moved it out of the primary/agent-mode role. Reasons stacked up rather than any single one being disqualifying:

Full Builtin Tools set (26 declarations) plus --reasoning off produced unusable garbage tokens instead of a response. One tool, fine. At scale, broken.

Disproportionately the model hitting a recurring i915/Vulkan fence-timeout crash on this Iris Xe iGPU. Same underlying driver bug affects both models, but Gemma's traffic pattern triggered it more.

Vision support needed real flag-chasing to get stable (--swa-full for multi-turn caching, reduced context to fit the mmproj file).

Audio never worked at all. Two separate upstream blockers, one closed "not planned."

None of these individually would have been a dealbreaker. Together, defending it as the primary model stopped being worth it. Tool-calling duty moved to Qwen3-4B-Instruct-2507. Vision hasn't turned out to be an actual need since, so Gemma isn't in active rotation anymore — kept only as a fallback if that changes.

Has anyone gotten Gemma stable for agent-mode tool-calling at scale on llama.cpp? Or hit the same combination of issues and made the same call?

#LocalAI #llamacpp #OpenWebUI #AIEngineering

---

## Post 6 — Tailscale remote access (DRAFT, renumbered from 5)

Local AI series — chapter 6.

The setup also runs a shell-execution service behind the chat UI, for real agent file/shell access, not just chat. That changes what "remote access" is allowed to mean.

Tailscale, private mesh network, no port-forwarding, nothing public:

sudo dnf install -y tailscale
systemctl enable --now tailscaled
tailscale up

Fedora 44 already ships it in-repo. The upstream repo-add step in the docs isn't needed and fails on dnf5 syntax anyway.

First gap: MagicDNS names resolved from the desktop, not from the phone.

curl [tailnet-hostname]:3000, works, desktop
curl [tailnet-hostname]:3000, fails, phone
curl [tailnet-ip]:3000, works, phone

Root cause: Tailscale's DNS override was off on the phone (turned off earlier to stop it fighting a different DNS profile), so it had no path to resolve .ts.net names at all. Raw tailnet IP works regardless. That's what actually matters for reachability.

Second gap, more interesting: firewall-cmd --get-zone-of-interface=tailscale0 came back empty. The tailnet interface wasn't assigned to any firewalld zone, meaning traffic on it wasn't guaranteed to pass the active ruleset even though the tailnet connection itself was live.

firewall-cmd --zone=trusted --change-interface=tailscale0 --permanent
firewall-cmd --reload

Then the actual decision. A convenience feature existed, a personal terminal connection giving a live file-browser panel, that made requests straight from the browser to the shell service's port. Fine on a local network. From a phone, the only way to make that panel work remotely would be publishing the shell API onto the tailnet directly, reachable by any device on it, not just this machine.

Deleted that connection. Chat-based tool use, proxied through the backend, works identically from the phone over mobile data. The shell API stayed loopback-only. Traded a UI panel for zero new attack surface on a raw shell endpoint.

#SelfHosted #Tailscale #LocalAI #Security

---

## Post 7 — Evaluating an uncensored model without trusting AI-generated slop about AI (DRAFT, renumbered from 6)

Local AI series — chapter 7.

Went looking for a local model that wouldn't hedge and moralize on every sensitive-but-legal question. What I actually learned was how much AI content on the internet is now AI-generated slop about AI.

The setup: an abliterated (refusal-removed) fine-tune of a 4B model, running on the same Fedora box's Intel iGPU as everything else in this series. Straightforward in theory, except every "best uncensored models" search surfaced the same wave of SEO blogs — confident, specific-sounding benchmark numbers, zero verifiable sourcing. One even cited scores from a model version I couldn't confirm exists.

→ Cross-checked against a real, live community leaderboard instead — had to drive it with actual browser automation, since it's a JS-rendered Gradio app and plain fetch tools got nothing back.

→ Ruled out an entire model family by reading the actual open GitHub issue, not assuming "surely fixed by now." Still open, still broken.

→ Checked llama.cpp's own source to see which models get a hand-written parser (real bug surface) versus the generic path — a code-level signal no blog post was going to give me.

→ One tool fetch flatly claimed a well-known model org had zero public models. Reality: dozens. Broken page render, not a broken org — worth remembering before trusting any single source once.

Once it was running, a separate finding worth keeping straight: refusal and hallucination are not the same failure mode. Ask it something sensitive-but-legal, it answers directly, no hedging. Ask it a real-world factual question outside its training strength, it confabulated an entire plausible-sounding backstory, complete with specific fake details. Removing refusal behavior does nothing to fix confidence in wrong answers. Different problem, different fix.

#LLM #LocalAI #llamacpp #AI
