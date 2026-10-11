#!/usr/bin/env python3
"""Non-blocking HTTP smoke checks against the published BersolekMart PWA/API.

Protected endpoints are checked without credentials only to distinguish an
installed/authenticated route (200/401/403) from a missing route (404). This
does not claim to verify member/driver behavior or perform a checkout.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

BASE = os.environ.get("BERSOLEKMART_BASE_URL", "https://bersolekmart.com").rstrip("/")
HEADERS = {
    "User-Agent": "BersolekMart-Mobile-CI-Smoke/1.0",
    "Accept": "application/json, text/html, image/png, */*",
}


def get(path: str, timeout: int = 15) -> tuple[int, str, bytes]:
    request = urllib.request.Request(BASE + path, headers=HEADERS)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.headers.get("Content-Type", ""), response.read(1024 * 1024)
    except urllib.error.HTTPError as exc:
        return exc.code, exc.headers.get("Content-Type", ""), exc.read(8192)
    except Exception as exc:
        print(f"::warning::GET {path} failed: {type(exc).__name__}: {exc}")
        return 0, "", b""


def warn(message: str) -> None:
    print(f"::warning::{message}")


def probe_public(path: str, label: str) -> tuple[int, str, bytes]:
    status, content_type, body = get(path)
    print(f"[PWA smoke] {label}: HTTP {status or 'NETWORK ERROR'}; content-type={content_type or '-'}; bytes={len(body)}")
    if status < 200 or status >= 300:
        warn(f"Public PWA endpoint {path} did not return 2xx (status {status}).")
    return status, content_type, body


def probe_protected(path: str, label: str) -> None:
    status, content_type, body = get(path)
    print(f"[PWA smoke] {label}: HTTP {status or 'NETWORK ERROR'}; content-type={content_type or '-'}")
    if status not in (200, 401, 403):
        warn(f"Protected route {path} returned {status}; expected 200/401/403 to confirm it exists.")


def main() -> None:
    probe_public("/", "PWA homepage")
    image_status, image_type, image_body = probe_public(
        "/assets/branding/bersolek-mart-splash.png", "official brand asset"
    )
    if image_status == 200 and (not image_type.lower().startswith("image/") or not image_body.startswith(b"\x89PNG\r\n\x1a\n")):
        warn("The official branding URL did not return a PNG image.")

    cms_status, _, cms_body = probe_public("/api/v1/cms/home", "CMS home/hero slides")
    if cms_status == 200:
        try:
            payload = json.loads(cms_body)
            data = payload.get("data", {}) if isinstance(payload, dict) else {}
            slides = data.get("hero_slides", []) if isinstance(data, dict) else []
            if not slides and isinstance(data, dict) and isinstance(data.get("hero"), dict):
                slides = [data["hero"]]
            print(f"[PWA smoke] CMS hero slides returned: {len(slides) if isinstance(slides, list) else 0}")
            if not isinstance(slides, list) or not slides:
                warn("CMS API is reachable but returned no hero slides; the mobile carousel will have no dynamic banner.")
        except Exception as exc:
            warn(f"CMS home response is not valid JSON: {exc}")

    for path, label in (
        ("/api/v1/catalog/products?limit=1", "catalog products"),
        ("/api/v1/catalog/categories", "catalog categories"),
    ):
        probe_public(path, label)

    for path, label in (
        ("/api/v1/addresses", "member addresses"),
        ("/api/v1/banks", "member/driver bank accounts"),
        ("/api/v1/checkout/options", "checkout options"),
        ("/api/v1/checkout/rates?city=Kota%20Probolinggo", "checkout shipping rates"),
        ("/api/v1/driver/profile", "driver profile"),
        ("/api/v1/orders?limit=1", "member orders"),
    ):
        probe_protected(path, label)


if __name__ == "__main__":
    main()
