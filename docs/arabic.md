# Arabic Hesham translation in WWHD-UWP — design

This document describes how Arabic Hesham's Wind Waker HD translation is integrated into this
port: the assets, the runtime's right-to-left text engine, and the one game-code patch his pack
ships (the Windfall pirate door riddle bypass). The tooling lives in [`arabic/`](../arabic/README.md).

## 1. The translation and what this port does with it

Arabic Hesham distributes his Wind Waker HD translation from
[his site](https://arabichesham.com/games/the-legend-of-zelda-the-wind-waker-hd); the archive this
integration targets is the release asset `Arabic.Hesham.Zelda.WW.zip`
(SHA-256 `21b83f9b05a493764bfe38ed93fd3995f65533d551c33f3a02ed1feeb5554001`). Its game files are
modified versions of Nintendo's content; this repository therefore carries **none of them** — the
build fetches the archive from the official release and verifies it against the pinned hash
(`arabic/fetch_patch.py`), and `.local/` keeps the staged result out of Git, like the other private
game-derived artifacts.

| File in the archive | Where it lands |
| --- | --- |
| `content/Common/Pack/permanent_2d_UsEnglish.pack` | Replaces the USA 2D language pack (all translated dialogue, UI strings and the Arabic bitmap font). |
| `content/Common/Layout/Title_00.szs` | Replaces the title screen (Arabic logo). |
| `graphicPacks/ArabicNative/patch_arabic_native.asm` | Hesham's Cemu PPC patch. Not copied: its two edits are applied at translation time (§4). |

## 2. Content integration (Methods A and B)

**Method A — bundled content mod (primary).** `arabic/stage_mod.py` builds the mod package:

    Mods/content.arabic_hesham/
    ├── manifest.json        (arabic/manifest.json: kind "content", game_id "wwhd")
    └── content/
        ├── Common/Pack/permanent_2d_UsEnglish.pack
        └── Common/Layout/Title_00.szs

The runtime's mod manager already maps content replacements by game path
(`runtime/src/mods/content.cpp`): the game's read of `/vol/content/Common/Pack/
permanent_2d_UsEnglish.pack` is redirected to the mod's file, and the cross-region rule maps a
translated pack under any region name onto the pack the game loads. The title screen archive is a
plain path replacement.

On Xbox the packaged app ships the staged tree under `BundledMods/content.arabic_hesham` (next to
the executable; CMake stages it from `.local/arabic/` when present). On first start the mod manager
copies it into the player's mod directory, enables it, and reports the install in the log
(`runtime/src/mods/packages.cpp`, `sync_bundled`). Removing or disabling the installed mod is the
player's choice and is respected afterwards.

**Method B — preparation overlay (explicit).** `arabic/stage_mod.py --overlay GAME_ROOT` bakes the
two files into a prepared game tree (`game/content/...`) instead of shipping a mod. Useful when
preparing on a PC or when the mod system must stay untouched. The on-console preparation pipeline
does not do this automatically: Method A gives the same result with runtime control (the mod can be
disabled) and does not modify the extracted game.

## 3. Right-to-left text activation (Step 2)

The runtime ships a full Arabic engine (`runtime/src/rtl_text.cpp`: joining forms, presentation
Forms-A/B, lam-alef ligatures, harakat; UAX #9 bidi) applied inside NintendoWare's text writer by
`runtime/src/rtl_text_hooks.cpp` (`TextWriterBase::PrintImpl` 0x028709E0, `CharStrmReader`
0x02871328, `CharWriter::PrintGlyph` 0x0286E8B4, `lyt::TextBox::DrawSelf` 0x028785C8).

Activation works through three gates, checked when the game opens a 2D language pack
(`runtime/src/hle/fs.cpp` reports the open to `rtl_text::language_pack_opened` with the *host*
path — the mod's file when the Arabic mod replaced it):

1. **Font scan** — `game_font::pack_font` parses the pack's `CKingMsg_bffnt.szs` → `CKingMsg.bffnt`
   CMAP. The runtime counts base Arabic letters (U+0621–U+064A) **and now Arabic presentation
   forms** (U+FE70–U+FEFC). Twenty or more of either turns right-to-left text on. The forms count
   was added for packs like Hesham's, whose font can map the shaped Forms-B glyphs with few or no
   base codepoints; before, such a font silently stayed off.
2. **Mod force** — when a content mod whose ID starts with `content.arabic` is enabled
   (`mods/packages.cpp` → `rtl_text::set_language_forced`), right-to-left text is forced on for the
   pack even if the font scan finds nothing; with an unreadable font the text is still reordered
   right to left (base letter forms), and the log says so.
3. **Escape hatch** — `WWHD_RTL=0` keeps everything off; `WWHD_RTL=1` forces it on for any pack
   (debugging); `WWHD_RTL_TRACE=1` logs the bidi/shaping plan per print.

`arabic/verify_pack.py` runs the same parsing pipeline offline and prints the counts the runtime
will see (base letters, Forms-A/B, lam-alef ligatures 0xFEF5–0xFEFC, harakat 0x064B–0x0652), the
activation verdict, and per-letter shaping coverage (a mapped joining letter with no presentation
form would render disconnected — the shaping engine falls back to the base letter, it never drops
a character). Its parsers are covered by `arabic/tests/test_pack_parsers.py` against synthetic
SARC/Yaz0/BFFNT fixtures, so no game asset is needed to test them.

## 4. The Windfall pirate door riddle bypass (Step 3)

Hesham's Cemu patch (`arabic/patch_arabic_native.asm`) edits the door's two functions in the USA
game:

| Address | Cemu patch | Encoding | Function |
| --- | --- | --- | --- |
| `0x021A4920` | `li r9, 1` | `0x39200001` | `actionPassward2` (`wwhd_actionPassward2_021A4808`): sets the password-correct flag |
| `0x021A4784` | `b 0x021A47C4` | `0x48000040` | `chkPassward` (`wwhd_chkPassward_021A45C8`): skips the password comparison, jumping straight to the riddle-answered path |

Why: with the translation, the door's password is typed on the game's letter keyboard in Arabic
letters — impossible to complete with the riddle's expected letters on an English console setup,
so the patch makes Link answer the riddle directly.

A Cemu `.asm` patch cannot run in this port: the game's PowerPC is translated ahead of time. The
equivalent here applies the same two edits **to the game image during preparation, before
translation** (`platforms/uwp-game/prepare_game.py`, `ARABIC_NATIVE_PATCHES`):

1. Preparation verifies the disc image is the USA release (SHA-256) — the same build Hesham's patch
   targets, which pins what is at those addresses.
2. After `recomp.Recompiler` analyses the image, the two words are replaced in the analysed
   program (`Recompiler.p.words` / `.text.data`) and translation proceeds. The translated C therefore
   contains exactly the patched instruction, with the containing function reported in the log (the
   Cemu patch works on addresses alone; so does this one).
   The `b` lands inside `chkPassward`, so the translator emits an in-function `goto`; the `li`
   replaces a mid-function instruction, so no function boundaries move and the translated-function
   count check still passes.
3. After translation, `verify_arabic_native` requires both instruction comments
   (`/* 021A4784: 48000040 */`, `/* 021A4920: 39200001 */`) to be present in the generated
   `code_*.c`; preparation fails loudly otherwise, and reports `PASS arabic-native` lines.

The edits live only in the translated game on the player's USB drive — the original disc image is
not modified.

## 5. Building the package

1. Build the UWP app as upstream does (Windows, Clang for UWP; see the root `README.md`).
2. Stage the translation once:
   `python3 arabic/fetch_patch.py && python3 arabic/stage_mod.py --zip build/arabic/Arabic.Hesham.Zelda.WW.zip --out .local/arabic/staged`
   (the CMake cache path `WWHD_ARABIC_MOD` points at the staged folder; default
   `.local/arabic/content.arabic_hesham`).
3. Configure `platforms/uwp-game` — the build bundles the staged mod as `BundledMods/` next to the
   executable and packages it into the `.appx`/`.msix` with the rest of the package layout. To sign
   for Xbox Developer Mode, use your own certificate, as upstream: install the `.appx` through the
   Xbox Device Portal and set the app to **Game** in Dev Home.
4. Optional checks on a PC:
   `python3 arabic/verify_pack.py <staged pack>` and `python3 arabic/tests/run_tests.py`.
   The same checks (plus the RTL engine's own test and compile checks of the changed runtime
   sources) run on GitHub on every push: `.github/workflows/arabic-checks.yml`.

## 6. What runs where

| Piece | Where | File |
| --- | --- | --- |
| Fetch + verify the translation archive | build PC | `arabic/fetch_patch.py` |
| Stage the mod (A) / overlay the game tree (B) | build PC / any | `arabic/stage_mod.py` |
| Bundle into the app package | build PC (CMake) | `platforms/uwp-game/CMakeLists.txt`, `cmake/CopyMod.cmake` |
| Install + enable the bundled mod, force RTL | console, first start | `runtime/src/mods/packages.cpp` |
| RTL activation + shaping + bidi | console, runtime | `runtime/src/rtl_text*.cpp`, `runtime/src/hle/fs.cpp` |
| Windfall door bypass | console, preparation | `platforms/uwp-game/prepare_game.py` |
| Offline verification of the pack | any | `arabic/verify_pack.py`, `arabic/tests/` |
