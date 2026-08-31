# Dead Ridge, TN

Session archive and campaign wiki for **Dead Ridge, TN** — a The Walking Dead Universe Roleplaying Game (Free League)
campaign (post-apocalyptic survival horror; Appalachian mountains, 2030; people are the real threat).

The site is built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/)
and published to GitHub Pages.

- **`docs/`** — the published site (sessions + wiki). Built by MkDocs.
- **`sessions-raw/`** — raw inputs per session (transcripts, notes). Not published.
- **`SESSION_SUMMARIZER.md`** — the prompt used to turn raw materials into the site.
- **`WORLD_PAGE.md`** — the prompt that builds the home page from `world/`.
- **`world/`** — the campaign bible (`world.md`) and world notes; source for the home
  page. Not published directly.
- **`bin/`** — helper scripts: `deepgram_async.py` (transcribe a session via S3 +
  Deepgram's async callback), `gen-image.py` (generate art via OpenAI), and
  `unpublish-session.sh` (remove a published session to republish it).

---

## The Process

```
OBS (record audio) → Deepgram (transcribe + diarize) → format transcript
   → sessions-raw/<DATE>/ → run SESSION_SUMMARIZER.md → commit → GitHub Pages
```

### 1. Record the audio (OBS Studio)

1. In OBS, open **Settings → Audio** and make sure your sources are captured:
   - **Mic/Aux** — your microphone (the DM).
   - **Desktop Audio** — the remote players coming through your voice app
     (Discord/etc.).
2. *(Recommended for cleaner speaker separation)* Enable multi-track recording:
   **Settings → Output → Output Mode: Advanced → Recording → Audio Track**, and
   assign each source to its own track. Use the **`.mkv`** container so multiple
   tracks are preserved (remux to `.mp4` later if needed).
3. Click **Start Recording** before play, **Stop Recording** after.
4. Find the file under your configured **Recording Path**.

> Deepgram accepts common audio/video formats (`wav`, `flac`, `mp3`, `m4a`,
> `mkv`, `mp4`, …), so you can usually upload the OBS file directly. If you
> recorded multi-track and want a single mix, export/remux to a `.wav` first.

> If you recorded **multi-track** (one track per speaker), you can instead
> transcribe each track separately *without* diarization — the speaker is known
> per track — and merge by timestamp. Diarization on a single mix is the simpler
> default, and is what the rest of this README assumes.

### 2. Transcribe with Deepgram (diarization on)

Send the recording to Deepgram with **diarization** and **utterances** enabled.
Diarization separates speakers (Speaker 0, Speaker 1, …); utterances give you
timestamped, speaker-tagged segments that map cleanly to the transcript format.

First, set your Deepgram API key. Copy `.env.example` to `.env`, fill in your
key, then load it into the shell (`.env` is git-ignored, so your key stays out
of the repo):

```bash
cp .env.example .env      # then edit .env and set DEEPGRAM_API_KEY (and OPENAI_API_KEY)
set -a; source .env; set +a
```

> `.env` also holds `OPENAI_API_KEY`, used by `bin/gen-image.py` to generate the
> scene, location, and home-hero art (via OpenAI `gpt-image-1` — your org must be
> verified for that model). The summarizer and `WORLD_PAGE.md` call it for you;
> load the key the same way before running them.

**Large video files (extract the audio first).** Deepgram caps pre-recorded
uploads at **2 GB**. A screen/video recording is almost entirely video — strip
it and upload audio only. Copying the existing audio stream is instant and
lossless (needs [`ffmpeg`](https://ffmpeg.org/); on WSL/Ubuntu:
`sudo apt install -y ffmpeg`):

```bash
ffmpeg -i session.mp4 -vn -acodec copy session.m4a   # drops video, keeps audio as-is
```

If that errors on the codec, re-encode instead — for speech-to-text, downmixing
to 16 kHz mono is lossless in practice and yields a tiny file:

```bash
ffmpeg -i session.mp4 -vn -ac 1 -ar 16000 -c:a flac session.flac
```

Then run the transcribe step below on the extracted audio (`Content-Type:
audio/mp4` for `.m4a`, `audio/flac` for `.flac`). Check `ls -lh` to confirm it's
under the 2 GB cap.

> **The easy path for long sessions: `bin/deepgram_async.py`.** It hosts the audio
> in a private S3 bucket, hands Deepgram a presigned URL, and has Deepgram `PUT`
> the finished JSON straight back into the bucket via Deepgram's **async
> callback** — so nothing can time out mid-job. One command replaces this whole
> section:
>
> ```bash
> pip install -r requirements-dev.txt         # boto3 + requests, once
> set -a; source .env; set +a
> python3 bin/deepgram_async.py sessions-raw/<DATE>/session.m4a
> ```
>
> It polls until the result lands and writes `sessions-raw/<DATE>/session.deepgram.json`
> for you. One-time AWS setup (bucket + least-privileged IAM user) is in
> **[`DEEPGRAM_AWS.md`](DEEPGRAM_AWS.md)**; the `translate-deepgram` skill runs this
> for you. The manual `curl` recipes below are the fallback.

**Choosing the diarizer (`diarize_model`).** The `diarize_model` query param
selects which speaker-separation model runs. Two values are worth knowing:

| Value                   | Model         | Notes |
|-------------------------|---------------|-------|
| `diarize_model=v1`      | original (v1) | The stable, faster diarizer. |
| `diarize_model=latest`  | newest        | Deepgram's current diarizer. Slower. |

> Passing `diarize_model` **implies diarization is on** — you do **not** also need
> `diarize=true` (and the deprecated `diarize=true` alone pins to **v1**). Set the
> model explicitly instead.

> **Prefer `v1` as the default.** On a ~3 hr single-mix session with five speakers,
> `latest` did *not* separate speakers better: it reported one more speaker than
> `v1`, but the extra "speaker" was ~30 s of scattered noise (53 words), and it
> actually folded more of one real speaker's lines into another. It's also slower,
> which can push a large single upload past Deepgram's sync **gateway timeout**
> (use `bin/deepgram_async.py` for very long files — see
> **[`DEEPGRAM_AWS.md`](DEEPGRAM_AWS.md)**). Start with `v1`; only try `latest` if
> v1 is visibly mis-splitting *your* recording.

> **Exception — in-person recordings on one room mic.** The finding above holds
> for the usual remote setup, where OBS captures a reasonably clean per-voice mix.
> Session zero (2026-08-30) was recorded in person on a **phone** sitting on the
> table, and there `v1` was clearly worse: five people collapsed into **three**
> speaker buckets, with several speakers merged inside a single utterance.
> `latest` produced four buckets and a more plausible distribution. Neither model
> can properly separate a room mic — expect to attribute lines by **content**
> (who names their own character, gear, or anchor) rather than trusting the
> diarization, and don't fabricate a per-player `speaker-map.json` that the audio
> can't support.

For a `.wav`/`.m4a` recording:

```bash
curl --request POST \
  --url 'https://api.deepgram.com/v1/listen?model=nova-3&diarize_model=v1&punctuate=true&smart_format=true&utterances=true' \
  --header "Authorization: Token $DEEPGRAM_API_KEY" \
  --header 'Content-Type: audio/mp4' \
  --data-binary @session.m4a \
  > session.deepgram.json
```

For an `.mp4` recording — change the `Content-Type` header and the file, and use
`-T` (stream from disk) instead of `--data-binary` (which buffers the whole file
into memory and fails with `out of memory` on large recordings). Deepgram
extracts the audio track automatically, so there's no need to demux to `.wav`
first:

```bash
curl --request POST \
  --url 'https://api.deepgram.com/v1/listen?model=nova-3&diarize_model=v1&punctuate=true&smart_format=true&utterances=true' \
  --header "Authorization: Token $DEEPGRAM_API_KEY" \
  --header 'Content-Type: video/mp4' \
  -T session.mp4 \
  > session.deepgram.json
```

> `-T` streams the upload from disk, so memory stays flat regardless of file
> size — prefer it over `--data-binary @file` for any large recording. Keep
> `--request POST`; `-T` alone defaults to PUT, which Deepgram rejects.

> Match the `Content-Type` to your file's container: `audio/wav`, `audio/flac`,
> `audio/mpeg` (`.mp3`), `audio/mp4` (`.m4a`), `video/mp4` (`.mp4`), etc.

### 3. Format the transcript

Convert Deepgram's `utterances` into the `transcript.md` format the summarizer
expects: a per-line `MM:SS <Player> as <Character>:` (or `<Player> the DM:` for
the DM), e.g.

```text
00:00 Gary the DM: The little boy crept into the silver shop...
00:15 Gary the DM: In the interrogation you learn he was being paid by the ruling family.
01:58 <Player> as <Character>: Wait — how much money are we talking?
02:01 Gary the DM: A pretty good sum.
```

Speaker labels for this campaign:

| Player  | Character                      | Archetype           | Label to use |
|---------|--------------------------------|---------------------|--------------|
| Gary    | — (Game Master)                | —                   | `Gary the DM` |
| Ian     | Johnathan "JB" Banks           | Broker *(homebrew)* | `Ian as Banks` |
| Graycen | Ashley "Ash" Fairfax           | Nobody              | `Graycen as Ash` |
| Conner  | Dr. Charles "Chuck" Greenbriar | Scientist           | `Conner as Chuck` |
| Cobie   | Clara "CJ" James               | Homemaker           | `Cobie as CJ` |

Deepgram assigns speaker **numbers**, not names, and **the numbering changes with
every conversion** — speaker 0 is not the same person from one session to the
next. So the mapping has to be rebuilt each time.

**The easy way — two Claude Code skills:**

- **"build speaker mapping"** inspects `session.deepgram.json` (who talks most,
  who says which character's name, who answers when the DM calls a name), proposes
  a number → person mapping with its reasoning, and lets you correct it. It saves
  the result to `sessions-raw/<DATE>/speaker-map.json`.
- **"translate deepgram"** then applies that map with the `jq` below and writes
  `sessions-raw/<DATE>/transcript.md`.

**The manual way.** Listen to a few lines to learn which number is whom, then run
the `jq` yourself — it formats the JSON and substitutes names in one pass (edit the
`map` to match this recording's speaker numbers):

```bash
jq -r --argjson map '{
  "0":"Gary the DM"
}' '
  def p2: tostring | if length < 2 then "0" + . else . end;
  .results.utterances[]
  | (.start|floor) as $t
  | "\(($t/60|floor)|p2):\(($t%60)|p2) \($map[(.speaker|tostring)] // "Speaker \(.speaker)"): \(.transcript)"
' session.deepgram.json > transcript.md
```

Any speaker number missing from the `map` falls through to a literal
`Speaker <N>` label — a useful escape hatch when a voice can't be identified, but
fix it before summarizing.

### 4. Drop the materials into `sessions-raw/<DATE>/`

```
sessions-raw/2026-06-04/
  transcript.md       # required — formatted above
  dm-notes.md         # optional — GM prep / notes
  <player>-notes.md   # optional — e.g. matt-notes.md
```

The summarizer treats the **newest** date folder as the latest session.

### 5. Generate the site content

Run the prompt in [`SESSION_SUMMARIZER.md`](SESSION_SUMMARIZER.md). It reads the
newest `sessions-raw/<DATE>/`, the existing `docs/`, and `world/world.md`, then:

- updates/creates wiki entries under `docs/wiki/{pcs,npcs,factions,locations}/`
  (generating a location image for each new location into `docs/assets/locations/`),
- writes the session summary to `docs/sessions/<DATE>.md`, ending with a
  **dramatized scene** (you pick 1 of 3) plus a generated image in
  `docs/assets/sessions/<DATE>.png`,
- updates the nav in `mkdocs.yml` and the table in `docs/index.md`.

**PC and NPC portraits** are player-provided: drop an image at
`docs/assets/pcs/<slug>.png` or `docs/assets/npcs/<slug>.png` (named after the
character's page) and it renders on that page automatically — no prompt needed.

**Home page.** To (re)build the landing page from the world bible, run the
[`WORLD_PAGE.md`](WORLD_PAGE.md) prompt. It reads everything in `world/`, rewrites
the body of `docs/index.md`, and generates `docs/assets/home-hero.png`.

**Republishing a session.** To redo an already-published session after edits,
remove it first, then re-run the summarizer:

```bash
bin/unpublish-session.sh <DATE>   # removes the session page, its image, nav + index row
```

It leaves `sessions-raw/<DATE>/` and the wiki untouched.

**Shortcut — Claude Code skills.** This repo ships project-local skills so you can
drive the steps by name instead of opening the prompts. In Claude Code, just say:

- **"build speaker mapping"** → works out which Deepgram speaker number is whom and
  saves `sessions-raw/<DATE>/speaker-map.json` (step 3).
- **"translate deepgram"** → applies that map and writes `transcript.md` (step 3).
- **"summarize latest session"** → runs the `SESSION_SUMMARIZER.md` process.
- **"build world data"** → runs the `WORLD_PAGE.md` process (rebuilds the home page).
- **"publish site"** → build-checks, commits, and pushes to `main` (deploys — step 7).

They live in `.claude/skills/` and are available only in this project. Recording and
transcription themselves (OBS / `ffmpeg` / the Deepgram request) stay manual — see
above.

### 6. Preview locally (optional)

```bash
pip install -r requirements.txt
mkdocs serve     # http://127.0.0.1:8000
```

### 7. Publish

Commit and push to **`main`**. The
[`deploy-docs`](.github/workflows/deploy-docs.yml) GitHub Action runs
`mkdocs gh-deploy --force`, building the site and publishing it to the
**`gh-pages`** branch at
<https://argvader.github.io/dead_ridge_tn/>.

```bash
git add docs mkdocs.yml
git commit -m "publish session <DATE>"
git push origin main
```

> **First publish — enable Pages.** On the repo's GitHub **Settings → Pages**, set
> the source to the **`gh-pages`** branch (the Action creates it on first deploy).
