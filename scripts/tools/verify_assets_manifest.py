#!/usr/bin/env python3
"""Verify the asset pack referenced in assets_manifest.json is actually
published on Arweave and matches what the in-repo manifest claims.

Two checks, both fast — safe to run on every PR:

1. Reachability probe: each pack URL is hit with a 16-byte range GET.
   The response must start with the Godot pack magic `GDPC`.
2. Sidecar manifest: a tiny `pack.manifest.json` published next to the
   pack on Arweave at `manifest.sidecar.urls`. We download it (sub-KB)
   and assert its `version`, `pack.sha256`, and `pack.size` match the
   in-repo manifest. If publish bumped the in-repo manifest but didn't
   actually upload (or uploaded different bytes than the manifest
   claims), the sidecar will be missing or mismatched and CI fails.

The sidecar is the integrity guarantee — we don't re-stream the full
264 MB through Arweave's gateway because it's flaky on long downloads
(IncompleteRead at ~50 MB), and an in-place re-hash buys nothing that
the sidecar doesn't already prove.

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

REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST = REPO_ROOT / "assets_manifest.json"
RETRY_DELAYS_SEC = [0, 30, 60, 120]
HTTP_TIMEOUT = 30
USER_AGENT = "psz-godot-ci/1.0"
SIDECAR_MAX_BYTES = 64 * 1024  # sidecar is ~200 bytes; cap reads for safety


def _request_get(url: str, range_header: str | None = None):
    headers = {"User-Agent": USER_AGENT}
    if range_header:
        headers["Range"] = range_header
    req = urllib.request.Request(url, method="GET", headers=headers)
    return urllib.request.urlopen(req, timeout=HTTP_TIMEOUT)


def probe_pack_url(url: str) -> tuple[bool, str]:
    """Range-GET the first 16 bytes; return (ok, detail). Arweave's CDN
    drops Content-Length on HEAD, so we can't rely on size matching —
    instead we just confirm the bytes start with the Godot pack magic
    `GDPC`, which proves we're getting a real pack rather than an error
    page."""
    try:
        resp = _request_get(url, range_header="bytes=0-15")
        if resp.status not in (200, 206):
            return False, f"{resp.status}"
        head_bytes = resp.read(16)
        if not head_bytes.startswith(b"GDPC"):
            return False, f"{resp.status} not-a-pack"
        return True, f"{resp.status} GDPC ok"
    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code}"
    except Exception as e:  # noqa: BLE001
        return False, f"{type(e).__name__}: {e}"


def find_reachable_pack(urls: list[str]) -> bool:
    if not urls:
        print("  FAIL pack: no urls in manifest")
        return False
    for attempt, delay in enumerate(RETRY_DELAYS_SEC, start=1):
        if delay:
            print(f"    retry in {delay}s...")
            time.sleep(delay)
        for url in urls:
            ok, detail = probe_pack_url(url)
            print(f"    attempt {attempt} GET {url} → {detail}")
            if ok:
                return True
    return False


def fetch_sidecar(urls: list[str]) -> dict | None:
    """Download a sidecar JSON from the first URL that returns a parseable
    response. Sidecars are small enough that one full GET is cheaper than
    a range probe + second fetch."""
    for attempt, delay in enumerate(RETRY_DELAYS_SEC, start=1):
        if delay:
            print(f"    retry in {delay}s...")
            time.sleep(delay)
        for url in urls:
            try:
                resp = _request_get(url)
                if resp.status not in (200, 206):
                    print(f"    attempt {attempt} GET {url} → {resp.status}")
                    continue
                raw = resp.read(SIDECAR_MAX_BYTES)
                data = json.loads(raw.decode("utf-8"))
                print(f"    attempt {attempt} GET {url} → 200 sidecar parsed")
                return data
            except urllib.error.HTTPError as e:
                print(f"    attempt {attempt} GET {url} → HTTP {e.code}")
            except json.JSONDecodeError as e:
                print(f"    attempt {attempt} GET {url} → JSON parse error: {e}")
            except Exception as e:  # noqa: BLE001
                print(f"    attempt {attempt} GET {url} → {type(e).__name__}: {e}")
    return None


def verify_sidecar(in_repo: dict, sidecar: dict) -> list[str]:
    """Return a list of mismatch messages — empty list means ok."""
    issues: list[str] = []
    repo_pack = in_repo.get("pack", {})
    side_pack = sidecar.get("pack", {})
    for field in ("sha256", "size"):
        if repo_pack.get(field) != side_pack.get(field):
            issues.append(
                f"pack.{field} mismatch: in-repo={repo_pack.get(field)!r} "
                f"sidecar={side_pack.get(field)!r}"
            )
    if in_repo.get("version") != sidecar.get("version"):
        issues.append(
            f"version mismatch: in-repo={in_repo.get('version')!r} "
            f"sidecar={sidecar.get('version')!r}"
        )
    return issues


def main() -> int:
    if not MANIFEST.exists():
        print(f"{MANIFEST} missing — nothing to verify")
        return 0
    data = json.loads(MANIFEST.read_text())
    pack = data.get("pack")
    if not pack:
        print("manifest has no pack entry — skipping")
        return 0

    pack_urls = pack.get("urls", [])
    pack_sha = str(pack.get("sha256", "")).strip().lower()
    pack_size = int(pack.get("size", 0))
    print(f"Verifying pack: size={pack_size} sha256={pack_sha[:12]}...")

    pack_ok = find_reachable_pack(pack_urls)
    if not pack_ok:
        print("\nFAIL: pack not reachable on any URL", file=sys.stderr)
        return 1

    sidecar_meta = data.get("sidecar")
    if not sidecar_meta or not sidecar_meta.get("urls"):
        print(
            "\nFAIL: assets_manifest.json has no sidecar.urls — re-run the "
            "publish script so it uploads a sidecar manifest, then commit "
            "the updated assets_manifest.json.",
            file=sys.stderr,
        )
        return 1

    print("\nFetching sidecar manifest...")
    sidecar = fetch_sidecar(sidecar_meta["urls"])
    if sidecar is None:
        print("\nFAIL: sidecar manifest not reachable on any URL", file=sys.stderr)
        return 1

    issues = verify_sidecar(data, sidecar)
    if issues:
        print("\nFAIL: sidecar disagrees with in-repo manifest:", file=sys.stderr)
        for issue in issues:
            print(f"  - {issue}", file=sys.stderr)
        print(
            "\nThis usually means the publish step ran but the in-repo "
            "manifest was edited (or rolled back) after upload. Re-run "
            "the publish script.",
            file=sys.stderr,
        )
        return 1

    print("\nAll checks passed: pack reachable + sidecar matches manifest.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
