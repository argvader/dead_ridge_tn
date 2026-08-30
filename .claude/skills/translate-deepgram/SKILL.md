---
name: translate-deepgram
description: >-
  Turn a session's audio into the transcript.md the Dead Ridge, TN summarizer expects:
  transcribe with Deepgram (async S3 flow) into session.deepgram.json if it's missing,
  then apply the speaker map from sessions-raw/<DATE>/speaker-map.json. Use when the user
  says "translate deepgram", "convert the deepgram json", "make the transcript", or
  similar. The conversion step still requires a speaker map — build-speaker-mapping first.
---

# Translate a session into a transcript

Transcribes the session audio with Deepgram (if not already done), then applies a
confirmed speaker mapping to Deepgram's `utterances` and writes the
`MM:SS <Label>: <text>` transcript that **summarize-session** reads.

The full pipeline has a **mandatory manual checkpoint** in the middle:

```
audio → [step 0: async transcribe] → session.deepgram.json
      → [build-speaker-mapping]     → speaker-map.json   ← verify/adjust by hand
      → [steps 1–3: convert]        → transcript.md
```

Step 0 produces the JSON, then **this skill stops.** Diarization numbers change with
every transcription, so the speaker map has to be built against this session's fresh
JSON and eyeballed by a human before any transcript is written. Do not carry on to
the conversion in the same run as generating the JSON.

## Steps

### 0. Ensure the Deepgram JSON exists (async transcription)

Find the session: the date the user named, else the newest `sessions-raw/<DATE>/`.

Check for a valid `sessions-raw/<DATE>/session.deepgram.json`:

```bash
jq empty sessions-raw/<DATE>/session.deepgram.json 2>/dev/null && echo "JSON present" || echo "need to transcribe"
```

**If it's present and valid, skip to step 1** — the map has presumably been built and
verified since it was generated.

If it's missing (or is a stale error like `{"err_code":"Gateway Timeout",...}`),
transcribe the session audio with the async S3 flow. Load credentials, then run the
script on the audio file in the dated folder (`.m4a`, `.flac`, `.wav`, or `.mp4`):

```bash
set -a; source .env; set +a
python3 bin/deepgram_async.py sessions-raw/<DATE>/session.m4a
```

This uploads the audio to the private `dead-ridge-tn-deepgram` S3 bucket, has Deepgram
`PUT` the finished transcript straight back to S3, and downloads it to
`sessions-raw/<DATE>/session.deepgram.json`. It waits and polls until the result
lands (a multi-hour file can take many minutes). Add `--diarize-model latest` only
if `v1` is visibly mis-splitting speakers (see the README finding).

Prerequisites for this step (see [`DEEPGRAM_AWS.md`](DEEPGRAM_AWS.md)):
`pip install -r requirements-dev.txt`, and `.env` holding `DEEPGRAM_API_KEY` plus the
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_DEFAULT_REGION` for the
`dead-ridge-tn-deepgram-bot` IAM user. If those aren't set up, stop and point the user at
`DEEPGRAM_AWS.md` rather than guessing.

**Then STOP.** Once `session.deepgram.json` exists, hand off — do not continue to
step 1 in this run:

> Transcript is in `sessions-raw/<DATE>/session.deepgram.json`. Next, run the
> **build-speaker-mapping** skill, then **verify and adjust
> `sessions-raw/<DATE>/speaker-map.json` by hand**. Re-run **translate-deepgram**
> once the map looks right and it will finish the conversion.

### 1. Load the speaker map

Find the session: the date the user named, else the newest `sessions-raw/<DATE>/`. The map
lives at `sessions-raw/<DATE>/speaker-map.json`.

**If it isn't there, stop.** Tell the user to run the **build-speaker-mapping** skill
first — the numbers Deepgram assigns change with every conversion, so a map from another
session is worthless and a guessed one silently mislabels the whole transcript. Do not
fabricate one.

If it is there, check it survived any hand-editing, and show it so the user can see what's
about to be applied:

```bash
jq empty sessions-raw/<DATE>/speaker-map.json && cat sessions-raw/<DATE>/speaker-map.json
```

A parse error means a bad manual edit (usually a trailing comma) — report it and offer to
fix.

### 2. Run the conversion

Locate the `session.deepgram.json` (repo root, or inside the dated folder), then:

```bash
jq -r --argjson map "$(cat sessions-raw/<DATE>/speaker-map.json)" '
  def p2: tostring | if length < 2 then "0" + . else . end;
  .results.utterances[]
  | (.start|floor) as $t
  | "\(($t/60|floor)|p2):\(($t%60)|p2) \($map[(.speaker|tostring)] // "Speaker \(.speaker)"): \(.transcript)"
' session.deepgram.json > sessions-raw/<DATE>/transcript.md
```

If `sessions-raw/<DATE>/transcript.md` already exists, confirm with the user before
overwriting it — it may carry hand-corrections.

### 3. Check the output

Don't assume it worked; look:

```bash
wc -l sessions-raw/<DATE>/transcript.md
head -5 sessions-raw/<DATE>/transcript.md
grep -c '^[0-9][0-9]*:[0-9][0-9] Speaker [0-9]' sessions-raw/<DATE>/transcript.md
sed -E 's/^[0-9]+:[0-9]+ ([^:]+):.*/\1/' sessions-raw/<DATE>/transcript.md | sort | uniq -c | sort -rn
```

- The **per-label line counts** should look like a session at the table: the DM well
  ahead, every player present. A missing or wildly over-represented name means the map is
  wrong, not the transcript.
- A nonzero **`Speaker <N>`** count means that number wasn't in the map. Report it —
  don't quietly leave it in the transcript the summarizer will read. Offer to re-run
  **build-speaker-mapping** to name them.
- Show the user the first few lines so they can eyeball the format.

### 4. Next step

With `sessions-raw/<DATE>/transcript.md` in place (plus any optional `dm-notes.md` /
`<player>-notes.md`), the session is ready for the **summarize-session** skill.
