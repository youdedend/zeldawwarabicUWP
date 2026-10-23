WWHD-UWP **Arabic Edition** — The Wind Waker HD with Hesham's Arabic translation (موقظ الرياح), built entirely on GitHub Actions.

## Downloads

| File | What it is |
|---|---|
| `wwhd-uwp-arabic.appx` | The game, ready to play, with the Arabic translation **inside**. Install/update this one. App version **0.1.4.0**. |
| `Arabic-Hesham-mod.zip` | Optional: the same translation as a standalone mod (for other WWHD-UWP installs). |
| `wwhd-uwp-arabic.cer` / `.pfx` | The self-signing certificate (CN=WWHDRecompDevelopment, PFX password `wwhd-uwp-arabic`). |

## Install / update (Xbox Dev Mode)

1. Device Portal → *Apps → Install app package* (or *File explorer* → Trusted People for `wwhd-uwp-arabic.cer` first, if this is the first install).
2. Deploy `wwhd-uwp-arabic.appx`. Updating over an existing install (same app, version 0.1.4.0) **keeps your save data and prepared game**.
3. Dev Home → set the app's **App type to Game**.

## Getting the Arabic translation (v0.1.4.0)

Arabic is **baked in during game preparation** — no mod installation, no file picker:

1. USB stick: your USA Wind Waker HD image (WUX/WUD) + `common.key` + the matching disc `.key`.
2. Launch the game → preparation screen → *Browse USB* → select your image → **Prepare** (one-time: extract, translate, compile; keep the drive connected).
3. When it finishes, choose **Play** — the game runs with the full Arabic translation, right-to-left text (activates automatically) and the Windfall pirate-door riddle bypass.

## Source code

The `Source code (zip)` / `Source code (tar.gz)` links are the complete tree: the runtime RTL engine, the bundled Arabic integration, the UWP CPython/SDL/LLVM build system, the mod tooling and all workflows.
