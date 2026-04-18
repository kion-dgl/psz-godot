#!/usr/bin/env python3
"""Verify every pack in assets_manifest.json is reachable and intact.

Modes:
- Default: HEAD each URL, confirm at least one 200 whose Content-Length
  matches the manifest's `size`. Fast — safe to run on every PR.
- --download: additionally download the pack bytes and verify sha256 matches
  the manifest's `sha256`. Slower (pulls ~350 MB). CI runs this only when
  the manifest changed in the PR so we don't waste bandwidth on unrelated
  PRs.

For each pack, each URL is retried a few times with backoff to accommodate
Arweave/CDN propagation. Fail only if NO URL yields a good response.

Run from repo root:
    python3 scripts/tools/verify_assets_manifest.py [--download]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST = REPO_ROOT / "assets_manifest.json"
RETRY_DELAYS_SEC = [0, 30, 60, 120]
HTTP_TIMEOUT = 30
HASH_CHUNK = 1 << 20  # 1 MiB
# R2's public dev URL blocks the default Python-urllib UA with 403; any
# non-default UA works. Use a stable identifier so R2 access logs are readable.
USER_AGENT = "psz-godot-ci/1.0"


def _request(url: str, method: str = "GET"):
    req = urllib.request.Request(
        url, method=method, headers={"User-Agent": USER_AGENT}
    )
    return urllib.request.urlopen(req, timeout=HTTP_TIMEOUT)


def head_ok(url: str, expected_size: int) -> tuple[bool, int, str]:
    """Returns (ok, length, detail). ok=True iff 200 + length matches."""
    try:
        resp = _request(url, "HEAD")
        length = int(resp.headers.get("Content-Length") or 0)
        if resp.status == 200 and (expected_size == 0 or length == expected_size):
            return True, length, f"200 len={length}"
        return False, length, f"{resp.status} len={length}"
    except urllib.error.HTTPError as e:
        return False, 0, f"HTTP {e.code}"
    except Exception as e:  # noqa: BLE001
        return False, 0, f"{type(e).__name__}: {e}"


def stream_sha256(url: str) -> tuple[str | None, int, str]:
    """Download `url`, compute sha256 chunk-by-chunk. Returns (hex or None, size, detail)."""
    try:
        resp = _request(url, "GET")
    except urllib.error.HTTPError as e:
        return None, 0, f"HTTP {e.code}"
    except Exception as e:  # noqa: BLE001
        return None, 0, f"{type(e).__name__}: {e}"
    h = hashlib.sha256()
    total = 0
    while True:
        try:
            chunk = resp.read(HASH_CHUNK)
        except Exception as e:  # noqa: BLE001
            return None, total, f"read error after {total}: {e}"
        if not chunk:
            break
        h.update(chunk)
        total += len(chunk)
        if total % (50 * 1024 * 1024) < HASH_CHUNK:
            print(f"    ...{total / 1024 / 1024:.0f} MB streamed")
    return h.hexdigest(), total, "ok"


def find_reachable_url(pack: dict) -> str | None:
    """Return the first URL whose HEAD yields 200 with expected size."""
    name = pack.get("name", "<unnamed>")
    expected_size = int(pack.get("size", 0))
    urls = pack.get("urls", [])
    if not urls:
        print(f"  FAIL {name}: no urls in manifest")
        return None
    for attempt, delay in enumerate(RETRY_DELAYS_SEC, start=1):
        if delay:
            print(f"    retry in {delay}s...")
            time.sleep(delay)
        for url in urls:
            ok, _, detail = head_ok(url, expected_size)
            print(f"    attempt {attempt} HEAD {url} → {detail}")
            if ok:
                return url
    return None


def verify_pack(pack: dict, download: bool) -> bool:
    name = pack.get("name", "<unnamed>")
    expected_size = int(pack.get("size", 0))
    expected_sha = str(pack.get("sha256", "")).strip().lower()
    urls = pack.get("urls", [])
    print(f"  pack {name}: size={expected_size} sha256={expected_sha[:12]}...")

    if not download:
        return find_reachable_url(pack) is not None

    if not expected_sha:
        print("  FAIL: --download requires a sha256 in the manifest")
        return False

    # Try each URL for the full download until one succeeds: some mirrors
    # (e.g. ar-io.dev) HEAD OK but return 402 on GET.
    for attempt, delay in enumerate(RETRY_DELAYS_SEC, start=1):
        if delay:
            print(f"    retry in {delay}s...")
            time.sleep(delay)
        for url in urls:
            ok, _, head_detail = head_ok(url, expected_size)
            if not ok:
                print(f"    HEAD {url} → {head_detail} (skipping)")
                continue
            print(f"    GET  {url} → streaming for sha256")
            got_sha, got_size, detail = stream_sha256(url)
            if got_sha is None:
                print(f"    GET failed ({detail}); trying next URL")
                continue
            if expected_size and got_size != expected_size:
                print(f"    size mismatch — got {got_size}, want {expected_size}")
                continue
            if got_sha != expected_sha:
                print(f"    sha256 mismatch — got {got_sha}, want {expected_sha}")
                # A mismatch is a hard fail — no point trying another mirror
                # for the same manifest entry, all mirrors should serve
                # identical bytes.
                return False
            print(f"  OK: sha256 matches manifest (via {url})")
            return True
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--download",
        action="store_true",
        help="Download each pack and verify its sha256 (slower).",
    )
    args = ap.parse_args()

    if not MANIFEST.exists():
        print(f"{MANIFEST} missing — nothing to verify")
        return 0
    data = json.loads(MANIFEST.read_text())
    packs = data.get("packs", [])
    if not packs:
        print("manifest has no packs — skipping")
        return 0

    mode = "full (download + hash)" if args.download else "url check only"
    print(f"Verifying {len(packs)} pack(s) from {MANIFEST.name} — {mode}")
    failed = []
    for pack in packs:
        if not verify_pack(pack, download=args.download):
            failed.append(pack.get("name", "<unnamed>"))

    if failed:
        print(f"\nFAIL: {failed}", file=sys.stderr)
        return 1
    print("\nAll packs verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
