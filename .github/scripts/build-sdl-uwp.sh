#!/usr/bin/env bash
# Builds the SDL3 UWP fork with this repo's input patches (bash: predictable quoting).
# Produces artifacts/sdl-uwp/: SDL3.lib, SDL3.dll, include/ (WWHD_SDL_BUILD + WWHD_SDL_SOURCE).
set -euo pipefail
root=$PWD
trace=$(mktemp)
exec >"$trace" 2>&1
trap 'status=$?; cat "$trace"; if [ $status -ne 0 ]; then tail -n 40 "$trace" | tr "\n" "~" | fold -w 900 | sed "s/^/::error::[sdl] /"; fi' EXIT

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
