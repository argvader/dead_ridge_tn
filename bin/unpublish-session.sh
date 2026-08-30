#!/usr/bin/env bash
#
# unpublish-session.sh <DATE>
#
# Remove an already-published session so it can be regenerated and republished.
# Touches ONLY the published session artifacts — never the raw inputs and never
# the wiki (wiki edits are cumulative and not safely reversible).
#
# Removes:
#   - docs/sessions/<DATE>.md
#   - docs/assets/sessions/<DATE>*.png   (generated scene image[s])
#   - the session's nav line in mkdocs.yml
#   - the session's row in the docs/index.md Sessions table
#
# Leaves sessions-raw/<DATE>/ intact so you can re-run SESSION_SUMMARIZER.md.
#
# Usage:
#   bin/unpublish-session.sh 2026-07-03

set -euo pipefail

# Run from the repo root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

DATE="${1:-}"

if [[ -z "$DATE" ]]; then
  echo "usage: bin/unpublish-session.sh <DATE>   (e.g. 2026-07-03)" >&2
  exit 1
fi

if [[ ! "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "unpublish-session: DATE must be YYYY-MM-DD, got '$DATE'" >&2
  exit 1
fi

SESSION_MD="docs/sessions/${DATE}.md"

if [[ ! -f "$SESSION_MD" ]]; then
  echo "unpublish-session: no published session at $SESSION_MD — nothing to do." >&2
  exit 1
fi

echo "Unpublishing session $DATE ..."

# 1. Session page.
rm -f "$SESSION_MD"
echo "  removed $SESSION_MD"

# 2. Generated scene image(s) for this session.
shopt -s nullglob
scene_images=(docs/assets/sessions/${DATE}*.png)
shopt -u nullglob
if (( ${#scene_images[@]} )); then
  rm -f "${scene_images[@]}"
  echo "  removed ${scene_images[*]}"
fi

# 3. Nav line in mkdocs.yml (the entry pointing at sessions/<DATE>.md).
if grep -q "sessions/${DATE}.md" mkdocs.yml; then
  sed -i "\#sessions/${DATE}\.md#d" mkdocs.yml
  echo "  removed nav entry in mkdocs.yml"

  # If that was the last session, the "- Sessions:" nav header is now empty, which
  # is an invalid mkdocs config (a section with no children). Drop the empty header
  # so the site still builds; the summarizer recreates it when a session returns.
  # A child entry is indented deeper (6 spaces) than the "  - Sessions:" header.
  awk '
    /^  - Sessions:[[:space:]]*$/ {
      header = $0
      if ((getline next_line) > 0) {
        if (next_line ~ /^      /) { print header }  # has a child — keep the header
        print next_line
      }
      next                                            # empty/EOF — drop the header
    }
    { print }
  ' mkdocs.yml > mkdocs.yml.tmp && mv mkdocs.yml.tmp mkdocs.yml

  if ! grep -q "^  - Sessions:" mkdocs.yml; then
    echo "  removed now-empty \"Sessions\" nav section (no sessions remain)"
  fi
fi

# 4. Table row in docs/index.md (the row linking to sessions/<DATE>.md).
if grep -q "sessions/${DATE}.md" docs/index.md; then
  sed -i "\#sessions/${DATE}\.md#d" docs/index.md
  echo "  removed table row in docs/index.md"
fi

echo
echo "Done. sessions-raw/${DATE}/ was left untouched."
echo "Next: re-run SESSION_SUMMARIZER.md for ${DATE}, then commit & push to republish."
