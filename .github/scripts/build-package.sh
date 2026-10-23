#!/usr/bin/env bash
# Builds the WWHD-UWP Arabic Edition package: runtime (dynamic game code + unified on-console
# preparation), staged Arabic mod, Tools/ and CompilerHeaders/ for on-console preparation, then
# MakeAppx + a self-signed signature (the unsigned APPX is kept for signing with your own cert).
# Expects artifacts/ populated by the other scripts (clang-uwp, sdl-uwp, python-uwp, mesa-driver,
# vulkan-headers, upstream-tools) — see the uwp-package workflow.
set -euo pipefail
root=$PWD
trace=$(mktemp)
exec >"$trace" 2>&1
trap 'status=$?; cat "$trace"; if [ $status -ne 0 ]; then tail -n 45 "$trace" | tr "\n" "~" | fold -w 900 | sed "s/^/::error::[package] /"; fi' EXIT

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
cmake -S "$(cygpath -m "$root/platforms/uwp-game")" -B "$(cygpath -m "$root/build/game")" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$clang_cl" -DCMAKE_CXX_COMPILER="$clang_cl" \
    -DCMAKE_SYSTEM_NAME=WindowsStore -DCMAKE_SYSTEM_VERSION=10.0 \
    -DWWHD_SDL_SOURCE="$art_win/sdl-src" \
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
cp artifacts/sdl-uwp/SDL3.dll package/
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
"$makeappx" pack /f "$mapping" /p "$root/wwhd-uwp-arabic-unsigned.appx" /o

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
"$signtool" sign /fd SHA256 /f "$root_win/wwhd-uwp-arabic.pfx" /p 'wwhd-uwp-arabic' "$root_win/wwhd-uwp-arabic.appx"

echo '== Package artifacts =='
ls -la wwhd-uwp-arabic*
echo 'PASS package'
