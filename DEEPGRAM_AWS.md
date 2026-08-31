# Transcribing large sessions with AWS S3 (+ async callback)

Deepgram's synchronous `v1/listen` endpoint holds the HTTP connection open for
the entire transcription. For a long session (a multi-hour recording can run to
hundreds of MB) with a slower model (`diarize_model=latest`), that connection can
outlive Deepgram's processing window and come back as a **`Gateway Timeout`** —
no transcript.

This guide moves the heavy lifting to AWS in two tiers:

- **Tier 1** hosts the audio in **S3** and hands Deepgram a URL, so you never
  upload the whole file from your laptop twice. Still a normal synchronous
  request — enough for `diarize_model=v1` (see the finding in
  [`README.md`](README.md), section 2).
- **Tier 2** adds the **async callback**: Deepgram returns a `request_id`
  immediately, processes in the background, then delivers the finished JSON to a
  destination you choose. Use this when a job is slow enough to time out
  synchronously (e.g. `latest` on a multi-hour file).

> **The callback goes straight into S3 — no Lambda.** Deepgram supports
> `callback_method=put`, and an S3 **presigned PUT URL** accepts exactly that.
> So Deepgram `PUT`s the result JSON directly into your private bucket. There is
> **no public endpoint** to stand up or secure — earlier versions of this guide
> used a Lambda Function URL because a plain `POST` callback can't target S3, but
> `callback_method=put` removes that need entirely. The bucket stays fully
> private; the only access is through two short-lived, single-object presigned
> URLs signed with your own IAM credentials.

The [`bin/deepgram_async.py`](bin/deepgram_async.py) script automates the whole
Tier-2 flow. The rest of this doc explains the one-time AWS setup it depends on,
then the manual commands behind it.

All commands use placeholders — substitute your own bucket name (S3 bucket names
are globally unique) and region. The Deepgram key is the `$DEEPGRAM_API_KEY` you
already load from `.env` (`set -a; source .env; set +a`).

---

## 0. Prerequisites (one-time)

