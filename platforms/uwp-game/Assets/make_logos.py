#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Generates the UWP tile and splash assets the package manifest references.

Source art: cover-source.jpg (the box art supplied for the Arabic Edition).
Tiles are center-cropped to fill (no distortion); the splash screen keeps the
whole artwork on a blurred, darkened cover background so nothing is cut off.
Run once from platforms/uwp-game/Assets:  python3 make_logos.py
"""
import sys
from pathlib import Path

from PIL import Image, ImageFilter

COVER = "cover-source.jpg"


def fill_crop(image: Image.Image, width: int, height: int) -> Image.Image:
    """Scale to cover the target and center-crop the overflow (aspect preserved)."""
    scale = max(width / image.width, height / image.height)
    scaled = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    left = (scaled.width - width) // 2
    top = (scaled.height - height) // 2
    return scaled.crop((left, top, left + width, top + height))


def make_tile(cover: Image.Image, path: Path, size: int) -> None:
    fill_crop(cover, size, size).save(path)
    print(f"{path.name}: {size}x{size}")


def make_splash(cover: Image.Image, path: Path, width: int, height: int) -> None:
    # Background: the cover scaled to fill, blurred and darkened, so the edges
    # of the contained artwork melt into it instead of floating on flat color.
    background = fill_crop(cover, width, height).filter(ImageFilter.GaussianBlur(24))
    background = background.point(lambda v: int(v * 0.45))
    # Foreground: the complete artwork, fitted inside with a small margin.
    margin = 12
    inner_w, inner_h = width - 2 * margin, height - 2 * margin
    scale = min(inner_w / cover.width, inner_h / cover.height)
    foreground = cover.resize((round(cover.width * scale), round(cover.height * scale)), Image.LANCZOS)
    left = (width - foreground.width) // 2
    top = (height - foreground.height) // 2
    background.paste(foreground, (left, top))
    background.save(path)
    print(f"{path.name}: {width}x{height} (art {foreground.width}x{foreground.height} on blurred cover)")


def main() -> int:
    here = Path(__file__).parent
    cover = Image.open(here / COVER).convert("RGB")
    make_tile(cover, here / "Square150x150Logo.png", 150)
    make_tile(cover, here / "Square44x44Logo.png", 44)
    make_tile(cover, here / "StoreLogo.png", 50)
    make_splash(cover, here / "SplashScreen.png", 620, 300)
    return 0


if __name__ == "__main__":
    sys.exit(main())
