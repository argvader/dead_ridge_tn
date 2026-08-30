#!/usr/bin/env python3
"""Transcribe a long session with Deepgram's async callback flow, using S3.

Why this exists: Deepgram's synchronous endpoint holds the HTTP connection open
for the whole job. A multi-hour file can outlive that window and come back as a
Gateway Timeout. This script uses the async flow instead:

  1. Upload the audio to a PRIVATE S3 bucket.
  2. Presign a GET URL so Deepgram can fetch the audio (no bytes leave here twice).
  3. Presign a PUT URL for the result object.
  4. Submit to Deepgram with callback=<presigned-put>&callback_method=put.
     Deepgram returns a request_id immediately, processes in the background, then
     PUTs the finished JSON straight into S3 via the presigned URL.
  5. (default) Poll S3 until the result lands, then download it locally.

No Lambda and no public endpoint are involved. The bucket stays fully private;
the only access is through two short-lived, single-object presigned URLs signed
with your own IAM credentials.

Prerequisites
-------------
  pip install -r requirements-dev.txt      # boto3 + requests
  # A private S3 bucket named dead-ridge-tn-deepgram, and AWS credentials for a
  # least-privileged IAM user scoped to it (see DEEPGRAM_AWS.md).
  # boto3 reads them from the environment or ~/.aws/credentials:
  #   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION
  # DEEPGRAM_API_KEY comes from .env (this script also loads .env for you).

Usage
-----
  python3 bin/deepgram_async.py sessions-raw/2026-01-15/session.m4a
  python3 bin/deepgram_async.py sessions-raw/2026-01-15/session.m4a --diarize-model latest
  python3 bin/deepgram_async.py sessions-raw/2026-01-15/session.m4a --no-wait  # fire and exit

The session date is taken from the audio file's parent directory name, so keep the
recording inside its dated sessions-raw/<DATE>/ folder (or pass --date).
"""

import argparse
import os
import sys
import time
from pathlib import Path
from urllib.parse import urlencode

import requests

try:
    import boto3
    from botocore.exceptions import ClientError
except ImportError:
    sys.exit("boto3 is required: pip install boto3")

REPO_ROOT = Path(__file__).resolve().parent.parent
DEEPGRAM_URL = "https://api.deepgram.com/v1/listen"


def load_dotenv(path):
    """Populate os.environ from a .env file without overwriting real env vars."""
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))


def parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("audio", type=Path, help="path to the audio file to transcribe")
    p.add_argument("--bucket", default=os.environ.get("DEEPGRAM_BUCKET", "dead-ridge-tn-deepgram"))
    p.add_argument("--region", default=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))
    p.add_argument("--model", default="nova-3")
    p.add_argument("--diarize-model", default="v1", choices=["v1", "latest"],
                   help="speaker-separation model; prefer v1 (see README finding)")
    p.add_argument("--date", help="session date folder under sessions-raw/ "
                                   "(default: audio file's parent dir name)")
    p.add_argument("--url-expiry", type=int, default=21600,
                   help="seconds the audio GET URL stays valid (default 6h)")
    p.add_argument("--callback-expiry", type=int, default=86400,
                   help="seconds the result PUT URL stays valid (default 24h, max 604800)")
    p.add_argument("--no-wait", dest="wait", action="store_false",
                   help="submit and exit instead of polling for the result")
    p.add_argument("--poll-timeout", type=int, default=5400,
                   help="max seconds to poll for the result (default 90m)")
    return p.parse_args()


def s3_keys(date, audio_name):
    """Return the (audio, result) object keys, namespaced per session date."""
    return f"{date}/audio/{audio_name}", f"{date}/session.deepgram.json"


def upload_audio(s3, bucket, key, audio_path):
    print(f"↑ uploading {audio_path.name} → s3://{bucket}/{key}")
    s3.upload_file(str(audio_path), bucket, key)


