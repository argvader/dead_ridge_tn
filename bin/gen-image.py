#!/usr/bin/env python3
"""Generate an image with OpenAI gpt-image-1 and save it to disk.

The single seam for all image generation in this project. The session and world
prompts shell out to it; it takes a text prompt and an output path, calls the
OpenAI Images API, and writes the returned PNG.

Usage:
    python3 bin/gen-image.py --prompt "<text>" --out docs/assets/<path>.png [--size 1536x1024]

Requires OPENAI_API_KEY in the environment. Load it from .env the same way as the
Deepgram key (see README.md):

    set -a; source .env; set +a

Uses only the Python standard library — no SDK, no pip install.
"""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request

API_URL = "https://api.openai.com/v1/images/generations"

# Appended to every prompt so scene, location, and hero art share one look —
# the signature style of the Dead Ridge, TN campaign.
STYLE_SUFFIX = (
    " — desaturated painterly digital illustration in the style of The Walking Dead Universe RPG interior art — muted olive drab, khaki and cold teal palette, bleached overcast light, heavy film grain and dry-brush texture, figures and edges dissolving into ink splatter and washed-out paper, weathered Appalachian decay, grim and quiet, no text or lettering."
)

# gpt-image-1 accepts a fixed set of sizes.
VALID_SIZES = {"1024x1024", "1536x1024", "1024x1536", "auto"}


def _die(message):
    print(f"gen-image: {message}", file=sys.stderr)
    sys.exit(1)


def generate(prompt, out_path, size):
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        _die(
            "OPENAI_API_KEY is not set. Copy .env.example to .env, add your key, "
            "then run:  set -a; source .env; set +a"
        )

    payload = json.dumps(
        {
            "model": "gpt-image-1",
            "prompt": prompt + STYLE_SUFFIX,
            "size": size,
            "n": 1,
        }
    ).encode("utf-8")

    request = urllib.request.Request(
        API_URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as err:
        detail = err.read().decode("utf-8", "replace")
        _die(f"OpenAI API returned {err.code}: {detail}")
    except urllib.error.URLError as err:
        _die(f"could not reach the OpenAI API: {err.reason}")

    try:
        b64 = body["data"][0]["b64_json"]
    except (KeyError, IndexError):
        _die(f"unexpected API response: {json.dumps(body)[:500]}")

    image_bytes = base64.b64decode(b64)

    parent = os.path.dirname(os.path.abspath(out_path))
    os.makedirs(parent, exist_ok=True)
    with open(out_path, "wb") as fh:
        fh.write(image_bytes)

    print(f"gen-image: wrote {out_path} ({len(image_bytes):,} bytes)")


def main():
    parser = argparse.ArgumentParser(
        description="Generate an image with OpenAI gpt-image-1 and save it to disk."
    )
    parser.add_argument("--prompt", required=True, help="Text prompt for the image.")
    parser.add_argument("--out", required=True, help="Output file path (e.g. docs/assets/x.png).")
    parser.add_argument(
        "--size",
        default="1536x1024",
        help=f"Image size, one of {sorted(VALID_SIZES)} (default: 1536x1024).",
    )
    args = parser.parse_args()

    if args.size not in VALID_SIZES:
        _die(f"invalid --size {args.size!r}; choose one of {sorted(VALID_SIZES)}")

    generate(args.prompt, args.out, args.size)


if __name__ == "__main__":
    main()
