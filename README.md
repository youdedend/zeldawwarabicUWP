# The Legend of Zelda: Wind Waker HD — Arabic Edition (UWP)

A self-contained **UWP package for Xbox Dev Mode and Windows** that plays your own copy of
*The Legend of Zelda: The Wind Waker HD* with **Hesham's full Arabic translation**
(موقظ الرياح) built in — right-to-left text, Arabic shaping and font, and a native bypass
for the Windfall pirate-door riddle that an Arabic player could never complete on an
English keyboard.

Built on top of [JYRS20's WWHD-UWP](https://github.com/JYRS20/WWHD-UWP) runtime
(itself an UWP adaptation of [ZeldaWWHDRecomp](https://github.com/ZeldaWWHDRecomp/ZeldaWWHDRecomp)),
with the translation by [Hesham Localization](https://arabichesham.com).

![CI](https://github.com/youdedend/zeldawwarabicUWP/actions/workflows/fast-package.yml/badge.svg?branch=arena%2F9b6f1103-zeldawwarabicuwp)

---

## What you get

| Feature | How it works |
|---|---|
| 🇸🇦 Full Arabic translation | Dialogue, UI strings and the Arabic bitmap font from Hesham's translation, baked into the game during preparation |
| ↔️ Right-to-left text | The runtime's RTL engine (Arabic shaping, lam-alef ligatures, presentation forms) switches on automatically when it sees the Arabic font |
| 🚪 Windfall door riddle bypass | The pirate-door password check is patched out at translation time — the riddle answers itself instead of demanding letters an Arabic player can't type |
| 🎮 Xbox Dev Mode + Windows | Same package family; deploy through the Xbox Device Portal or double-click on Windows |
| 💾 Your game, your save | No game files or keys are distributed: you prepare **your own** USA dump; save data survives app updates |

---

## Download

Grab **one file** from the [latest release](../../releases/latest):

| File | What it is |
|---|---|
| `wwhd-uwp-arabic.appx` | The game, ready to install. The Arabic translation is inside and is baked in when you prepare your copy. |
| `wwhd-uwp-arabic.cer` | The signing certificate (install once into *Trusted People*). |
| `Arabic-Hesham-mod.zip` | *(Optional)* The same translation as a standalone mod for any other WWHD-UWP install. |

Every update is published as a **new release** (`arabic-vX.Y.Z`) — old releases stay put,
and updating the app over an older version keeps your save data.

---

## Install on Xbox Dev Mode

1. **Dev Home** on the console → enable *Dev Mode* (one-time activation on
   [Xbox Developer Portal](https://www.xbox.com/developers)).
2. Open the **Device Portal** in a browser (`https://<console-ip>:11443`, shown in Dev Home).
3. *Apps → Install certificate* (or *File explorer* → Trusted People) → install
   **`wwhd-uwp-arabic.cer`** (first install only).
4. *Apps → Install app package* → deploy **`wwhd-uwp-arabic.appx`**.
5. **Dev Home → Games & apps → The Legend Of Zelda Wind Waker → App type: Game.**
   (The game needs the Game memory class — do this after every reinstall.)

On **Windows**: install the `.cer` into *Trusted People* (Local Machine), then
double-click the `.appx` (or `Add-AppxPackage .\wwhd-uwp-arabic.appx`).

---

## Prepare & play

The app never ships Nintendo's data — it prepares **your own** USA copy on the console:

1. On a PC, put on a USB stick (NTFS):
   - your **USA** Wind Waker HD image: `*.wux` or `*.wud`
   - `common.key`
   - the matching disc key, named exactly like the image plus `.key`
     (e.g. `The Wind Waker HD (USA).wux` → `The Wind Waker HD (USA).wux.key`)
2. Launch the app → the preparation screen appears.
3. **Browse USB** → select your image → **Prepare**.
4. Wait. One-time per image: extract → translate → compile (roughly 20–60 minutes;
   keep the drive connected; ~3 GiB of extra free space is used on the drive).
5. Choose **Play**.

What preparation bakes in: Hesham's Arabic language pack + font, the right-to-left
engine's trigger, and the Windfall door bypass — all verified by hash before the game
is declared ready. Later launches use the prepared files and start in seconds.

---

## Updating

Each app update is a new `arabic-vX.Y.Z` release. Install the new `.appx` over the old
app through the Device Portal — the version is higher, so it updates in place and
**keeps your save data and prepared game**. A re-preparation is only needed when a
release says so in its notes (for example when the baked-in translation changes).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| App opens and immediately exits | Set **App type: Game** in Dev Home (resets after reinstalls). |
| Preparation cannot find the image | The disc key must sit **next to** the image and be named `<image>.key`; `common.key` in the same folder. |
| "Unsupported game" during preparation | Only the **USA original release** (v0) dump is supported; the image hash is checked. |
| Preparation fails mid-way | See the on-screen error and `LocalState\WWHD\wwhd-console.log` via the Device Portal (*File explorer → LocalAppData → package → LocalState*). |
| Arabic text appears but letters are disconnected / left-to-right | You are on an old preparation: re-prepare once with v0.1.3.0 or later. |
| No Arabic at all after preparation | Check `wwhd-console.log` for the `PASS arabic-overlay` lines; without them the package predates the bake-in feature. |

---

## Building from source

GitHub Actions builds everything on every push:

- **Fast package** (`.github/workflows/fast-package.yml`): injects the Arabic
  integration into the released WWHD-UWP v0.1.2 package — minutes, cached.
- **Full package** (`.github/workflows/uwp-package.yml`): rebuilds the whole runtime
  from source — LLVM/Clang bridge (built once per source hash and reused via
  artifacts), SDL3, UWP CPython (with the frozen-module Linux stage), Mesa Dozen,
  the runtime itself, signed APPX.
- **Checks** (`.github/workflows/arabic-checks.yml`): the offline test suite
  (`python3 arabic/tests/run_tests.py`, 24 tests).

Build scripts live in `.github/scripts/*.sh` (bash, ERR-trap annotated), and every
generated file the CPython UWP build needs is produced by a parallel Linux stage and
fingerprint-cached. See `docs/arabic.md` for the full integration design.

## Project layout

```
├── arabic/                 translation tooling: fetch (hash-pinned), stage, verify + tests
├── platforms/
│   ├── uwp-game/           runtime host: entry, preparation UI, prepare_game.py, manifests
│   ├── uwp-python/         CPython 3.11 as a UWP component (+ UWP patch, sources)
│   ├── uwp-clang/          the on-console clang/LLVM bridge
│   └── uwp-extract/        embedded WUD/WUX disc extractor (CNG crypto)
├── runtime/src/            the recomp runtime: RTL engine, mod manager, Vulkan renderer…
├── cmake/                  build glue (dynamic bindings, bundled mods, …)
├── .github/
│   ├── workflows/          the three CI pipelines
│   └── scripts/            bash build/publish scripts
└── docs/arabic.md          the Arabic integration design document
```

## Credits & licenses

- [JYRS20/WWHD-UWP](https://github.com/JYRS20/WWHD-UWP) — the UWP runtime (MPL-2.0)
- [ZeldaWWHDRecomp](https://github.com/ZeldaWWHDRecomp/ZeldaWWHDRecomp) — the recompilation base
- [Hesham Localization](https://arabichesham.com) — the Arabic translation and font
- [Mesa](https://gitlab.freedesktop.org/mesa/mesa) — OpenGL/Vulkan-on-Dozen drivers
- [libsdl-org/SDL](https://github.com/libsdl-org/SDL),
  [rodrigoandrigo/SDL3_UWP](https://github.com/rodrigoandrigo/SDL3_UWP) — window/input
- [CPython 3.11](https://github.com/python/cpython),
  [LLVM/Clang 20](https://github.com/llvm/llvm-project) — on-console tooling

Runtime source is licensed MPL-2.0 like upstream; third-party licenses remain applicable.
**No game images, keys or copyrighted data are included in this repository or its
releases.** You must own and use your own copy of the game.
