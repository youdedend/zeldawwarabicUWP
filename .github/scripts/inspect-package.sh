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

for path in sorted(glob.glob("package/*.exe") + glob.glob("package/*.dll")):
    try:
        pe = pefile.PE(path, fast_load=True)
        pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]])
        imports = [e.dll.decode().lower() for e in getattr(pe, "DIRECTORY_ENTRY_IMPORT", [])]
        needed = [d for d in imports if not systemish.match(d)]
        emit("imports " + os.path.basename(path), needed or ["(only system DLLs)"])
    except Exception as error:
        emit("imports " + os.path.basename(path), [f"ERROR {error}"])

manifest = open("package/AppxManifest.xml", encoding="utf-8-sig").read()
for tag, pattern in (("app", r"<Applications>.*?</Applications>"),
                     ("deps", r"<Dependencies>.*?</Dependencies>"),
                     ("caps", r"<Capabilities>.*?</Capabilities>")):
    piece = re.search(pattern, manifest, re.S)
    emit("manifest " + tag, [piece.group(0)[:700] if piece else "NONE"])
PYEOF
