#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Generates the UWP tile and splash assets the package manifest references.

Solid deep-sea background (#102838, the manifest's BackgroundColor) with a light sail mark.
Run once from platforms/uwp-game/Assets:  python3 make_logos.py
"""
import struct
import sys
import zlib
from pathlib import Path

BG = (0x10, 0x28, 0x38)
SAIL = (0xE8, 0xEE, 0xF2)


def png(width: int, height: int, pixel) -> bytes:
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none
        for x in range(width):
            raw.extend(pixel(x, y))
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def sail_mark(width: int, height: int, x: int, y: int):
    """A simple lateen sail: two triangles, drawn relative to the canvas."""
    cx, cy = width * 0.5, height * 0.58
    s = min(width, height)
    hull_l, hull_r = cx - s * 0.32, cx + s * 0.32
    top_y, bottom_y = cy - s * 0.30, cy + s * 0.22
    mast_x = cx - s * 0.10
    in_sail = hull_l <= x <= mast_x and top_y <= y <= bottom_y and \
        (x - hull_l) / max(mast_x - hull_l, 1) >= (y - top_y) / max(bottom_y - top_y, 1)
    in_hull = (top_y + s * 0.26) <= y <= bottom_y and hull_l <= x <= hull_r and \
        abs(x - cx) / max(hull_r - cx, 1) <= (bottom_y - y) / max(bottom_y - (top_y + s * 0.26), 1)
    return in_sail or in_hull


def make(path: Path, width: int, height: int) -> None:
    path.write_bytes(png(width, height, lambda x, y: SAIL if sail_mark(width, height, x, y) else BG))
    print(f"{path.name}: {width}x{height}")


def main() -> int:
    here = Path(__file__).parent
    make(here / "StoreLogo.png", 50, 50)
    make(here / "Square44x44Logo.png", 44, 44)
    make(here / "Square150x150Logo.png", 150, 150)
    make(here / "SplashScreen.png", 620, 300)
    return 0


if __name__ == "__main__":
    sys.exit(main())
