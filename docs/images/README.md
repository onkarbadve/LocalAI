# Images

## Screenshot placeholders

Every screenshot `.png` in this directory is a **blank placeholder** (solid neutral gray, no real UI content) — not a real screenshot. They exist so the [README](../../README.md)'s Screenshots section and any other markdown embedding them renders correctly instead of showing broken-image icons, while it's obvious from opening the file that no real capture has happened yet.

Replace each file in place (keep the filename) with a real screenshot (PNG or JPG) as it's captured — no other changes needed, every reference already points at these paths.

| File | Should show | Status |
|---|---|---|
| `openwebui-home.png` | Open WebUI homepage / chat list | TODO — placeholder |
| `chat.png` | A real chat conversation, ideally showing an agent-mode tool call in action | TODO — placeholder |
| `model-selection.png` | Model picker showing all three registered `llama-server` connections (production + 2 uncensored) | TODO — placeholder |
| `mobile.png` | Open WebUI accessed from a phone over the Tailscale tailnet | TODO — placeholder |
| `open-terminal.png` | Open Terminal integration — the SYSTEM connection invoked from chat, or the Files/Terminal side panel | TODO — placeholder |
| `settings.png` *(optional)* | Model Capabilities / Integrations settings pages referenced in [docs/troubleshooting.md](../troubleshooting.md) | TODO — placeholder |

## Generated diagrams

| File | What it is | Status |
|---|---|---|
| `architecture.png` | Static PNG export of the Mermaid diagram in [docs/architecture.md](../architecture.md), for viewers without Mermaid rendering | **Stale** — diagram gained SearXNG/MeTube/Gemma-uncensored on 2026-08-02; regenerate with `mmdc` once available on this box |
