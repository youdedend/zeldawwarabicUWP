# Changelog

## Arabic Edition (this repository)

- Arabic Hesham's translation integrated as the bundled content mod `content.arabic_hesham`: fetched and SHA-256-verified from his official release (`arabic/`), staged into the package as `BundledMods/`, installed and enabled on first start.
- Right-to-left text also activates on Arabic presentation forms (fonts that map Forms-A/B with few base letters), and is forced on while the Arabic mod is active (`rtl_text_hooks.cpp`, `mods/packages.cpp`).
- The Windfall pirate door riddle bypass (Hesham's `patch_arabic_native.asm`, two PowerPC edits) is applied during game preparation, before translation, and verified in the translated output (`platforms/uwp-game/prepare_game.py`).
- Offline verification tooling and tests for the pack parsers, the mod staging and the door patch (`arabic/verify_pack.py`, `arabic/tests/run_tests.py`).

## 0.1.2

- Unified USB selection, extraction, translation, compilation, verification and game launch.
- Reuse of completed preparations without recompiling the game.
- Folder browsing and a new English interface with staged progress, prepared for 1080p in 16:9.
- Dynamic loading of verified game objects from USB; the APPX contains no generated game instructions.

Playable at 30 FPS on Xbox Series S, based on user testing. An isolated graphics-driver startup crash has been reported.

## 0.0.2.13

- Added bounded vertex snapshot reuse with exact byte comparisons and submission-generation checks.
- Retained AVX2 texture checks, reduced guest-memory commitment and corrected Xbox controller mappings.
- Added CPU, texture, upload and GPU timing diagnostics.

30 FPS gameplay has been reported on Xbox Series S. This source release contains no installable APPX.