- An AWS account.
- A **private S3 bucket**. This campaign reuses `ttrpg-deepgram`, the bucket the
  other campaign repos already share — set `DEEPGRAM_BUCKET=ttrpg-deepgram` and
  `DEEPGRAM_PREFIX=dead-ridge-tn` in `.env` (both are already there). The prefix
  namespaces this repo's objects as `<prefix>/<DATE>/…`, so two campaigns
  recorded on the same date can't overwrite each other's audio or transcript.
  If you'd rather stand up a fresh bucket, S3 bucket names are globally unique —
  pick one, pass `--bucket` (or set `DEEPGRAM_BUCKET`), and create it in the
  S3 console with these settings — the goal is the most locked-down posture that
  still lets the callback write:

  | Setting | Value |
  |---|---|
  | **Bucket name** | `ttrpg-deepgram` (or your own; pass `--bucket`) |
  | **Region** | e.g. `us-east-1` (remember it — it must match `--region`) |
  | **Object Ownership** | ACLs disabled (default) |
  | **Block *all* public access** | **ON — leave all four boxes checked** |
  | **Default encryption** | SSE-S3 (AES-256), default. *Avoid SSE-KMS* — it forces extra signed headers on the callback PUT |
  | **Bucket Versioning** | optional; enable to recover an overwritten result |

  No bucket policy and no public access are needed — presigned URLs carry their
  own authorization. *(Optional: add a lifecycle rule to expire objects after
  ~14 days so large audio files don't linger.)*

- A least-privileged **IAM user** whose access key the script/CLI signs URLs
  with. Attach this inline policy (scoped to just this bucket):

  ```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::ttrpg-deepgram",
        "arn:aws:s3:::ttrpg-deepgram/*"
      ]
    }]
  }
  ```

  Create an access key ("Application running outside AWS") and put the
  credentials where boto3 / the AWS CLI can read them — either `~/.aws/credentials`
  or your git-ignored `.env`:

  ```
  AWS_ACCESS_KEY_ID=AKIA...
  AWS_SECRET_ACCESS_KEY=...
  AWS_DEFAULT_REGION=us-east-1
  ```

- For the **script**: `pip install boto3` (the AWS CLI's `s3 presign` only signs
  GET URLs, so the PUT callback URL is generated with boto3).
- For the **manual Tier 1 commands**: the **AWS CLI**, configured once with
  `aws configure`; confirm with `aws sts get-caller-identity`.

This AWS setup is **optional infrastructure** — only worth it for large/slow
jobs. A direct `v1` upload (per the README) usually finishes fine without any of
this.

Throughout, these are the placeholders to replace:

| Placeholder        | Example                            |
|--------------------|------------------------------------|
| `<BUCKET>`         | `ttrpg-deepgram`                   |
| `<REGION>`         | `us-east-1`                        |
| `<PRESIGNED_GET>`  | output of `aws s3 presign` (below) |

---

## Tier 2 — async callback, the easy way (the script)

Once the one-time setup in section 0 is done, a single command handles upload,
presigning, submission, and download:

```bash
set -a; source .env; set +a
python3 bin/deepgram_async.py sessions-raw/<DATE>/session.m4a
```

It:

1. Uploads the audio to `s3://<BUCKET>/<PREFIX>/<DATE>/audio/…` (private).
2. Presigns a **GET** URL so Deepgram can fetch the audio.
3. Presigns a **PUT** URL for `s3://<BUCKET>/<PREFIX>/<DATE>/session.deepgram.json`.
4. Submits to Deepgram with `callback=<presigned-put>&callback_method=put` and
   prints the `request_id`.
5. Polls S3 and downloads the result to
   `sessions-raw/<DATE>/session.deepgram.json` when Deepgram delivers it.

Useful flags:

| Flag | Effect |
|---|---|
| `--diarize-model latest` | use the newer (slower) diarizer instead of `v1` |
| `--no-wait` | submit and exit; fetch the result later yourself |
| `--bucket` / `--region` | override the defaults (`ttrpg-deepgram` / `us-east-1`) |
| `--prefix` | key prefix inside the shared bucket (default `dead-ridge-tn`) |
| `--date` | session folder name if it can't be inferred from the audio path |
| `--callback-expiry` | seconds the result PUT URL stays valid (default 24h, max 604800) |

The script infers `<DATE>` from the audio file's parent folder, so keep the audio
inside its `sessions-raw/<DATE>/` directory.

---

## Tier 1 — S3-hosted audio, synchronous request (manual)

Use this for a normal-length `v1` job when you just want to avoid streaming the
bytes on the request. It's also the set of primitives the script automates.

### 1. Create the bucket

Covered in section 0 — a private bucket with all public access blocked.

```bash
aws s3 mb s3://<BUCKET> --region <REGION>   # or create it in the console
```

### 2. Upload the audio

```bash
aws s3 cp sessions-raw/<DATE>/session.m4a s3://<BUCKET>/<DATE>/audio/
```

### 3. Generate a presigned GET URL

A presigned URL is a temporary, expiring link to the private object — no public
access required.

```bash
aws s3 presign s3://<BUCKET>/<DATE>/audio/session.m4a --expires-in 3600
```

The URL only has to stay valid long enough for Deepgram to **start** fetching, so
1 hour is plenty (SigV4 max is 7 days). Copy the printed URL for the next step.

### 4. Submit to Deepgram by URL

Send a small JSON body pointing at the audio instead of streaming the bytes —
Deepgram fetches the file itself.

```bash
curl --request POST \
  --url 'https://api.deepgram.com/v1/listen?model=nova-3&diarize_model=v1&punctuate=true&smart_format=true&utterances=true' \
  --header "Authorization: Token $DEEPGRAM_API_KEY" \
  --header 'Content-Type: application/json' \
  --data '{"url":"<PRESIGNED_GET>"}' \
  > sessions-raw/<DATE>/session.deepgram.json
```

This is still synchronous — the transcript comes back on this request. Keep
`diarize_model=v1` per the README finding; only reach for `latest` (and Tier 2)
if `v1` is visibly mis-splitting speakers.

---

## Tier 2 — async callback, the manual commands

This is what the script does under the hood, if you want to run it by hand. Do
Tier 1 steps 2–3 first to host the audio and get a `<PRESIGNED_GET>`.

### 1. Presign a PUT URL for the result

The AWS CLI can't presign PUT URLs, so use boto3:

```bash
python3 - <<'PY'
import boto3
url = boto3.client("s3", region_name="<REGION>").generate_presigned_url(
    "put_object",
    Params={"Bucket": "<BUCKET>", "Key": "<DATE>/session.deepgram.json",
            "ContentType": "application/json"},
    ExpiresIn=86400,   # 24h — must cover processing plus Deepgram's retries
)
print(url)
PY
```

**Sign `ContentType: application/json`** — this is required. Deepgram sends that
header when it PUTs the result, and the presigned signature must include it or S3
rejects the callback with `403 SignatureDoesNotMatch`. (This matches Deepgram's
official [S3 presigned-URL recipe](https://developers.deepgram.com/docs/using-aws-s3-presigned-urls-with-the-deepgram-api).)
Default bucket encryption is applied automatically.

### 2. Submit with the PUT callback

Deepgram takes the callback as a query parameter, so the whole presigned PUT URL
must be **URL-encoded** when placed after `&callback=` (it's full of `&`/`=`).
`curl --data-urlencode` handles that:

```bash
curl --request POST -G 'https://api.deepgram.com/v1/listen' \
  --data 'model=nova-3' \
  --data 'diarize_model=latest' \
  --data 'punctuate=true' \
  --data 'smart_format=true' \
  --data 'utterances=true' \
  --data 'callback_method=put' \
  --data-urlencode 'callback=<PRESIGNED_PUT>' \
  --header "Authorization: Token $DEEPGRAM_API_KEY" \
  --header 'Content-Type: application/json' \
  --data-binary '{"url":"<PRESIGNED_GET>"}'
```

You get back `{"request_id":"..."}` right away (not a transcript). Deepgram
processes in the background — a multi-hour file can take many minutes — then
`PUT`s the finished JSON to the presigned URL, i.e. straight into S3. It retries
up to 10 times (30 s apart) on failure, so the PUT URL must stay valid long
enough to cover the whole window.

### 3. Fetch the result

```bash
aws s3 cp s3://<BUCKET>/<DATE>/session.deepgram.json sessions-raw/<DATE>/
```

Then clean up the audio (`aws s3 rm s3://<BUCKET>/<DATE>/audio/session.m4a`); the
transcript is small and cheap to keep.

---

## Which tier do I need?

| Situation                                             | Use     |
|-------------------------------------------------------|---------|
| `diarize_model=v1`, any normal-length session         | Tier 1  |
| Uploading from the laptop is slow / flaky             | Tier 1  |
| `diarize_model=latest` or job times out synchronously | Tier 2  |
| Very long recording (multi-hour)                      | Tier 2  |

Once you have a good `session.deepgram.json`, continue with **step 3 (Format the
transcript)** in [`README.md`](README.md) — or just run the **build-speaker-mapping**
and **translate-deepgram** skills, which do that step for you.
