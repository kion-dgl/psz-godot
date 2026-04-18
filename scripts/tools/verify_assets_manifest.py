#!/usr/bin/env python3
"""Verify every pack in assets_manifest.json is reachable via at least one URL.

For each pack:
- Try each URL in order (follow redirects)
- Retry a few times with backoff to accommodate slow CDN/gateway propagation
- Fail only if NO URL returns 200 with the expected content-length

Run from repo root:
    python3 scripts/tools/verify_assets_manifest.py
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

MANIFEST = Path(__file__).resolve().parents[2] / "assets_manifest.json"
# Propagation buffer: Arweave Turbo uploads may take ~10-20 min to index on
# some gateways. CI retries four times spaced 30-120s apart.
RETRY_DELAYS_SEC = [0, 30, 60, 120]
HTTP_TIMEOUT = 20


def head(url: str):
    req = urllib.request.Request(url, method="HEAD")
    return urllib.request.urlopen(req, timeout=HTTP_TIMEOUT)


def verify_pack(pack: dict) -> bool:
    name = pack.get("name", "<unnamed>")
    expected_size = int(pack.get("size", 0))
    urls = pack.get("urls", [])
    if not urls:
        print(f"  FAIL {name}: no urls in manifest")
        return False
    print(f"  pack {name}: size={expected_size}")

    for attempt, delay in enumerate(RETRY_DELAYS_SEC, start=1):
        if delay:
            print(f"    retry in {delay}s...")
            time.sleep(delay)
        for url in urls:
            try:
                resp = head(url)
                code = resp.status
                length = int(resp.headers.get("Content-Length") or 0)
                print(f"    attempt {attempt} {url} → {code} len={length}")
                if code == 200 and (expected_size == 0 or length == expected_size):
                    return True
            except urllib.error.HTTPError as e:
                print(f"    attempt {attempt} {url} → HTTP {e.code}")
            except Exception as e:  # noqa: BLE001
                print(f"    attempt {attempt} {url} → {type(e).__name__}: {e}")
    return False


def main() -> int:
    if not MANIFEST.exists():
        print(f"{MANIFEST} missing — nothing to verify")
        return 0
    data = json.loads(MANIFEST.read_text())
    packs = data.get("packs", [])
    if not packs:
        print("manifest has no packs — skipping")
        return 0

    print(f"Verifying {len(packs)} pack(s) from {MANIFEST.name}")
    failed = []
    for pack in packs:
        if not verify_pack(pack):
            failed.append(pack.get("name", "<unnamed>"))

    if failed:
        print(f"\nFAIL: {failed}", file=sys.stderr)
        return 1
    print("\nAll packs reachable.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
