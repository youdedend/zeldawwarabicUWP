#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Stage Arabic Hesham's translation as a WWHD-UWP content mod, or overlay it onto a prepared game.

Two ways to integrate, both supported by the runtime (docs/arabic.md):

  Method A (default)  stage the mod directory the runtime's mod manager installs:
                      Mods/content.arabic_hesham/{manifest.json, content/...}
                      The UWP package ships this tree under BundledMods/; on the console it is
                      copied into the player's mod directory on first start and enabled.

  Method B            --overlay GAME_ROOT bakes the files into a prepared (extracted) game tree:
                      game/content/Common/Pack/permanent_2d_UsEnglish.pack
                      game/content/Common/Layout/Title_00.szs

The Cemu code patch in the archive (graphicPacks/ArabicNative/patch_arabic_native.asm) is never
copied: this port applies its two PowerPC edits at translation time (platforms/uwp-game/
prepare_game.py), and a content mod must not carry dead code.

Usage:
    python3 stage_mod.py --zip build/arabic/Arabic.Hesham.Zelda.WW.zip --out Mods
    python3 stage_mod.py --zip build/arabic/Arabic.Hesham.Zelda.WW.zip --overlay game/
    python3 stage_mod.py --from-dir Arabic_Hesham --out Mods
"""
import argparse
import json
import shutil
import sys
import zipfile
from pathlib import Path

KNOWN_LANGUAGE_PACKS = (
    "permanent_2d_usenglish.pack", "permanent_2d_usfrench.pack", "permanent_2d_usspanish.pack",
    "permanent_2d_euenglish.pack", "permanent_2d_eufrench.pack", "permanent_2d_eugerman.pack",
    "permanent_2d_euitalian.pack", "permanent_2d_euspanish.pack", "permanent_2d_jpjapanese.pack",
)
MOD_ID = "content.arabic_hesham"


def lower(name: str) -> str:
    return name.lower().replace("\\", "/")


def extract_tree(zip_path: Path, work: Path) -> Path:
    """Extract the archive and return the folder that holds its content/ tree (Arabic_Hesham/)."""
    work.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        for member in archive.namelist():
            if member.startswith("__MACOSX"):
                continue
            target = (work / member).resolve()
            if not str(target).startswith(str(work.resolve())):
                raise SystemExit(f"FAIL {zip_path}: unsafe archive entry {member}")
        archive.extractall(work)
    for candidate in sorted(work.rglob("*")):
        if candidate.is_dir() and (candidate / "content").is_dir():
            return candidate
    raise SystemExit(f"FAIL {zip_path}: no content/ tree found inside (expected an Arabic_Hesham/ folder)")


def stage(source: Path, out: Path, manifest_path: Path) -> Path:
    """Copy the source content tree into a mod package directory; return it."""
    content = source / "content"
    packs = [p for p in content.rglob("*.pack") if lower(p.name) in KNOWN_LANGUAGE_PACKS]
    if not packs:
        raise SystemExit(f"FAIL {content}: no known language pack (permanent_2d_*.pack) inside. "
                         "A translation pack this runtime cannot map would silently do nothing.")
    target = out / MOD_ID
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    shutil.copy(manifest_path, target / "manifest.json")
    shutil.copytree(content, target / "content")
    staged = sorted(p.relative_to(target).as_posix() for p in target.rglob("*") if p.is_file())
    print(f"Staged {MOD_ID}:")
    for name in staged:
        print(f"  {name} ({(target / name).stat().st_size} bytes)")
    skipped = [p for p in content.rglob("*") if p.is_file() and lower(p.suffix) in (".asm", ".txt", ".md")]
    if skipped:
        print("Not staged (applied by the runtime, or documentation):")
        for p in skipped:
            print(f"  {p.relative_to(source).as_posix()}")
    return target


def overlay(source: Path, game_root: Path) -> None:
    """Bake the content files into a prepared game tree (Method B)."""
    content = source / "content"
    if not (game_root / "content").is_dir():
        raise SystemExit(f"FAIL {game_root}: not a prepared game tree (no content/ folder)")
    copied = 0
    for item in content.rglob("*"):
        if not item.is_file() or lower(item.suffix) in (".asm", ".txt", ".md"):
            continue
        relative = item.relative_to(content)
        destination = game_root / "content" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, destination)
        print(f"  overlay {relative.as_posix()} ({item.stat().st_size} bytes)")
        copied += 1
    if not copied:
        raise SystemExit(f"FAIL {content}: nothing to overlay")
    print(f"PASS overlay: {copied} file(s) written into {game_root}/content")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", help="the verified Arabic.Hesham.Zelda.WW.zip")
    parser.add_argument("--from-dir", help="an already extracted Arabic_Hesham/ folder")
    parser.add_argument("--out", default="Mods", help="Method A: mod directory to stage into")
    parser.add_argument("--overlay", help="Method B: prepared game tree to bake the files into")
    parser.add_argument("--work", default="build/arabic/extracted", help="extraction scratch directory")
    parser.add_argument("--manifest", default=str(Path(__file__).parent / "manifest.json"))
    args = parser.parse_args()

    if not args.zip and not args.from_dir:
        parser.error("one of --zip or --from-dir is required")
    source = Path(args.from_dir) if args.from_dir else extract_tree(Path(args.zip), Path(args.work))
    print(f"Source: {source}")
    if args.overlay:
        overlay(source, Path(args.overlay))
    else:
        stage(source, Path(args.out), Path(args.manifest))
        print(f"PASS staged mod in {args.out}/{MOD_ID} (install: copy to the console's mod directory, "
              "or ship it as BundledMods/content.arabic_hesham in the app package)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
