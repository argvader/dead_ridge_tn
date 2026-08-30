---
name: build-speaker-mapping
description: >-
  Work out which Deepgram speaker number is which person for a Dead Ridge, TN
  recording, and save it to sessions-raw/<DATE>/speaker-map.json. Use when the user says
  "build speaker mapping", "map the speakers", "who is speaker 3", or is about to turn a
  session.deepgram.json into a transcript. Diarization numbers change with every
  conversion, so this must be re-run for each recording. Produces the map that the
  translate-deepgram skill consumes.
---

# Build the speaker mapping

Deepgram labels speakers as bare numbers (`0`, `1`, `2`, …), and **the numbering changes
with every conversion** — speaker 0 is not the same person from one session to the next.
This skill inspects a `session.deepgram.json`, proposes a mapping from those numbers to
real people, lets the user correct it, and saves the result for **translate-deepgram**.

Make a *well-evidenced proposal*, not a silent guess. A swapped pair of players
mislabels the whole transcript, and the summarizer then builds wiki pages on top of it.
You gather evidence; the user arbitrates.

## The cast

Expected speakers: **1** — Gary plus the player roster.

| Deepgram speaker | Label to use |
|------------------|--------------|
| (the DM's voice) | `Gary the DM` |

## Steps

### 1. Find the transcript JSON

Use the path the user gave. Otherwise look for `session.deepgram.json` in the repo root
or in the newest `sessions-raw/<DATE>/`. Check it has utterances:

```bash
jq '.results.utterances | length' session.deepgram.json
```

`null` means the file was produced without `utterances=true` — **stop** and tell the user
to re-run Deepgram with that flag (`README.md` step 2). No mapping is recoverable from a
`channels`-only response.

### 2. Take a speaker census

How many speakers Deepgram found, and how much each one talks:

```bash
jq -r '
  .results.utterances
  | group_by(.speaker)
  | map({ speaker:    .[0].speaker,
          utterances: length,
          words:      (map(.transcript | split(" ") | length) | add),
          talk_time:  (map(.end - .start) | add | floor),
          first_at:   (map(.start) | min | floor) })
  | sort_by(-.talk_time)[]
  | "speaker \(.speaker): \(.utterances) utts, \(.words) words, \(.talk_time)s talking, first at \(.first_at)s"
' session.deepgram.json
```

Compare the count found against the **1** expected:

- **Same count** — a straight assignment problem.
- **More speakers than people** — diarization over-split someone (a mic-volume shift or
  crosstalk usually does it). Recoverable: the jq map allows **many→one**, so two numbers
  can carry the same label. Flag any speaker with negligible talk time — under ~1% of the
  session is usually noise or a stray split.
- **Fewer speakers than people** — two people were merged into one number, or someone was
  quiet. A mapping **cannot** un-merge them. Say so plainly rather than papering over it
  with a label; the fix is re-running with `diarize_model=latest` (`README.md` §2,
  `DEEPGRAM_AWS.md` Tier 2), and it's the user's call whether that's worth it.

### 3. Gather evidence

Sample each speaker — the longest utterances are the most diagnostic:

```bash
jq -r '
  .results.utterances
  | group_by(.speaker)[]
  | (.[0].speaker) as $s
  | sort_by(-(.transcript | length))[:5][]
  | "[\($s)] \(.transcript[:200])"
' session.deepgram.json
```

Tally who says each character's name — the DM says everyone's, players rarely say their
own:

```bash
jq -r --argjson names '[]' '
  .results.utterances
  | group_by(.speaker)[]
  | (.[0].speaker) as $s
  | . as $utts
  | [ $names[]
      | . as $n
      | { name: $n,
          count: ($utts | map(select(.transcript | ascii_downcase | contains($n | ascii_downcase))) | length) } ]
  | (map(select(.count > 0) | "\(.name)=\(.count)") | join(", ")) as $hits
  | "speaker \($s): " + (if $hits == "" then "(names no one)" else $hits end)
' session.deepgram.json
```

A speaker who names **everyone** is almost certainly the DM. A speaker who names
*no one* is a normal player — people rarely say their own character's name.

Then the strongest single signal — when the DM addresses a character, whoever talks
**next** is usually that character's player. Substitute the DM's number for `--argjson dm`
once step 2 has made it obvious:

```bash
jq -r --argjson dm 0 --argjson names '[]' '
  [.results.utterances[] | { speaker, t: (.transcript | ascii_downcase) }] as $u
  | range(0; ($u | length) - 1) as $i
  | select($u[$i].speaker == $dm)
  | $names[]
  | . as $n
  | select($u[$i].t | test("\\b" + ($n | ascii_downcase) + "\\b"))
  | "\($n) -> speaker \($u[$i + 1].speaker)"
' session.deepgram.json | sort | uniq -c | sort -rn
```

### 4. Reason to a proposal

Weigh the signals together; no single one is conclusive.

- **The DM** is nearly always the top speaker by talk time and word count, usually by a
  wide margin — they narrate and voice every NPC. Their lines skew second-person and
  procedural: "you see", "roll for", "make a … check", "DC", "what do you do". They name
  the most distinct characters, and they open the session.
- **Players** speak in the first person about one character ("I attack", "Fizz goes for
  the door"), react rather than narrate, and ask rules questions. Pin each to a character
  with the addressing tally above, plus self-reference and who the DM replies to.

Attach a **confidence** to every row — the low-confidence ones are exactly where a mapping
goes wrong, and the user needs to know which to check.

If a speaker genuinely can't be identified, **leave them out of the map**. Do not invent a
name: the jq falls back to `Speaker <N>`, which is honest and easy to fix later.

### 5. Show the user, and let them edit

Present the proposal as a table — speaker number, proposed label, the evidence, the
confidence — and call out anything odd from step 2 (extra or missing speakers, a silent
participant). Then ask for corrections and apply them. Swapping two players is the common
fix; expect it and make it painless. Iterate until the user is happy — **never move on
from an unconfirmed mapping.**

Labels must match the format the summarizer expects:

- DM → `Gary the DM`
- Player → `<Player> as <Character>`

### 6. Save the map

Write the confirmed mapping to `sessions-raw/<DATE>/speaker-map.json`, alongside that
session's other raw inputs (create the dated folder if it doesn't exist; use the
**session's** date, not today's, if they differ).

Keep it a bare JSON object of string keys → labels — no comments, no wrapper key. It is
passed straight to `jq --argjson`, and any extra structure breaks it:

```json
{
  "0": "Gary the DM",
  "1": "<Player> as <Character>"
}
```

Then point the user at the **translate-deepgram** skill, which applies this map and writes
`transcript.md`.

> A mapping only *renames* speakers — it cannot fix bad diarization. If the samples show
> one number that clearly contains two different people, the mapping isn't the problem.
> Say so.
