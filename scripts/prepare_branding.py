#!/usr/bin/env python3
"""Prepare official BersolekMart logo assets before building the Flutter APK.

The canonical source is the public PWA asset, not an AI-generated placeholder.
If the website asset can't be reached or is invalid, the release build must fail
instead of silently shipping the old padlock icon.
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
    except Exception as exc:
        print(f"ERROR: unable to fetch canonical BersolekMart logo from {LOGO_URL}: {exc}", file=sys.stderr)
        return 1

    bounds = source.getchannel("A").getbbox()
    if bounds is None:
        raise RuntimeError("Canonical logo has no visible pixels")
    logo = source.crop(bounds)

    # Trim transparent canvas before fitting the launcher icon. The old asset
    # included large margins and Android scaled the logo down again.
    legacy_mark = contain(logo, 440, 440)
    legacy = Image.new("RGBA", (512, 512), (255, 255, 255, 255))
    legacy.alpha_composite(
        legacy_mark, ((512 - legacy_mark.width) // 2, (512 - legacy_mark.height) // 2)
    )
    legacy.save(FULL_LOGO, format="PNG", optimize=True)

    adaptive_mark = contain(logo, 400, 400)
    adaptive = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    adaptive.alpha_composite(
        adaptive_mark, ((512 - adaptive_mark.width) // 2, (512 - adaptive_mark.height) // 2)
    )
    adaptive.save(ADAPTIVE_LOGO, format="PNG", optimize=True)

    for path in (FULL_LOGO, ADAPTIVE_LOGO):
        if not path.exists() or path.stat().st_size < 1000:
            print(f"ERROR: prepared asset looks invalid: {path}", file=sys.stderr)
            return 1
        with Image.open(path) as image:
            if image.size != (512, 512):
                print(f"ERROR: expected a 512x512 image at {path}, got {image.size}", file=sys.stderr)
                return 1
        print(f"Prepared {path.name}: {path.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
