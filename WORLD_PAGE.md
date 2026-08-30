# World Page Builder — Dead Ridge, TN

## Task Description

This prompt builds the **home page** of the *Dead Ridge, TN* site — the root
landing page at `docs/index.md`. It reads the campaign's world sources and turns
them into an evocative, well-linked introduction to the setting, then generates a
hero image for the top of the page.

Run this whenever the world bible or its notes change, or when you want to refresh
the home page. It is separate from `SESSION_SUMMARIZER.md` (which handles sessions
and the wiki).

---

## Input Sources

### World Folder
Read **every** `.md` file in `world/`:

- `world/world.md` — the canonical campaign bible (regions, havens, factions,
  groups, threats, and where the survivors are based).
- `world/*-notes.md` (optional) — any supplementary world notes. Fold their content
  into the page where relevant; do not list them separately.

### Existing Home Page
`docs/index.md` — read it first. It already contains a `## Sessions` table that is
maintained by `SESSION_SUMMARIZER.md`. **Preserve that table exactly** — this prompt
only rewrites the narrative body above it.

### Wiki
`docs/wiki/` — use it to cross-link. When the body mentions a location, NPC, or
faction that has a wiki page, link to it. Do **not** link to a page that doesn't
exist yet (a broken link fails `mkdocs build --strict`).

---

## Output Required

Rewrite `docs/index.md` with the following structure:

1. **Frontmatter** — keep it as:
   ```yaml
   ---
   title: "Home"
   ---
   ```

2. **Hero image** — generate one (see below) and embed it at the very top of the
   body, right under the `# Dead Ridge, TN` H1:
   ```markdown
   ![Dead Ridge, TN](assets/home-hero.png){ .home-hero }
   ```

3. **Introduction** — 2–3 short paragraphs welcoming the reader to the world and
   the campaign's starting location. Set the tone (post-apocalyptic survival horror; Appalachian mountains, 2030; people are the real threat) drawn from
   `world/world.md`.

4. **Curated sections** — a handful of `##` sections drawn from the world sources,
   each 1–2 tight paragraphs: the defining event or tension of the setting, the
   party's home region, and the wider world / major powers. Link a location, faction,
   or NPC to its wiki page on first mention (only if that page exists).

   Keep it a **landing page**, not a copy of the bible — invite the reader in and
   link out to the wiki and sessions for depth.

5. **Sessions** — keep the existing `## Sessions` heading and its table at the very
   bottom, unchanged.

---

## Hero Image

Before writing the file, generate the hero image. First load your keys (once per
shell), then run the generator with a prompt built from the setting's defining
place or vista (draw the specifics from `world/world.md`):

```bash
set -a; source .env; set +a
python3 bin/gen-image.py \
  --prompt "<a sweeping establishing vista of the campaign's world / starting location, drawn from world/world.md>" \
  --out docs/assets/home-hero.png \
  --size 1536x1024
```

The script appends the shared campaign art style automatically. If it exits non-zero
(e.g. `OPENAI_API_KEY` not set), surface the error and stop — do not embed a
missing image. The `.home-hero` class is styled in `docs/stylesheets/extra.css`.

---

## Notes

- Do **not** modify `mkdocs.yml`, the wiki, or session files — only `docs/index.md`
  and the generated `docs/assets/home-hero.png`.
- Keep names, places, and lore consistent with `world/world.md`.
- Preview with `mkdocs serve`, then commit `docs/` to publish (see `README.md`).