def presign(s3, method, bucket, key, expiry, content_type=None):
    # For the callback PUT, sign ContentType: application/json — this is what
    # Deepgram's official S3-presigned-URL recipe does, and Deepgram sends that
    # header when it PUTs the result. Default bucket encryption is applied by S3.
    params = {"Bucket": bucket, "Key": key}
    if content_type:
        params["ContentType"] = content_type
    return s3.generate_presigned_url(method, Params=params, ExpiresIn=expiry)


def submit(audio_get_url, result_put_url, model, diarize_model):
    query = urlencode({
        "model": model,
        "diarize_model": diarize_model,
        "punctuate": "true",
        "smart_format": "true",
        "utterances": "true",
        "callback": result_put_url,       # urlencode percent-encodes the whole URL
        "callback_method": "put",         # Deepgram PUTs the JSON to the presigned URL
    })
    resp = requests.post(
        f"{DEEPGRAM_URL}?{query}",
        headers={"Authorization": f"Token {os.environ['DEEPGRAM_API_KEY']}",
                 "Content-Type": "application/json"},
        json={"url": audio_get_url},
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()


def _fmt(seconds):
    """Seconds → H:MM:SS (or M:SS under an hour)."""
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def wait_for_result(s3, bucket, key, dest, poll_timeout, interval=15):
    print(f"⋯ waiting for Deepgram to PUT s3://{bucket}/{key} (polling every {interval}s)")
    start = time.time()
    deadline = start + poll_timeout
    tty = sys.stdout.isatty()
    while time.time() < deadline:
        try:
            s3.head_object(Bucket=bucket, Key=key)
        except ClientError as e:
            if e.response["Error"]["Code"] not in ("404", "NoSuchKey", "403"):
                raise
            elapsed = _fmt(time.time() - start)
            # In-place timer on a TTY; plain lines when logged to a file.
            end = "" if tty else "\n"
            print(f"\r  ⏱ {elapsed} elapsed (timeout at {_fmt(poll_timeout)})",
                  end=end, flush=True)
            time.sleep(interval)
            continue
        if tty:
            print()  # close the in-place timer line
        dest.parent.mkdir(parents=True, exist_ok=True)
        s3.download_file(bucket, key, str(dest))
        print(f"✓ transcript downloaded → {dest} (after {_fmt(time.time() - start)})")
        return True
    if tty:
        print()
    print(f"⚠ timed out after {_fmt(time.time() - start)}; the job may still finish. "
          f"Fetch later: aws s3 cp s3://{bucket}/{key} {dest}")
    return False


def main():
    args = parse_args()
    load_dotenv(REPO_ROOT / ".env")

    if not args.audio.is_file():
        sys.exit(f"audio file not found: {args.audio}")
    if not os.environ.get("DEEPGRAM_API_KEY"):
        sys.exit("DEEPGRAM_API_KEY is not set (put it in .env or the environment)")

    date = args.date or args.audio.resolve().parent.name
    audio_key, result_key = s3_keys(date, args.audio.name)
    dest = REPO_ROOT / "sessions-raw" / date / "session.deepgram.json"

    s3 = boto3.client("s3", region_name=args.region)

    upload_audio(s3, args.bucket, audio_key, args.audio)
    audio_get_url = presign(s3, "get_object", args.bucket, audio_key, args.url_expiry)
    result_put_url = presign(s3, "put_object", args.bucket, result_key, args.callback_expiry,
                             content_type="application/json")

    result = submit(audio_get_url, result_put_url, args.model, args.diarize_model)
    request_id = result.get("request_id", "<none>")
    print(f"✓ submitted to Deepgram — request_id={request_id}")
    print(f"  result will land at s3://{args.bucket}/{result_key}")

    if args.wait:
        wait_for_result(s3, args.bucket, result_key, dest, args.poll_timeout)
    else:
        print(f"  fetch when ready: aws s3 cp s3://{args.bucket}/{result_key} {dest}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\ninterrupted — the Deepgram job may still be running; "
                 "re-run to resume polling, or fetch the result from S3 later.")
