# WWHD UWP — Arabic Edition

UWP adaptation of [ZeldaWWHDRecomp](https://github.com/ZeldaWWHDRecomp/ZeldaWWHDRecomp) for Xbox Developer Mode, integrating **Arabic Hesham's complete Arabic translation** of The Wind Waker HD: translated dialogue and UI, the Arabic bitmap font with native right-to-left rendering, shaping and bidi, the localized title screen, and his Windfall pirate-door riddle bypass — all in one UWP package.

**Playable at 30 FPS on Xbox Series S, based on user testing.**

**This port is experimental. Work is ongoing to improve performance and optimize the runtime.**

## Arabic integration

| What | How |
| --- | --- |
| Translation assets (dialogue, UI, font, title screen) | Bundled content mod `content.arabic_hesham`, auto-installed and enabled on first start. Fetched and SHA-256-verified from [Arabic Hesham's official release](https://arabichesham.com/games/the-legend-of-zelda-the-wind-waker-hd) at build time (`arabic/fetch_patch.py`); never redistributed from this repository. |
| Right-to-left rendering | The runtime's Arabic engine (shaping, presentation Forms-A/B, lam-alef ligatures, harakat, UAX #9 bidi) applied inside NintendoWare's text writer; forced on while the Arabic mod is active (`runtime/src/rtl_text_hooks.cpp`). |
| Windfall pirate door riddle | Hesham's PPC patch applied at preparation time to the translated game (`platforms/uwp-game/prepare_game.py`): Link answers the riddle directly — no Arabic keyboard needed. |

Design and build instructions: **[docs/arabic.md](docs/arabic.md)** · tooling: **[arabic/](arabic/README.md)** · offline tests: `python3 arabic/tests/run_tests.py`.

To build the package with the translation, stage it once before configuring CMake:

```sh
python3 arabic/fetch_patch.py
python3 arabic/stage_mod.py --zip build/arabic/Arabic.Hesham.Zelda.WW.zip --out .local/arabic/staged
```

## Upstream features

- Select your WUX/WUD from any folder on USB.
- Extract, translate, compile and verify your own game directly on the console. Prepared files remain on USB and are reused on later launches.
- Upstream graphics, controller, audio and gameplay settings.
- Vulkan rendering through Mesa Dozen / Direct3D 12 and UWP input, storage and lifecycle support.

## Installation

Install the APPX through Xbox Device Portal and set the application to **Game** in Dev Home.

Keep your original USA WUX/WUD, matching disc `.key` and `common.key` together on USB. Allow at least 3 GiB of additional free space. Choose **Browse USB**, select the image and keep the drive connected during preparation and gameplay. Later, choose **Play game**.

You must own the original game; this repository contains no game images, keys or game-derived assets, and the Arabic translation is downloaded from its author's own release.

## Source and credits

This repository is a source overlay for upstream commit `f10b56621ed13e0053e7cf8190e740834377e45a` with the Arabic integration. It includes the UWP adaptation and embedded preparation hosts. Public upstream tooling and external dependencies are required to build it.

No game images, keys, generated game instructions, private certificates or personal automation are included. Game translation and compilation occur locally from the user's copy.

See [CREDITS.md](CREDITS.md). Runtime source is licensed under [MPL-2.0](LICENSE); third-party licenses remain applicable.
