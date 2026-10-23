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

# The released zip wraps the app in an .appx (itself a zip) and ships the VCLibs
# runtime as a second appx under Dependency/: extract EVERY appx, since the game
# package holds SDL3.dll and the VCLibs package holds the *_app.dll runtime files.
i=0
for appx in $(find released -iname "*.appx"); do
    i=$((i + 1))
    echo "extracting $appx"
    cp "$appx" "inner-$i.zip"
    pwsh -NoProfile -Command "Expand-Archive -Path 'inner-$i.zip' -DestinationPath 'released/appx-$i' -Force" 2>/dev/null \
      || powershell -NoProfile -Command "Expand-Archive -Path 'inner-$i.zip' -DestinationPath 'released/appx-$i' -Force"
done

dll=$(find released -iname "SDL3.dll" | head -1)
[ -n "$dll" ] || { echo 'FATAL: the released package has no SDL3.dll' >&2; find released -name "*.dll" | head; exit 1; }
mkdir -p artifacts/jyrs
cp "$dll" artifacts/jyrs/SDL3.dll
# Also stash the VCLibs runtime DLLs: the package must carry them itself (the
# console's missing VCLibs framework is the instant-exit-at-startup cause;
# SDL3 imports vccorlib140_app.dll at load).
vcdir=artifacts/jyrs/vc-rt
mkdir -p "$vcdir"
find released -name "*_app.dll" -exec cp {} "$vcdir/" \; 2>/dev/null || true
vc_count=$(ls "$vcdir" 2>/dev/null | wc -l)
[ "$vc_count" -ge 5 ] || { echo "FATAL: expected the bundled VC runtime DLLs in the released package (found $vc_count)" >&2; exit 1; }
ls -la artifacts/jyrs "$vcdir"
echo "PASS sdl3 ($(stat -c %s artifacts/jyrs/SDL3.dll) bytes, $vc_count runtime DLLs)"
