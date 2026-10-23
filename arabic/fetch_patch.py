#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Download Arabic Hesham's Wind Waker HD translation from the official release.

The translation is not stored in this repository: it is Hesham Localization's work, distributed
from his own release page. This script fetches the exact archive this integration was built and
tested against (size and SHA-256 pinned below), so a build is reproducible and any changed or
tampered re-upload is refused.

Usage:
    python3 fetch_patch.py [--out DIR]      # default: build/arabic/Arabic.Hesham.Zelda.WW.zip
    python3 fetch_patch.py --zip FILE       # verify a manually downloaded copy instead
"""
import argparse
import hashlib
import sys
import urllib.request
from pathlib import Path

DOWNLOAD_URL = ("https://github.com/7akeem0/Arabic_Hesham-Downloads/releases/download/"
                "localizations-2026-09/Arabic.Hesham.Zelda.WW.zip")
PAGE_URL = "https://arabichesham.com/games/the-legend-of-zelda-the-wind-waker-hd"
EXPECTED_SHA256 = "21b83f9b05a493764bfe38ed93fd3995f65533d551c33f3a02ed1feeb5554001"
EXPECTED_SIZE = 10585918  # bytes, from the release's published asset metadata


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def verify(path: Path) -> None:
    size = path.stat().st_size
    if size != EXPECTED_SIZE:
        raise SystemExit(f"FAIL {path}: expected {EXPECTED_SIZE} bytes, found {size}. "
                         f"Download it yourself from {PAGE_URL} and pass --zip.")
    actual = sha256_file(path)
    if actual != EXPECTED_SHA256:
        raise SystemExit(f"FAIL {path}: SHA-256 {actual}, expected {EXPECTED_SHA256}. "
                         "Refusing to use a changed or tampered archive.")
    print(f"PASS {path}: SHA-256 verified ({EXPECTED_SHA256})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="build/arabic", help="target directory")
    parser.add_argument("--zip", help="verify this locally downloaded archive instead of fetching")
    args = parser.parse_args()

    target = Path(args.zip) if args.zip else Path(args.out) / "Arabic.Hesham.Zelda.WW.zip"
    if not target.exists():
        if args.zip:
            raise SystemExit(f"FAIL {target}: no such file")
        target.parent.mkdir(parents=True, exist_ok=True)
        print(f"Fetching {DOWNLOAD_URL}")
        request = urllib.request.Request(DOWNLOAD_URL, headers={"User-Agent": "wwhd-uwp-arabic/1.0"})
        with urllib.request.urlopen(request) as response, open(target, "wb") as out:
            total = 0
            while block := response.read(1 << 20):
                out.write(block)
                total += len(block)
                print(f"\r{total >> 20} MiB", end="", flush=True)
        print()
    verify(target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
