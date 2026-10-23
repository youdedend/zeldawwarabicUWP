#!/usr/bin/env bash
# Grabs the SDL3.dll from the released JYRS20 package: the UWP binary proven on Xbox
# (our fresh SDL3 build imports desktop-only DLLs the console cannot resolve).
set -euo pipefail
root=$PWD
exec 3>&1 4>&2
trace=$(mktemp)
exec >"$trace" 2>&1
trap 'status=$?; exec 1>&3 2>&4; cat "$trace"; if [ $status -ne 0 ]; then tail -n 30 "$trace" | tr "\n" "~" | fold -w 900 | sed "s/^/::error::[sdl3] /"; fi' EXIT

[ -n "${UPSTREAM_RELEASE_ZIP:-}" ] || { echo 'FATAL: UPSTREAM_RELEASE_ZIP is not set' >&2; exit 1; }
echo "== Downloading the released package ($UPSTREAM_RELEASE_ZIP) =="
curl -sSL --retry 3 --retry-delay 5 -o released.zip "$UPSTREAM_RELEASE_ZIP"
ls -la released.zip
[ "$(stat -c %s released.zip)" -gt 1000000 ] || { echo 'FATAL: the download is suspiciously small' >&2; exit 1; }

echo '== Extracting =='
rm -rf released
pwsh -NoProfile -Command "Expand-Archive -Path released.zip -DestinationPath released -Force" 2>/dev/null \
  || powershell -NoProfile -Command "Expand-Archive -Path released.zip -DestinationPath released -Force"

dll=$(find released -iname "SDL3.dll" | head -1)
[ -n "$dll" ] || { echo 'FATAL: the released package has no SDL3.dll' >&2; find released -name "*.dll" | head; exit 1; }
mkdir -p artifacts/jyrs
cp "$dll" artifacts/jyrs/SDL3.dll
ls -la artifacts/jyrs
echo "PASS sdl3 ($(stat -c %s artifacts/jyrs/SDL3.dll) bytes)"
