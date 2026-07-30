# /home/onkar/LocalAI

Dual-OS (Windows + Fedora) local LLM serving setup, built around llama.cpp. See [SETUP.md](SETUP.md) for hardware, directory layout, and models in production - read it instead of exploring the tree. See [JOURNAL.md](JOURNAL.md) for a dated log of changes, fixes, and incidents - append to it (newest entry on top) whenever you make a change or resolve an issue here.

- `llama.cpp/` - built from source (Vulkan backend). It's an upstream checkout with its own [AGENTS.md](llama.cpp/AGENTS.md) contribution rules - only read that file when actually working inside `llama.cpp/`, not for unrelated tasks in this directory.
- `models/`, `start-*.sh` - GGUF models and launch scripts, referenced in SETUP.md.
- `linkedin-post.md` - write-up of the Windows to Linux port.
