#!/usr/bin/env python3
"""Fetch the canonical BersolekMart logo from the deployed PWA and prepare Android assets.

The source is the existing public/assets/branding/bersolek-mart-splash.png from
the PWA source. Failing this step is intentional: don't ship an APK with a fake
placeholder icon if the canonical logo can't be fetched.
"""
from __future__ import annotations

import io
import os
import sys
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "branding"
FULL_LOGO = ASSETS / "bersolek-mart-icon-512.png"
ADAPTIVE_LOGO = ASSETS / "bersolek-mart-adaptive-foreground.png"
LOGO_URL = os.environ.get(
    "BERSOLEKMART_LOGO_URL",
    "https://bersolekmart.com/assets/branding/bersolek-mart-splash.png",
)


def fetch_source() -> Image.Image:
    request = urllib.request.Request(
        LOGO_URL,
        headers={"User-Agent": "BersolekMart-Android-Build/1.0", "Accept": "image/png"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError(f"Logo fetch returned HTTP {response.status}")
        raw = response.read(5 * 1024 * 1024 + 1)
    if len(raw) > 5 * 1024 * 1024:
        raise RuntimeError("Logo response exceeds 5 MiB; refusing unexpected asset")
    image = Image.open(io.BytesIO(raw))
    image.verify()
    image = Image.open(io.BytesIO(raw)).convert("RGBA")
    if image.width < 400 or image.height < 400:
        raise RuntimeError(f"Canonical logo is unexpectedly small: {image.size}")
    if image.getchannel("A").getbbox() is None:
        raise RuntimeError("Canonical logo is fully transparent")
    return image


def contain(image: Image.Image, max_width: int, max_height: int) -> Image.Image:
    scale = min(max_width / image.width, max_height / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(size, Image.Resampling.LANCZOS)


def main() -> int:
    ASSETS.mkdir(parents=True, exist_ok=True)
    try:
        source = fetch_source()
    except Exception as exc:  # do not quietly build with the wrong icon
        print(f"ERROR: unable to fetch canonical BersolekMart logo from {LOGO_URL}: {exc}", file=sys.stderr)
        return 1

    full = source.resize((512, 512), Image.Resampling.LANCZOS)
    full.save(FULL_LOGO, format="PNG", optimize=True)

    # The launcher gets the illustration mark only, inside Android's safe zone.
    # The complete wordmark is still used in the app splash and account header.
    w, h = source.size
    crop = source.crop((round(w * 0.05), round(h * 0.158), round(w * 0.95), round(h * 0.708)))
    mark = contain(crop, 300, 190)
    adaptive = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    adaptive.alpha_composite(mark, ((512 - mark.width) // 2, (512 - mark.height) // 2))
    adaptive.save(ADAPTIVE_LOGO, format="PNG", optimize=True)

    print(f"Prepared full logo: {FULL_LOGO} ({FULL_LOGO.stat().st_size} bytes)")
    print(f"Prepared adaptive foreground: {ADAPTIVE_LOGO} ({ADAPTIVE_LOGO.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
