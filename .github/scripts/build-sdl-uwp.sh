#!/usr/bin/env bash
# Builds the SDL3 UWP fork with this repo's input patches (bash: predictable quoting).
# Produces artifacts/sdl-uwp/: SDL3.lib, SDL3.dll, include/ (WWHD_SDL_BUILD + WWHD_SDL_SOURCE).
set -euo pipefail
root=$PWD
trace=$(mktemp)
exec 3>&1 4>&2   # keep the real stdout for the exit trap (annotations must reach the log)
exec >"$trace" 2>&1

# The CMake build tree embeds absolute compiler paths: wipe it when the toolchain changed
# (a restored cache from another runner image would fail with dead paths).
fresh_build() {  # fresh_build <build-dir>
    local dir="$1" stamp="$VCINSTALLDIR|$VCToolsInstallDir"
    if [ -f "$dir/.toolchain" ] && [ "$(cat "$dir/.toolchain")" = "$stamp" ]; then
        echo "toolchain unchanged: incremental build in $dir"
    else
        echo "toolchain changed (or first build): wiping $dir"
        rm -rf "$dir"
        mkdir -p "$dir"
        printf '%s' "$stamp" > "$dir/.toolchain"
    fi
}

trap 'status=$?; exec 1>&3 2>&4; cat "$trace"; if [ $status -ne 0 ]; then tr -d "\\r" < "$trace" > "$trace.clean"; grep -E "FAILED:|error C[0-9]|fatal error|error LNK|error MSB|ninja: build stopped|CMake Error|error:" "$trace.clean" | head -20 > "$trace.err" || true; if [ -s "$trace.err" ]; then fold -w 850 "$trace.err" | sed "s/^/::error::[sdl] /"; fi; tail -n 25 "$trace.clean" | tr "\\n" "~" | fold -w 900 | sed "s/^/::error::[sdl] tail /"; fi' EXIT

echo '== Cloning SDL3_UWP =='
if [ ! -d sdl-src ]; then
    git clone --depth 1 https://github.com/rodrigoandrigo/SDL3_UWP sdl-src
fi
cd sdl-src
echo "SDL3_UWP commit: $(git rev-parse HEAD)"

echo '== Applying the repo SDL patches =='
for patch in sdl-pixel-format sdl-wgi-input; do
    tr -d '\r' < "$root/platforms/uwp-game/patches/$patch.patch" > "$RUNNER_TEMP/$patch.patch"
    if git apply --check --ignore-whitespace "$RUNNER_TEMP/$patch.patch" 2>/dev/null; then
        git apply --ignore-whitespace "$RUNNER_TEMP/$patch.patch"
    elif git apply --check --reverse --ignore-whitespace "$RUNNER_TEMP/$patch.patch" 2>/dev/null; then
        echo "$patch already applied (cached source tree)"
    else
        git apply --3way "$RUNNER_TEMP/$patch.patch"
    fi
done
cd "$root"

echo '== Building SDL3 (UWP shared, Ninja + the MSVC environment) =='
fresh_build "$root/build/sdl"
cmake -S "$(cygpath -m "$PWD/sdl-src")" -B "$(cygpath -m "$root/build/sdl")" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=WindowsStore -DCMAKE_SYSTEM_VERSION=10.0 \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
cmake --build "$(cygpath -m "$root/build/sdl")" --target SDL3-shared

dll=$(find build/sdl -name SDL3.dll | head -1)
lib=$(find build/sdl -name SDL3.lib | head -1)
[ -n "$dll" ] && [ -n "$lib" ] || { echo 'SDL3.dll/SDL3.lib not found after build'; exit 1; }
mkdir -p artifacts/sdl-uwp
cp "$dll" artifacts/sdl-uwp/SDL3.dll
cp "$lib" artifacts/sdl-uwp/SDL3.lib
rm -rf artifacts/sdl-uwp/include
cp -r sdl-src/include artifacts/sdl-uwp/include
ls -la artifacts/sdl-uwp
echo 'PASS sdl-uwp'
