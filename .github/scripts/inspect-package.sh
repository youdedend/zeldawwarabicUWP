#!/usr/bin/env bash
# Reports the package's static imports and manifest structure as ::notice::
# annotations: the channel for comparing the full build against the
# proven-working fast build when activation fails with 0x80070002.
set -euo pipefail
root=$PWD
exec 3>&1 4>&2
trace=$(mktemp)
exec >"$trace" 2>&1
trap 'status=$?; exec 1>&3 2>&4; cat "$trace"; if [ $status -ne 0 ]; then tail -n 25 "$trace" | tr "\n" "~" | fold -w 900 | sed "s/^/::error::[inspect] /"; fi' EXIT

python -m pip install -q pefile || pip install -q pefile || echo 'pefile unavailable - imports will be skipped' >&2
python3 - <<'PYEOF'
import glob, os, re, textwrap
import pefile

def emit(tag, lines):
    text = f"[{tag}] " + " | ".join(lines)
    for chunk in textwrap.wrap(text, 850):
        print(f"::notice::{chunk}")

systemish = re.compile(
    r"^(api-ms-|ext-ms-|ntdll|kernel32|user32|gdi32|shell32|advapi32|ole32|oleaut32|"
    r"ws2_32|bcrypt|ncrypt|crypt32|combase|rpcrt4|ucrtbase|msvcrt|vcruntime|msvcp|"
    r"concrt|dbghelp|winmm|sechost|shlwapi|usp10|dwrite|d3d11|dxgi|wintrust|wldp|"
    r"cryptbase|sspicli|kernelbase)", re.I)

# GitHub caps step annotations: report the load-critical modules first (the exe and
# its startup DLLs), then the manifest. Non-system imports are what the Xbox loader
# must resolve at process start; a miss there is an instant exit with no logs.
priority = ["wwhd-uwp-game.exe", "wwhd-python.dll", "SDL3.dll", "wwhd-clang-bridge.dll"]
paths = sorted(glob.glob("package/*.exe") + glob.glob("package/*.dll"))
paths.sort(key=lambda p: priority.index(os.path.basename(p)) if os.path.basename(p) in priority else 99)
reported = 0
for path in paths:
    if reported >= 6:
        emit("imports", ["(remaining modules skipped - annotation cap)"])
        break
    name = os.path.basename(path)
    if name not in priority:
        continue
    try:
        pe = pefile.PE(path, fast_load=True)
        pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]])
        imports = [e.dll.decode().lower() for e in getattr(pe, "DIRECTORY_ENTRY_IMPORT", [])]
        needed = [d for d in imports if not systemish.match(d)]
        emit("imports " + name, needed or ["(only system DLLs)"])
        reported += 1
    except Exception as error:
        emit("imports " + name, [f"ERROR {error}"])
        reported += 1

import os as _os
staged = sorted(f for f in _os.listdir("package") if f.lower().endswith(".dll"))
emit("staged dlls", [", ".join(staged) or "NONE"])

manifest = open("package/AppxManifest.xml", encoding="utf-8-sig").read()
app = re.search(r"<Applications>.*?</Applications>", manifest, re.S)
deps = re.search(r"<Dependencies>.*?</Dependencies>", manifest, re.S)
combined = ((deps.group(0) if deps else "") + " " + (app.group(0) if app else ""))[:800]
emit("manifest", [combined or "NONE"])
PYEOF
