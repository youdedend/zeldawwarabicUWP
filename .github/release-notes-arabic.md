WWHD-UWP **Arabic Edition** — The Wind Waker HD with Hesham's Arabic translation (موقظ الرياح), built entirely on GitHub Actions.

## Downloads

| File | What it is |
|---|---|
| `wwhd-uwp-arabic-full.appx` | **Recommended.** Self-contained recompiled runtime: the Arabic mod is **bundled and enabled automatically**, the RTL text engine switches on by itself, and the Windfall pirate-door riddle bypass is built in. |
| `wwhd-uwp-arabic.appx` | Light build on the released WWHD-UWP v0.1.2 runtime with the Arabic files and the door bypass injected. The mod must be enabled once manually (below). |
| `Arabic-Hesham-mod.zip` | The translation as a standalone mod folder (for any WWHD-UWP install). |
| `*.pfx` / `*.cer` | The self-signing certificate (CN=WWHDRecompDevelopment, PFX password `wwhd-uwp-arabic`). |

## Install (Windows)

1. Install `wwhd-uwp-arabic.cer` into *Trusted People* of the Local Machine certificate store.
2. Double-click the `.appx` (or `Add-AppxPackage .\wwhd-uwp-arabic.appx`).

## Install (Xbox Dev Mode)

1. Open the Device Portal in a browser (*Home → Remote Access* or the IP shown in Dev Home).
2. *Apps → Install certificate* (or *File explorer* → install `wwhd-uwp-arabic.cer` to Trusted People).
3. Deploy the `.appx` under *Apps → Install app package*.

## Enabling the Arabic translation

- **`wwhd-uwp-arabic-full.appx`: nothing to do** — the mod ships inside and activates itself (right-to-left text included).
- **`wwhd-uwp-arabic.appx` / standalone mod:**
  1. Download `Arabic-Hesham-mod.zip` and extract it — you get a `content.arabic_hesham` folder.
  2. In-game: *Settings → Mods → More → Mods folder* (this opens the game's mods folder).
  3. Copy `content.arabic_hesham` into that folder, restart the game.
  4. *Settings → Mods* — select the mod and enable it.

The RTL text engine activates automatically once the Arabic mod is active (the font check is built into the runtime of the full package).

## Source code

The `Source code (zip)` / `Source code (tar.gz)` links are the complete tree for these packages: runtime RTL edits, the bundled-mod loader, the door-riddle bypass, mod tooling and all build workflows.
