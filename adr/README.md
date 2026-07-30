# Architecture Decision Records

Stable, load-bearing engineering decisions behind this setup — the *why*, distilled from [JOURNAL.md](../JOURNAL.md)'s chronological history into a form that doesn't require reading the whole log to understand a current choice. If the journal is the trial transcript, these are the verdicts.

Each record covers Context, Decision, Alternatives Considered, and Consequences. Where no alternative was actually evaluated at the time, the record says so directly rather than inventing a comparison that didn't happen — see [0003-openwebui.md](0003-openwebui.md) for an example.

| ADR | Decision |
|---|---|
| [0001](0001-fedora-over-windows.md) | Fedora as the daily driver, Windows preserved as origin |
| [0002](0002-qwen3-model-choice.md) | Qwen3-4B-Instruct-2507 as the production chat/agent model |
| [0003](0003-openwebui.md) | Open WebUI as the chat frontend, on rootless Podman |
| [0004](0004-vulkan-backend.md) | Vulkan as the llama.cpp inference backend |

New ADRs should follow the same numbering (`000N-short-title.md`) and only capture decisions that are actually stable — a one-off bugfix belongs in [JOURNAL.md](../JOURNAL.md) or [docs/troubleshooting.md](../docs/troubleshooting.md) instead, per [AGENTS.md](../AGENTS.md#documentation-update-rules).
