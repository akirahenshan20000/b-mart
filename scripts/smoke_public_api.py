#!/usr/bin/env python3
"""Strict smoke checks for the deployed BersolekMart mobile API.

Public endpoints must return a successful JSON contract. Protected endpoints are
probed without credentials and must return JSON HTTP 401, proving the route exists
and is applying Bearer-token authentication. No user data or credentials are sent.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from urllib.parse import urljoin, urlsplit

BASE = os.environ.get("BERSOLEKMART_BASE_URL", "https://bersolekmart.com").rstrip("/")
HEADERS = {
    "User-Agent": "BersolekMart-Mobile-CI-Smoke/1.1",
    "Accept": "application/json, text/html, image/png, */*",
}
FAILURES: list[str] = []


def request(path: str, method: str = "GET", payload: dict | None = None, timeout: int = 20) -> tuple[int, str, bytes]:
    headers = dict(HEADERS)
    body = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(payload).encode("utf-8")
    target_url = path if path.startswith(("https://", "http://")) else BASE + path
    req = urllib.request.Request(target_url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.headers.get("Content-Type", ""), response.read(1024 * 1024)
    except urllib.error.HTTPError as exc:
        return exc.code, exc.headers.get("Content-Type", ""), exc.read(8192)
    except Exception as exc:
        FAILURES.append(f"{method} {path}: network error ({type(exc).__name__})")
        print(f"::error::{method} {path} failed: {type(exc).__name__}")
        return 0, "", b""


def report(label: str, method: str, path: str, status: int, content_type: str, expected: str) -> None:
    print(f"[PWA smoke] {label}: {method} {path} -> HTTP {status or 'NETWORK ERROR'}; content-type={content_type or '-'}")
    if expected == "public-json":
        if status != 200 or "json" not in content_type.lower():
            FAILURES.append(f"{method} {path}: expected HTTP 200 JSON, got {status} ({content_type})")
    elif expected == "protected-json":
        if status != 401 or "json" not in content_type.lower():
            FAILURES.append(f"{method} {path}: unauthenticated request should return HTTP 401 JSON, got {status} ({content_type})")
    elif expected == "png":
        if status != 200 or not content_type.lower().startswith("image/"):
            FAILURES.append(f"{method} {path}: expected image response, got {status} ({content_type})")


def parse_json(body: bytes, label: str):
    try:
        return json.loads(body)
    except Exception:
        FAILURES.append(f"{label}: response body is not valid JSON")
        return None


def require_api_envelope(payload, label: str, data_type):
    if not isinstance(payload, dict) or payload.get("ok") is not True or not isinstance(payload.get("data"), data_type):
        FAILURES.append(f"{label}: expected {{ok:true,data:{data_type.__name__}}} envelope")
        return None
    return payload["data"]


def main() -> int:
    status, content_type, body = request("/")
    print(f"[PWA smoke] PWA homepage: HTTP {status or 'NETWORK ERROR'}; bytes={len(body)}")
    if status != 200 or b"<html" not in body.lower():
        FAILURES.append(f"GET /: expected HTTP 200 HTML, got {status} ({content_type})")

    status, content_type, body = request("/assets/branding/bersolek-mart-splash.png")
    report("official brand asset", "GET", "/assets/branding/bersolek-mart-splash.png", status, content_type, "png")
    if status == 200 and not body.startswith(b"\x89PNG\r\n\x1a\n"):
        FAILURES.append("official brand asset did not return a valid PNG signature")

    status, content_type, body = request("/api/v1/health")
    report("API health", "GET", "/api/v1/health", status, content_type, "public-json")
    health = require_api_envelope(parse_json(body, "API health"), "API health", dict) if status == 200 else None
    if health is not None and (health.get("status") != "ok" or health.get("database") != "ok"):
        FAILURES.append("API health returned a non-healthy service/database state")

    status, content_type, body = request("/api/v1/cms/home")
    report("CMS home", "GET", "/api/v1/cms/home", status, content_type, "public-json")
    cms = require_api_envelope(parse_json(body, "CMS home"), "CMS home", dict) if status == 200 else None
    if isinstance(cms, dict):
        slides = cms.get("hero_slides")
        if not isinstance(slides, list):
            slides = [cms["hero"]] if isinstance(cms.get("hero"), dict) else []
        print(f"[PWA smoke] CMS hero slides: {len(slides)}")
        # Zero slides is a valid CMS state; the app must not invent a banner.

    product_path = "/api/v1/catalog/products?limit=24"
    status, content_type, body = request(product_path)
    report("catalog products", "GET", product_path, status, content_type, "public-json")
    products = require_api_envelope(parse_json(body, "catalog products"), "catalog products", list) if status == 200 else None
    if isinstance(products, list):
        print(f"[PWA smoke] Active products returned for limit=24: {len(products)}")
        raster_image_url = None
        svg_fallbacks = 0
        for product in products:
            if not isinstance(product, dict) or any(k not in product for k in ("id", "name", "price", "image")):
                FAILURES.append("catalog product item is missing id/name/price/image contract fields")
                continue
            if str(product.get("status", "active")).lower() != "active":
                FAILURES.append("catalog API returned a non-active product")
            image_path = str(product.get("image") or "").strip()
            if not image_path:
                continue
            parsed_image = urlsplit(image_path)
            if parsed_image.path.lower().endswith(".svg"):
                svg_fallbacks += 1
                continue
            if parsed_image.scheme in ("http", "https"):
                raster_image_url = image_path
                break
            if not parsed_image.scheme:
                raster_image_url = urljoin(BASE.rstrip("/") + "/", image_path)
                break
        print(f"[PWA smoke] Products using SVG fallback: {svg_fallbacks}")
        if raster_image_url:
            image_status, image_type, image_body = request(raster_image_url)
            image_path_only = urlsplit(raster_image_url).path
            print(f"[PWA smoke] Product image: GET {image_path_only} -> HTTP {image_status or 'NETWORK ERROR'}; content-type={image_type or '-'}; bytes={len(image_body)}")
            if image_status != 200 or not image_type.lower().startswith("image/"):
                FAILURES.append(f"product image {image_path_only}: expected HTTP 200 image/*, got {image_status} ({image_type})")
        elif products:
            print("[PWA smoke] No raster product image URL found in active products; catalog items may use the documented SVG fallback or have no uploaded photos.")

    status, content_type, body = request("/api/v1/catalog/categories")
    report("catalog categories", "GET", "/api/v1/catalog/categories", status, content_type, "public-json")
    require_api_envelope(parse_json(body, "catalog categories"), "catalog categories", list) if status == 200 else None

    # Route existence and Bearer-token middleware checks. No credentials are sent.
    protected_get = (
        ("/api/v1/me", "current user"),
        ("/api/v1/addresses", "member/driver addresses"),
        ("/api/v1/banks", "member/driver bank accounts"),
        ("/api/v1/checkout/options", "checkout options"),
        ("/api/v1/checkout/rates?city=Kota%20Probolinggo", "checkout rates"),
        ("/api/v1/driver/profile", "driver profile"),
        ("/api/v1/orders?limit=1", "member orders"),
    )
    for path, label in protected_get:
        status, content_type, _ = request(path)
        report(label, "GET", path, status, content_type, "protected-json")

    protected_post = (
        ("/api/v1/profile", "profile update"),
        ("/api/v1/addresses/save", "address save"),
        ("/api/v1/addresses/delete/1", "address delete"),
        ("/api/v1/banks/save", "bank account save"),
        ("/api/v1/banks/delete/1", "bank account delete"),
        ("/api/v1/driver/base-location", "driver base location"),
        ("/api/v1/driver/jobs/1/status", "driver job status command"),
        ("/api/v1/driver/status", "driver availability status"),
    )
    for path, label in protected_post:
        status, content_type, _ = request(path, method="POST", payload={})
        report(label, "POST", path, status, content_type, "protected-json")

    if FAILURES:
        for failure in FAILURES:
            print(f"::error::{failure}")
        print(f"[PWA smoke] FAILED: {len(FAILURES)} issue(s) found.")
        return 1
    print("[PWA smoke] PASS: public contracts valid and protected routes enforce authentication.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
