# /home/onkar/LocalAI
be token concious
Dual-OS (Windows + Fedora) local LLM serving setup, built around llama.cpp. See [SETUP.md](SETUP.md) for hardware, directory layout, and models in production - read it instead of exploring the tree. See [JOURNAL.md](JOURNAL.md) for a dated log of changes, fixes, and incidents - append to it (newest entry on top) whenever you make a change or resolve an issue here. See [AGENTS.md](AGENTS.md) for tool-agnostic conventions (coding style, documentation rules, testing expectations) that apply regardless of which AI tool is being used.

- `llama.cpp/` - built from source (Vulkan backend). It's an upstream checkout with its own [AGENTS.md](llama.cpp/AGENTS.md) contribution rules - only read that file when actually working inside `llama.cpp/`, not for unrelated tasks in this directory.
- `models/`, `start-*.sh` - GGUF models and launch scripts, referenced in SETUP.md.
- `docs/` - topic-specific reference docs (architecture, hardware, models, benchmarks, troubleshooting, lessons learned) extracted from README/SETUP/JOURNAL.
- `linkedin-post.md` - write-up of the Windows to Linux port. Local only (gitignored), not pushed to remote.
