#!/usr/bin/env bash
#
# normalize-asset-names.sh [--dry-run]
#
# Normalize image filenames under the PC and NPC asset folders so they are
# lowercase with spaces replaced by hyphens:
#
#   docs/assets/pcs/*
#   docs/assets/npcs/*
#
# e.g. "Barundin ashvein.png" -> "barundin-ashvein.png"
#
# Uses `git mv` when the file is tracked (preserving history) and falls back to
# a plain `mv` otherwise. Pass --dry-run to preview the renames without touching
# anything.
#
# Usage:
#   bin/normalize-asset-names.sh
#   bin/normalize-asset-names.sh --dry-run

set -euo pipefail

# Run from the repo root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
elif [[ -n "${1:-}" ]]; then
  echo "usage: bin/normalize-asset-names.sh [--dry-run]" >&2
  exit 1
fi

DIRS=("docs/assets/pcs" "docs/assets/npcs")

renamed=0
skipped=0

for dir in "${DIRS[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "normalize-asset-names: no such directory '$dir' — skipping." >&2
    continue
  fi

  # Only image files, only at the top level of each asset folder.
  while IFS= read -r -d '' src; do
    name="$(basename "$src")"
    # lowercase, then spaces -> hyphens
    newname="${name,,}"
    newname="${newname// /-}"

    if [[ "$name" == "$newname" ]]; then
      continue
    fi

    dest="$dir/$newname"

    # A target that exists AND is a genuinely different file is a real
    # conflict. On case-insensitive filesystems (e.g. Windows drives under
    # WSL) a case-only rename makes `dest` resolve to `src` itself — that is
    # not a conflict, so only skip when they are different files.
    if [[ -e "$dest" && ! "$src" -ef "$dest" ]]; then
      echo "normalize-asset-names: target exists, skipping: $dest" >&2
      skipped=$((skipped + 1))
      continue
    fi

    echo "  $src -> $dest"

    if [[ "$DRY_RUN" -eq 0 ]]; then
      if git ls-files --error-unmatch "$src" >/dev/null 2>&1; then
        git mv "$src" "$dest"
      elif [[ "$src" -ef "$dest" ]]; then
        # Case-only rename on a case-insensitive FS: go via a temp name so
        # `mv` does not refuse "the same file".
        tmp="$dir/.rename-tmp-$$-$RANDOM"
        mv "$src" "$tmp"
        mv "$tmp" "$dest"
      else
        mv "$src" "$dest"
      fi
    fi
    renamed=$((renamed + 1))
  done < <(find "$dir" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.svg' \) -print0)
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry run: $renamed file(s) would be renamed, $skipped skipped."
else
  echo "done: $renamed file(s) renamed, $skipped skipped."
fi
