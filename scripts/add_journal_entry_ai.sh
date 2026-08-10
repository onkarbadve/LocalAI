#!/usr/bin/env bash
# scripts/add_journal_entry_ai.sh
# Append a single NDJSON journal entry to JOURNAL.md and commit it.
# Usage examples:
#   ./scripts/add_journal_entry_ai.sh '{"date":"2026-08-12","title":"Example","goal":"x","changes":["a"],"results":["b"]}'
# Or pipe JSON on stdin:
#   echo '{...}' | ./scripts/add_journal_entry_ai.sh -

set -euo pipefail
FILE="JOURNAL.md"
ENTRY=""
if [ "${1:-}" = "-" ]; then
  ENTRY=$(cat -)
elif [ "${1:-}" != "" ]; then
  ENTRY="$1"
else
  echo "Usage: $0 '<json-object>'  or echo '<json-object>' | $0 -"
  exit 2
fi
# Basic validation: must contain date and title
if ! echo "$ENTRY" | grep -q '"date"' || ! echo "$ENTRY" | grep -q '"title"'; then
  echo "Entry must contain at least \"date\" and \"title\" fields"
  exit 3
fi
# Append as a single line
echo "$ENTRY" >> "$FILE"
# Optional: commit
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add "$FILE"
  git commit -m "journal(ai): add entry $(echo "$ENTRY" | sed -n 's/.*"date"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p') - $(echo "$ENTRY" | sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')" || true
fi

echo "Appended entry to $FILE"
