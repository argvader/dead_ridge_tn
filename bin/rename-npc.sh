#!/usr/bin/env bash
#
# rename-npc.sh [--dry-run] [--pcs] <old-slug> <new-slug> "<Old Name>" "<New Name>"
#
# Rename a wiki NPC (or PC) everywhere: move the page, rewrite every reference to
# it across the docs tree, and fix the nav label — the mechanical chore behind a
# name correction like "Cerus → Seris" or "Nybora Tidewater → Naivara Tidewoven".
#
# What it does:
#   1. git mv  docs/wiki/<cat>/<old-slug>.md  ->  <new-slug>.md
#   2. Replace "<old-slug>.md" -> "<new-slug>.md" (link targets + nav) across all
#      docs/**/*.md and mkdocs.yml.
#   3. Replace the literal display name "<Old Name>" -> "<New Name>" in the same set.
#
# Category defaults to npcs; pass --pcs to rename a PC instead.
#
# NOTE — deliberate limitations:
#   - Replacements are LITERAL substring swaps. This fits unique single-token
#     corrections (Cerus->Seris). For a multi-word name whose parts also appear
#     alone (e.g. "Nybora Tidewater" also written just "Nybora"), only the exact
#     string you pass is changed — run again for the short form, or fix the
#     stragglers by hand. The script prints leftover mentions so you can spot them.
#   - Compound cases where a surname is shared with an item (e.g. the "Tidewater
#     Amulet" named after the Tidewater family) need a manual pass.
#   - It does NOT move the portrait image (art is dropped in already named to the
#     new slug) and never touches sessions-raw/ (raw source of record).
#
# Always finish with:  mkdocs build --strict
#
# Usage:
#   bin/rename-npc.sh cerus seris "Cerus" "Seris"
#   bin/rename-npc.sh --dry-run --pcs old-hero new-hero "Old Hero" "New Hero"

set -euo pipefail

# Run from the repo root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

DRY_RUN=0
CATEGORY="npcs"
POS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --pcs)     CATEGORY="pcs" ;;
    --npcs)    CATEGORY="npcs" ;;
    --*)       echo "rename-npc: unknown flag '$arg'" >&2; exit 1 ;;
    *)         POS+=("$arg") ;;
  esac
done

if [[ ${#POS[@]} -ne 4 ]]; then
  echo "usage: bin/rename-npc.sh [--dry-run] [--pcs] <old-slug> <new-slug> \"<Old Name>\" \"<New Name>\"" >&2
  exit 1
fi

OLD_SLUG="${POS[0]}"
NEW_SLUG="${POS[1]}"
OLD_NAME="${POS[2]}"
NEW_NAME="${POS[3]}"

PAGE="docs/wiki/${CATEGORY}/${OLD_SLUG}.md"
DEST="docs/wiki/${CATEGORY}/${NEW_SLUG}.md"

if [[ ! -f "$PAGE" ]]; then
  echo "rename-npc: no page at $PAGE — nothing to rename." >&2
  exit 1
fi
if [[ -e "$DEST" ]]; then
  echo "rename-npc: destination already exists: $DEST" >&2
  exit 1
fi

# Files in scope: every markdown page under docs/ plus the nav. Never sessions-raw/.
mapfile -t FILES < <(find docs -name '*.md')
FILES+=("mkdocs.yml")

# Count occurrences we're about to change, for the summary / dry-run.
slug_hits=$(grep -rlF "${OLD_SLUG}.md" "${FILES[@]}" 2>/dev/null | wc -l | tr -d ' ')
name_hits=$(grep -rlF "$OLD_NAME" "${FILES[@]}" 2>/dev/null | wc -l | tr -d ' ')

echo "rename ${CATEGORY}: ${OLD_SLUG}.md -> ${NEW_SLUG}.md   |   \"$OLD_NAME\" -> \"$NEW_NAME\""
echo "  page move : $PAGE -> $DEST"
echo "  link refs : $slug_hits file(s) contain ${OLD_SLUG}.md"
echo "  name refs : $name_hits file(s) contain \"$OLD_NAME\""

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry run: no changes made."
  exit 0
fi

# 1. Move the page (git mv when tracked, else plain mv).
if git ls-files --error-unmatch "$PAGE" >/dev/null 2>&1; then
  git mv "$PAGE" "$DEST"
else
  mv "$PAGE" "$DEST"
fi

# 2 + 3. Literal replacements across the doc set. Perl with \Q..\E keeps the
# match literal and values are passed via env to avoid any quoting pitfalls.
OLD_SLUG_MD="${OLD_SLUG}.md" NEW_SLUG_MD="${NEW_SLUG}.md" \
OLD_NAME="$OLD_NAME" NEW_NAME="$NEW_NAME" \
perl -i -pe '
  s/\Q$ENV{OLD_SLUG_MD}\E/$ENV{NEW_SLUG_MD}/g;
  s/\Q$ENV{OLD_NAME}\E/$ENV{NEW_NAME}/g;
' "${FILES[@]}"

echo "done."
echo
echo "Leftover mentions of the OLD name/slug (review — expected to be empty):"
grep -rnF -e "$OLD_NAME" -e "${OLD_SLUG}.md" "${FILES[@]}" || echo "  (none)"
echo
echo "Next: run  mkdocs build --strict  to confirm no links broke."
