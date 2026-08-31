# Session Summarizer — Dead Ridge, TN

## Task Description

This is the session summarizer for **Dead Ridge, TN**, a **The Walking Dead Universe Roleplaying Game (Free League)**
campaign (post-apocalyptic survival horror; Appalachian mountains, 2030; people are the real threat).
We play remotely and capture audio with OBS Studio, then transcribe with
Deepgram (diarization on) to get per-speaker transcripts.

I will provide:

- Previous session summaries (if available)
- The wiki with PC, NPC, faction, and location entries
- Raw materials from the latest session (transcript, DM notes, player notes)

Using the provided information, generate the following outputs in **Markdown**,
formatted for MkDocs Material.

---

## Output Required

### 1. Wiki Updates

Update or create entries in `docs/wiki/` organized by category:

#### Player Characters (`docs/wiki/pcs/`)
Update existing PC files with new information from this session — abilities used,
character development, relationships formed.

> **Portraits.** PC pages show a portrait automatically **if** an image named after
> the page slug exists at `docs/assets/pcs/<slug>.png` (or `.jpg`/`.jpeg`/`.webp`) —
> these are player-provided art, dropped in by hand. Do not generate or embed them;
> the `hooks/wiki_images.py` build hook renders them at the top of the page.

> **Character notes (PCs and NPCs alike).** Before writing or updating a PC or NPC
> page, check for a player-provided notes file at `docs/assets/pcs/<slug>.md` or
> `docs/assets/npcs/<slug>.md` — the **same slug** as the portrait. If one exists,
> treat it as **authoritative source material** for that character. It is often a
> rough, Google-Docs-pasted sheet (bold-wrapped headings like `## **Backstory**`,
> escaped `\!`, stray blank bullets, curly quotes) — **distill it, don't dump it**:
> - Fold **background + personality** into the page's `## Overview` prose, in the
>   site's voice.
> - Add an `## In Character` section (placed **after** `## Overview` and before any
>   per-arc sections / `## Session History`) carrying condensed **Ideals / Bonds /
>   Flaws** and 2–3 **signature sayings** as `>` blockquotes, sourced from the notes
>   file's sayings list.
> - If the notes file (or a known campaign fact) gives a **pronunciation**, surface it
>   as an italic gloss on its own line directly under the page H1, e.g.
>   `*(pronounced Prawnse)*`.
>
> These `.md` files are **source, not rendered pages** — the build excludes them via
> `exclude_docs` in `mkdocs.yml`. Do not link to them and do not paste their raw text.

#### NPCs (`docs/wiki/npcs/`)
For each NPC encountered (new or returning), create or update their file:

- **Name and role** (title, occupation, affiliation)
- **Appearance** and distinguishing traits
- **Personality** and behavior observed
- **Goals and motivations** (known or inferred)
- **Relationships** with PCs and other NPCs
- **Session history** — key interactions and developments

> **Portraits.** NPC pages show a portrait automatically **if** an image named after
> the page slug exists at `docs/assets/npcs/<slug>.png` (or `.jpg`/`.jpeg`/`.webp`) —
> these are user-provided art, dropped in by hand. Do not generate or embed them;
> the `hooks/wiki_images.py` build hook renders them at the top of the page.

> **Canonical names come from the portrait art, not the transcript.** Deepgram
> transcripts garble names — ASR writes what it hears, so a character whose art is
> `seris.png` comes through as "Cerus", and invented surnames get split, merged, or
> swapped for ordinary words that sound like them. The
> player-dropped filenames in `docs/assets/pcs/` and
> `docs/assets/npcs/` carry the **correct** spelling. So before finalizing any
> PC/NPC name: list those folders and, when a character plausibly matches an existing
> image filename (same person, phonetically or semantically), adopt the **image's**
> spelling for both the display name and the page slug, and name the page file to
> match the image basename so the portrait auto-wires. If an existing wiki page's name
> conflicts with newly-dropped art that clearly depicts the same character, prefer the
> image spelling and rename the page with
> `bin/rename-npc.sh <old-slug> <new-slug> "<Old Name>" "<New Name>"` (it does the
> `git mv` + rewrites every reference + updates the nav).

#### Factions (`docs/wiki/factions/`)
Update faction entries with new information about:
- Leadership and membership changes
- Goals and current activities
- Relationship changes with the party or other factions

#### Locations (`docs/wiki/locations/`)
For significant locations visited or mentioned:
- Description and notable features
- Who/what can be found there
- Events that occurred there

**Location image.** Each location page opens with a summary paragraph (the text
right after the `# Heading`). When you create a location page — or when
`docs/assets/locations/<slug>.png` does **not** already exist for an existing one —
generate an image from that summary:

```bash
set -a; source .env; set +a
python3 bin/gen-image.py \
  --prompt "<the location's summary paragraph>" \
  --out docs/assets/locations/<slug>.png \
  --size 1536x1024
```

`<slug>` is the page's filename without `.md` (e.g. `the-old-keep`). Do **not**
embed the image in the markdown — the `hooks/wiki_images.py` build hook renders any
`docs/assets/locations/<slug>.png` at the top of its page automatically. Skip
generation if the file already exists (avoids needless regeneration and cost). If
the generator exits non-zero, surface the error and continue without the image.

---

### 2. Session Summary

Create a session summary file in `docs/sessions/` named by date
(e.g., `2026-06-04.md`).

Structure as follows:

#### Overview
A 2-3 sentence summary of what happened this session.

#### Key Events
Detailed bullet points covering:
- Major decisions and their consequences
- Combat encounters and outcomes
- Discoveries (lore, secrets, items, clues)
- Significant character moments and roleplay

