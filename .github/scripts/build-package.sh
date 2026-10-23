#!/usr/bin/env bash
# Builds the WWHD-UWP Arabic Edition package: runtime (dynamic game code + unified on-console
# preparation), staged Arabic mod, Tools/ and CompilerHeaders/ for on-console preparation, then
# MakeAppx + a self-signed signature (the unsigned APPX is kept for signing with your own cert).
# Expects artifacts/ populated by the other scripts (clang-uwp, sdl-uwp, python-uwp, mesa-driver,
# vulkan-headers, upstream-tools) — see the uwp-package workflow.
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

trap 'status=$?; exec 1>&3 2>&4; cat "$trace"; if [ $status -ne 0 ]; then tr -d "\\r" < "$trace" > "$trace.clean"; grep -E "FAILED:|error C[0-9]|fatal error|error LNK|error MSB|ninja: build stopped|CMake Error|error:" "$trace.clean" | head -20 > "$trace.err" || true; if [ -s "$trace.err" ]; then fold -w 850 "$trace.err" | sed "s/^/::error::[package] /"; fi; tail -n 25 "$trace.clean" | tr "\\n" "~" | fold -w 900 | sed "s/^/::error::[package] tail /"; fi' EXIT

art=$root/artifacts
art_win=$(cygpath -m "$art")          # D:/... mixed mode: CMake- and MSYS-safe
root_win=$(cygpath -m "$root")
profile_text='arabic-unified-1'

echo '== Host tools for FetchContent (glslang, zlib source dirs) =='
mkdir -p .local/host-tools/_deps
if [ ! -d .local/host-tools/_deps/glslang-src ]; then
    curl -sL -o glslang.tar.gz "https://github.com/KhronosGroup/glslang/archive/refs/tags/${GLSLANG_TAG}.tar.gz"
    tar -xzf glslang.tar.gz
    mv "glslang-${GLSLANG_TAG}" .local/host-tools/_deps/glslang-src
fi
if [ ! -d .local/host-tools/_deps/zlib-src ]; then
    curl -sL -o zlibfc.tar.gz "https://github.com/madler/zlib/archive/refs/tags/v${ZLIB_TAG}.tar.gz"
    tar -xzf zlibfc.tar.gz
    mv "zlib-${ZLIB_TAG}" .local/host-tools/_deps/zlib-src
fi

echo '== Building the runtime (dynamic game code, unified preparation, Ninja + clang-cl) =='
clang_cl=$(command -v clang-cl || echo '/c/Program Files/LLVM/bin/clang-cl.exe')
if [ -f "$(cygpath -u "$clang_cl" 2>/dev/null || echo "$clang_cl")" ]; then clang_cl=$(cygpath -m "$clang_cl"); else clang_cl='C:/Program Files/LLVM/bin/clang-cl.exe'; fi
echo "clang-cl: $clang_cl"
fresh_build "$root/build/game"
cmake -S "$(cygpath -m "$root/platforms/uwp-game")" -B "$(cygpath -m "$root/build/game")" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$clang_cl" -DCMAKE_CXX_COMPILER="$clang_cl" \
    -DCMAKE_SYSTEM_NAME=WindowsStore -DCMAKE_SYSTEM_VERSION=10.0 \
    -DWWHD_SDL_SOURCE="$art_win/sdl-uwp" \
    -DWWHD_SDL_BUILD="$art_win/sdl-uwp" \
    -DWWHD_VULKAN_HEADERS="$art_win/vulkan-headers/include" \
    -DWWHD_PYTHON_BUILD="$art_win/python-uwp" \
    -DWWHD_CLANG_BUILD="$art_win/clang-uwp" \
    -DWWHD_DYNAMIC_GAMECODE=ON -DWWHD_UNIFIED_PREPARATION=ON
cmake --build "$(cygpath -m "$root/build/game")" --target wwhd-uwp-game

echo '== Staging the package =='
exe=$(find build/game -name wwhd-uwp-game.exe | head -1)
[ -n "$exe" ] || { echo 'wwhd-uwp-game.exe not found after build'; exit 1; }
rm -rf package
mkdir -p package
cp "$exe" package/
# The dynamic gamecode path compiles/links through the LLVM bridge: without this DLL
# the app fails at startup, before any UI.
[ -f artifacts/clang-uwp/bin/wwhd-clang-bridge.dll ] || { echo 'FATAL: the clang bridge DLL is missing from artifacts (check the bridge job)'; exit 1; }
cp artifacts/clang-uwp/bin/wwhd-clang-bridge.dll package/
# Our fresh SDL3 build imports desktop-only DLLs (vccorlib140, mmdevapi) that do not
# exist on Xbox: the released package's SDL3.dll is the proven UWP binary - prefer it.
if [ -f artifacts/jyrs/SDL3.dll ]; then
    cp artifacts/jyrs/SDL3.dll package/SDL3.dll
