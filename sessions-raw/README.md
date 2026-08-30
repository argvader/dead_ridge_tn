# Raw Session Materials

Drop the inputs for each session into a dated folder here, then run the
summarizer (see `../SESSION_SUMMARIZER.md`). The summarizer reads the **newest**
date folder as the latest session.

```
sessions-raw/
  2026-06-04/
    transcript.md      # full session transcript (Deepgram diarized output)
    speaker-map.json   # Deepgram speaker number -> person, for this recording
    dm-notes.md        # GM session notes and prep (optional)
    <player>-notes.md  # individual player notes, e.g. braedon-notes.md (optional)
```

`speaker-map.json` is written by the **build-speaker-mapping** skill and consumed by
**translate-deepgram**, which produces `transcript.md`. It is kept per session because
Deepgram's speaker numbering changes with every conversion — the map from one session
does not apply to the next.

These files are **inputs only** — they are not published to the site (only
`docs/` is built by MkDocs).