#### Memorable Moments
Highlight standout moments worth remembering:
- Creative problem-solving
- Great roleplay or dramatic scenes
- Exceptional bravery, skill, or resourcefulness
- Funny, unexpected, or cinematic moments

#### Open Threads
- Unresolved plot points and mysteries
- Promises made or debts owed
- Suggested next steps and story hooks

#### Dramatized Scene (Interactive)

After completing the summary, **suggest exactly 3 scenes** from the session that
could be dramatized as short prose. For each suggestion, provide:
- A short title
- A one-sentence description of the moment

**Wait for the user to choose one.** Then write a **3-paragraph dramatization**
of that scene — vivid, atmospheric prose that brings the moment to life. Include
sensory details, character voice, and tension.

**Generate a scene image.** Build an image prompt from the chosen scene — the
setting, the characters present (use their wiki/`world/world.md` descriptions for
appearance), and the mood. Load your keys once per shell, then run the generator:

```bash
set -a; source .env; set +a
python3 bin/gen-image.py \
  --prompt "<vivid one-paragraph description of the chosen scene>" \
  --out docs/assets/sessions/<DATE>.png \
  --size 1536x1024
```

The script appends the shared campaign art style automatically. If it exits non-zero
(e.g. `OPENAI_API_KEY` not set), surface the error and continue with the prose
only — do not embed a missing image.

Add the dramatized scene to the session summary under a `## The Scene` heading,
placed **as the very last section** of the file. Embed the image first, then the
prose:

```markdown
## The Scene

![<scene title>](../assets/sessions/<DATE>.png)

<the 3-paragraph dramatization>
```

---

### 3. Navigation Update

Add the new session to `mkdocs.yml` under the `Sessions:` nav entry.

**Session-title convention — numbered when listed, plain when alone.** Give each
session a short **thematic title** (e.g. "The Tidewoven Amulet"). Do **not** use a
"Session One —" style prefix.
- **When the title appears in a list** (the `mkdocs.yml` nav label, and via the `#`
  column of the `docs/index.md` table), it carries the session's **chapter number**.
  Nav label format: `"<N>. <Thematic Title>"`.
- **When the title stands alone** (the session page's frontmatter `title:` and its
  `# ` H1), show the thematic title **only** — no number, no prefix.

**Create the `Sessions:` and `Wiki:` nav sections if they are missing.** A freshly
scaffolded site starts with only `- Home: index.md` in its `nav:`. On the first run,
build out the structure — `Sessions:` right after Home, then `Wiki:` with the four
category subsections you actually created pages under:

```yaml
nav:
  - Home: index.md
  - Sessions:
      - "1. The First Session": sessions/2026-07-03.md
  - Wiki:
      - Player Characters:
          - wiki/pcs/<slug>.md
      - NPCs:
          - wiki/npcs/<slug>.md
      - Factions:
          - wiki/factions/<slug>.md
      - Locations:
          - wiki/locations/<slug>.md
```

On later runs the sections already exist — just add the new session under
`Sessions:` and any new wiki pages under their category. Do **not** create an empty
nav section (a heading with no children fails `mkdocs build --strict`); only add a
category subsection once it has at least one page.

Also add the session row to the table in `docs/index.md` — the `#` column holds the
chapter number and the link text is the thematic title only.

---

### 4. Cross-Linking

Use standard Markdown links to connect content:

- **Session files** → Link NPC names on first mention:
  `[The Enigmatic Ally](../wiki/npcs/the-enigmatic-ally.md)`
- **NPC files** → Cross-reference other NPCs, factions, and locations
- **Location files** → Link to NPCs found there and events that occurred

**Do NOT link PCs** — they appear too frequently and would create excessive links.

Use relative paths from the file's location. Keep link text natural:
`[the Ally](../wiki/npcs/the-enigmatic-ally.md)` reads better than the full title.

---

## Input Sources

### World Bible
`world/world.md` — the canonical setting reference: regions, havens, factions,
groups, and threats. Use it to keep names, places, and lore
consistent, and to place new NPCs/locations correctly in the world.

### Previous Sessions
Located in `docs/sessions/` — read for context and continuity.

### Wiki
Located in `docs/wiki/` — reference for existing characters, factions, and locations.

### Latest Session Materials
Located in `sessions-raw/[DATE]/`:
- `transcript.md` — Full session transcript
- `dm-notes.md` — GM's session notes and prep
- `*-notes.md` — Individual player notes (e.g., `braedon-notes.md`)

Find the newest date folder for the latest session.

### Participants

**Gary** is the **Game Master** — not a player, but their voice appears as
a speaker in the transcript (they voice all NPCs and narration).

| Player  | Character                      | Archetype           | Issue / Drive |
|---------|--------------------------------|---------------------|---------------|
| Ian     | Johnathan "JB" Banks           | Broker *(homebrew)* | Drive: get back to Wall Street — "I just gotta ring the bell" |
| Graycen | Ashley "Ash" Fairfax           | Nobody              | Issue: doesn't care if she lives · Drive: "Keeps going anyway" |
| Conner  | Dr. Charles "Chuck" Greenbriar | Scientist           | Drive: "I'm not crazy" |
| Cobie   | Clara "CJ" James               | Homemaker           | Issue: Bloodthirsty · Drive: take down as many as possible |

Matching speaker labels are in `README.md`. Note that in-person recordings on a
single room mic cannot be reliably diarized per player — see the README's
diarizer notes before trusting a `speaker-map.json`.

---

## Setting Context

The campaign is set in the world described in [`world/world.md`](world/world.md) —
the canonical bible for regions, havens, factions, groups, and threats.
Tone: **post-apocalyptic survival horror; Appalachian mountains, 2030; people are the real threat**. Read it before writing so names, places, and lore stay
consistent, and place any new NPCs and locations correctly within it.
