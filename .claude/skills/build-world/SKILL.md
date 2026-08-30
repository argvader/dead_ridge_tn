---
name: build-world
description: >-
  Rebuild the Dead Ridge, TN home page (docs/index.md) from the world/ folder. Use
  when the user says "build world data", "build the world page", "rebuild the home
  page", or similar. Reads world/world.md and any world notes and follows the
  WORLD_PAGE.md prompt to regenerate the landing-page body and hero image.
---

# Build the world / home page

Regenerate the site's landing page from the campaign's world sources.

## Steps

1. **Load API keys** (needed for the hero image):

   ```bash
   set -a; source .env; set +a
   ```

2. **Read `WORLD_PAGE.md`** at the repo root and **follow it exactly.** It is the
   canonical prompt and single source of truth. It will:
   - read **all** `.md` files in `world/` (`world.md` + any `*-notes.md`),
   - rewrite the body of `docs/index.md` with an evocative intro + curated sections
     linking into the wiki, **preserving** the existing `## Sessions` table at the
     bottom,
   - generate `docs/assets/home-hero.png` via `bin/gen-image.py` and place it at the
     top of the page.

3. When done, remind the user they can preview with `mkdocs serve` and publish with
   the **publish-site** skill.
