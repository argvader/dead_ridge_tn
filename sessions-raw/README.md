# Raw Session Materials

Drop the inputs for each session into a dated folder here, then run the
summarizer (see `../SESSION_SUMMARIZER.md`). The summarizer reads the **newest**
date folder as the latest session.

```
sessions-raw/
  2026-06-04/
    transcript.md      # full session transcript (Deepgram diarized output) — optional
    speaker-map.json   # Deepgram speaker number -> person, for this recording
    Session Notes.md   # GM's written account of the session (optional)
    dm-notes.md        # GM session notes and prep (optional)
    <player>-notes.md  # individual player notes, e.g. braedon-notes.md (optional)
    *-handout.md       # handouts given at the table (optional)
    title.png          # title card, rendered at the top of the session page (optional)
```

**Every `.md` in the folder except `transcript.md` is treated as notes** — you do
not have to match a filename, just drop the file in. At least one text source
(transcript or notes) must be present.

**No recording?** That's fine. When the audio fails, written notes alone are
enough — the summarizer treats them as the authoritative record and produces the
same session page. See "When there is no transcript" in `../SESSION_SUMMARIZER.md`.

**`title.png`** is user-made title art. The summarizer copies it to
`docs/assets/sessions/<DATE>-title.png` and the `hooks/wiki_images.py` build hook
renders it above the session page's heading. `.jpg`/`.jpeg`/`.webp` work too.

`speaker-map.json` is written by the **build-speaker-mapping** skill and consumed by
**translate-deepgram**, which produces `transcript.md`. It is kept per session because
Deepgram's speaker numbering changes with every conversion — the map from one session
does not apply to the next.

These files are **inputs only** — they are not published to the site (only
`docs/` is built by MkDocs).
