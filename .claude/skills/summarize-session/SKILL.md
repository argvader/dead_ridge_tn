---
name: summarize-session
description: >-
  Turn the latest recorded Dead Ridge, TN session into site content. Use when the
  user says "summarize latest session", "summarize the session", "run the session
  summarizer", or similar. Reads the newest sessions-raw/<DATE>/ and follows the
  SESSION_SUMMARIZER.md prompt to write the session summary, wiki updates, scene and
  location images, and nav/index updates.
---

# Summarize the latest session

Run the project's session summarizer over the newest raw session.

## Steps

1. **Load API keys** (needed for scene + location image generation):

   ```bash
   set -a; source .env; set +a
   ```

2. **Find the newest session** — the most recent date folder under
   `sessions-raw/<DATE>/` (it holds `transcript.md` and optional notes).

3. **Read `SESSION_SUMMARIZER.md`** at the repo root and **follow it exactly.** It is
   the canonical prompt and single source of truth — do not paraphrase or skip steps.
   It will:
   - update/create wiki entries under `docs/wiki/{pcs,npcs,factions,locations}/`
     (generating a location image from each new location's summary via
     `bin/gen-image.py`),
   - write the session summary to `docs/sessions/<DATE>.md`, including the interactive
     **3-scene** pick and a generated scene image + `## The Scene` at the bottom,
   - update the nav in `mkdocs.yml` and the table in `docs/index.md`.

4. When done, remind the user they can preview with `mkdocs serve` and publish with
   the **publish-site** skill.

> This skill starts from an existing `sessions-raw/<DATE>/transcript.md`. It does **not**
> cover recording or the Deepgram request (OBS / ffmpeg / curl) — those stay manual per
> `README.md`. To turn a `session.deepgram.json` into that transcript, use the
> **build-speaker-mapping** and **translate-deepgram** skills first.
>
> To redo an already-published session, first run `bin/unpublish-session.sh <DATE>`.
