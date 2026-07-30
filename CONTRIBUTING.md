# Contributing

This repository is primarily a personal engineering notebook — a running record of one setup, on one specific machine. It's shared publicly because the documented issues, fixes, and reasoning are likely useful to anyone else running local LLMs on integrated graphics / RAM-constrained hardware. Contributions are welcome within that scope.

## What's in scope

- Corrections to documented facts, flags, or reasoning that are actually wrong.
- Fixes to broken links, formatting, or markdown rendering issues.
- Clarifications where the documentation is genuinely confusing to a first-time reader.
- New troubleshooting entries **if you hit the same issue independently and can confirm the same root cause** — open an issue first to discuss before writing it up.

## What's out of scope

- Feature requests for the setup itself (this isn't a product — it reflects one person's actual hardware and choices).
- Rewriting the tone or structure of `JOURNAL.md`. It's a historical log; entries are not edited retroactively except to fix factual errors.
- Adding speculative content, benchmark numbers, or conclusions that weren't actually measured on this hardware — see [AGENTS.md](AGENTS.md#documentation-standards) for why.

## Workflow

1. **Open an issue first** for anything beyond a trivial typo/link fix, describing what you found and why it needs changing. This avoids wasted effort on a PR that doesn't fit the notebook's scope.
2. **Fork and branch** from `main`.
3. **Keep changes focused** — one issue/topic per pull request.
4. **Reference what you verified.** If you're correcting a technical claim, say how you confirmed it (a command you ran, an upstream issue link, a model card). Unverified claims won't be merged, per the no-fabrication rule in [AGENTS.md](AGENTS.md).
5. **Open a pull request** against `main` with a clear description of what changed and why.

## Documentation conventions

Read [AGENTS.md](AGENTS.md) before proposing documentation changes — it covers this repo's specific conventions (comment style in scripts, when to update `JOURNAL.md` vs. `docs/`, why content gets moved rather than deleted).

## Code of conduct

Be respectful and constructive. This is a small, personal project maintained by one person in their spare time — response times may be slow.
