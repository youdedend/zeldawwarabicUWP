# Arabic Hesham translation integration

This directory carries everything that integrates [Arabic Hesham's Wind Waker HD translation]
(https://arabichesham.com/games/the-legend-of-zelda-the-wind-waker-hd) into WWHD-UWP. The design
document is [docs/arabic.md](../docs/arabic.md); here is the toolchain and what each piece does.

## Contents

| File | Purpose |
| --- | --- |
| `manifest.json` | The content mod's manifest (mod manager format 1, `content.arabic_hesham`). |
| `fetch_patch.py` | Downloads the translation from Arabic Hesham's official release, size- and SHA-256-verified. |
| `stage_mod.py` | Stages the verified archive as the mod package (Method A) or overlays it onto a prepared game tree (Method B). |
| `verify_pack.py` | Reads the staged language pack the way the runtime does and reports its Arabic coverage (Step 2 verification). |
| `patch_arabic_native.asm` | Reference copy of Hesham's Cemu PPC patch (the Windfall pirate door riddle bypass). |
| `tests/` | Offline tests with synthetic SARC/BFFNT fixtures — no game assets required. |

The translation archive itself is **not** in this repository: it is Hesham Localization's work, and
the game's derived files must not be redistributed from here. `fetch_patch.py` pins the exact
archive (`Arabic.Hesham.Zelda.WW.zip`, SHA-256
`21b83f9b05a493764bfe38ed93fd3995f65533d551c33f3a02ed1feeb5554001`) so builds are reproducible and
a changed re-upload is refused.

## Quick start (PC, for staging and checks)

```sh
python3 arabic/fetch_patch.py                         # -> build/arabic/Arabic.Hesham.Zelda.WW.zip
python3 arabic/stage_mod.py --zip build/arabic/Arabic.Hesham.Zelda.WW.zip --out Mods
python3 arabic/verify_pack.py Mods/content.arabic_hesham/content/Common/Pack/permanent_2d_UsEnglish.pack
python3 arabic/stage_mod.py --zip build/arabic/Arabic.Hesham.Zelda.WW.zip --overlay /path/to/prepared/game
```

Run the offline test suite (no assets needed):

```sh
python3 arabic/tests/run_tests.py
```

## On the console

Nothing here needs to be run by hand for the packaged app: the UWP package ships the staged mod
under `BundledMods/content.arabic_hesham`, and the runtime copies it into the player's mod
directory on first start, enables it, and forces right-to-left text for its language pack
(`runtime/src/mods/packages.cpp`, `runtime/src/rtl_text_hooks.cpp`). The Windfall pirate door
patch is applied during game preparation, on console, by `platforms/uwp-game/prepare_game.py`.

## Attribution

The Arabic translation, the localized fonts and the title screen are the work of **Arabic Hesham
(Hesham Localization)**. The Windfall door PPC patch is from his Cemu graphic pack. Please refer to
his page for the terms that apply to the translation itself.