else
    cp artifacts/sdl-uwp/SDL3.dll package/SDL3.dll
fi
cp artifacts/python-uwp/wwhd-python.dll package/
cp artifacts/python-uwp/python311.zip package/
cp artifacts/mesa-driver/*.dll package/
printf '%s' "$profile_text" > package/preparation-profile.txt
cp -r platforms/uwp-game/Assets package/Assets

cp -r artifacts/upstream-tools package/Tools

headers=package/CompilerHeaders
mkdir -p "$headers"
for h in ppc.h guest_addr.h recomp_table.h wwhd_guest_abi.h wwhd_mod.h verify_tap.h verify_tap_gen.h; do
    cp "runtime/include/$h" "$headers"
done
for h in stdint.h string.h math.h stdio.h stdlib.h; do
    cp "platforms/uwp-clang/include/$h" "$headers"
done

mod_source=$(find build/game -type d -name content.arabic_hesham -exec test -e '{}/manifest.json' ';' -print 2>/dev/null | head -1)
if [ -z "$mod_source" ]; then mod_source="$root/.local/arabic/content.arabic_hesham"; fi
[ -e "$mod_source/manifest.json" ] || { echo 'Arabic mod is not staged (run arabic/fetch_patch.py + arabic/stage_mod.py first)'; exit 1; }
mkdir -p package/BundledMods
cp -r "$mod_source" package/BundledMods/content.arabic_hesham
# CMake generates the manifest at configure time (Unified/Dynamic per the build mode).
[ -f build/game/AppxManifest.xml ] || { echo 'FATAL: CMake did not generate AppxManifest.xml' >&2; exit 1; }
cp build/game/AppxManifest.xml package/AppxManifest.xml

echo 'Package contents:'
ls -la package

echo '== Packing the APPX (MakeAppx) =='
sdk_bin=$(ls -d "/c/Program Files (x86)/Windows Kits/10/bin/"10.* 2>/dev/null | sort -V | tail -1)
[ -n "$sdk_bin" ] || { echo 'Windows SDK bin directory not found'; exit 1; }
makeappx="$sdk_bin/x64/makeappx.exe"
signtool="$sdk_bin/x64/signtool.exe"
mapping=$(mktemp)
{ echo '[Files]'
  (cd package && find . -type f | sed 's|^\./||' | while IFS= read -r rel; do
       printf '"%s\\%s" "%s"\n' "$root_win\\package" "$rel" "$rel"
   done)
} > "$mapping"
# MSYS auto-converts single-letter slash options to drive paths (/f -> F:/):
# exclude these two native tools from conversion and pass Windows paths explicitly.
mapping_win=$(cygpath -m "$mapping")
appx_win="$root_win/wwhd-uwp-arabic-unsigned.appx"
MSYS2_ARG_CONV_EXCL="*" "$makeappx" pack /f "$mapping_win" /p "$appx_win" /o

echo '== Signing (self-signed, CN=WWHDRecompDevelopment to match the manifest publisher) =='
powershell -NoProfile -Command "
\$ErrorActionPreference = 'Stop'
\$cert = New-SelfSignedCertificate -Type Custom -Subject 'CN=WWHDRecompDevelopment' \`
    -KeyUsage DigitalSignature -FriendlyName 'WWHD UWP Arabic Edition' \`
    -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 \`
    -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(5)
\$password = ConvertTo-SecureString -String 'wwhd-uwp-arabic' -Force -AsPlainText
Export-PfxCertificate -Cert \$cert -FilePath '$root_win\wwhd-uwp-arabic.pfx' -Password \$password | Out-Null
Export-Certificate -Cert \$cert -FilePath '$root_win\wwhd-uwp-arabic.cer' | Out-Null
"
cp wwhd-uwp-arabic-unsigned.appx wwhd-uwp-arabic.appx
# Report the staged package's imports and manifest as ::notice:: annotations: the
# sandbox-side channel for diffing this build against the proven-working fast build.
# This script's own stdout is redirected into the trace, so hand the inspector the
# saved real stdout/stderr (fd 3/4) - otherwise its notices never reach GitHub.
bash "$root/.github/scripts/inspect-package.sh" 1>&3 2>&4 || true
MSYS2_ARG_CONV_EXCL="*" "$signtool" sign /fd SHA256 /f "$root_win/wwhd-uwp-arabic.pfx" /p 'wwhd-uwp-arabic' "$root_win/wwhd-uwp-arabic.appx"

echo '== Package artifacts =='
ls -la wwhd-uwp-arabic*
echo 'PASS package'
