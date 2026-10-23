#!/usr/bin/env bash
# Builds CPython 3.11 as a UWP component (platforms/uwp-python) and packs the standard library.
# Produces artifacts/python-uwp/: wwhd-python.dll, python311.lib, wwhd-python-host.lib, python311.zip
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

trap 'status=$?; exec 1>&3 2>&4; cat "$trace"; if [ $status -ne 0 ]; then tr -d "\\r" < "$trace" > "$trace.clean"; grep -E "FAILED:|error C[0-9]|fatal error|error LNK|error MSB|ninja: build stopped|CMake Error|error:" "$trace.clean" | head -20 > "$trace.err" || true; if [ -s "$trace.err" ]; then fold -w 850 "$trace.err" | sed "s/^/::error::[python] /"; fi; tail -n 25 "$trace.clean" | tr "\\n" "~" | fold -w 900 | sed "s/^/::error::[python] tail /"; fi' EXIT

CPYTHON_VERSION=v3.11.17
ZLIB_VERSION=1.3.1

echo "== CPython $CPYTHON_VERSION + zlib $ZLIB_VERSION =="
if [ ! -d deps-zlib ]; then
    curl -sL -o zlib.tar.gz "https://github.com/madler/zlib/archive/refs/tags/v$ZLIB_VERSION.tar.gz"
    tar -xzf zlib.tar.gz
    mv "zlib-$ZLIB_VERSION" deps-zlib
fi

# Upstream's UWP support patch (WWHD_UWP guards over getpath.c, posixmodule, _io, ...).
# The Windows checkout can deliver the patch with CRLF line endings: normalize like the SDL patches.
UWP_PATCH="$root/platforms/uwp-python/patches/cpython-3.11.17-uwp.patch"
uwp_patch_lf="$root/uwp-patch-lf.tmp"
tr -d '\r' < "$UWP_PATCH" > "$uwp_patch_lf"

# Classify the tree: 'fresh' (patch applies), 'patched' (exactly the current patch is
# in place) or 'stale' (an older patch revision - useless, re-extract). A cached tree
# from an earlier revision of this patch would otherwise poison the build.
state=stale
if [ -d deps-cpython ]; then
    if git -C deps-cpython apply --check "$uwp_patch_lf" 2>/dev/null; then
        state=fresh
    elif git -C deps-cpython apply --reverse --check "$uwp_patch_lf" 2>/dev/null; then
        state=patched
    fi
fi
if [ -d deps-cpython ] && [ "$state" = stale ]; then
    echo "cached CPython tree has an outdated patch state: re-extracting a fresh tree"
    rm -rf deps-cpython
fi
if [ ! -d deps-cpython ]; then
    curl -sL -o cpython.tar.gz "https://github.com/python/cpython/archive/refs/tags/$CPYTHON_VERSION.tar.gz"
    tar -xzf cpython.tar.gz
    mv "cpython-${CPYTHON_VERSION#v}" deps-cpython
    state=fresh
fi
# git apply needs a repository anchored at THIS tree: without its own .git, git
# discovers the Actions checkout's repo above and resolves patch paths against that
# root - silently applying NOTHING while exiting 0 (reproduced locally, exact match
# with the runner's failure and its [attr] warnings).
[ -e deps-cpython/.git ] || git -C deps-cpython init -q
# NOTE: set -e is suspended inside if/then bodies, so applies carry explicit || FATAL.
if [ "$state" = fresh ]; then
    git -C deps-cpython apply "$uwp_patch_lf" || { echo "FATAL: git apply failed after a successful check" >&2; exit 1; }
    echo "applied cpython-3.11.17-uwp.patch"
else
    echo "cpython-3.11.17-uwp.patch already applied (current revision verified)"
fi
rm -f "$uwp_patch_lf"
# Verify the patch really took effect (representative hunks in three files).
for probe in "PC/pyconfig.h:WWHD_UWP" "Modules/timemodule.c:define tzset() ((void)0)" "Modules/posixmodule.c:WWHD_UWP"; do
    file="deps-cpython/${probe%%:*}"
    needle="${probe#*:}"
    grep -q "$needle" "$file" || { echo "FATAL: $file lacks the patched content ($needle) - the UWP patch did not land" >&2; exit 1; }
done
echo "UWP patch content verified in PC/pyconfig.h, timemodule.c, posixmodule.c"

# deepfreeze.c is generated during a CPython build and absent from the source tarball; the
# workflow builds it on Linux (host-independent C) and hands it over via DEEPFREEZE_C.
# Both installs FAIL LOUDLY when set but missing: a silent skip costs a whole CI round-trip.
if [ -n "${DEEPFREEZE_C:-}" ]; then
    if [ ! -f "$DEEPFREEZE_C" ]; then
        echo "FATAL: DEEPFREEZE_C is set but the file is missing: $DEEPFREEZE_C" >&2
        find artifacts/cpython-deepfreeze -type f 2>/dev/null || true
        exit 1
    fi
    mkdir -p deps-cpython/Python/deepfreeze
    cp "$DEEPFREEZE_C" deps-cpython/Python/deepfreeze/deepfreeze.c
    echo "deepfreeze.c installed ($(stat -c %s deps-cpython/Python/deepfreeze/deepfreeze.c) bytes)"
fi
# getpath.h (generated frozen bytecode for getpath.py) is included by Modules/getpath.c.
if [ -n "${GETPATH_H:-}" ]; then
    if [ ! -f "$GETPATH_H" ]; then
        echo "FATAL: GETPATH_H is set but the file is missing: $GETPATH_H" >&2
        find artifacts/cpython-getpath-h -type f 2>/dev/null || true
        exit 1
    fi
    mkdir -p deps-cpython/Python/frozen_modules
    cp "$GETPATH_H" deps-cpython/Python/frozen_modules/getpath.h
    echo "getpath.h installed ($(stat -c %s deps-cpython/Python/frozen_modules/getpath.h) bytes)"
fi
# Last line of defense: the generate step cannot succeed without these two generated files.
[ -f deps-cpython/Python/deepfreeze/deepfreeze.c ] || { echo "FATAL: deepfreeze.c still absent from the source tree" >&2; exit 1; }
[ -f deps-cpython/Python/frozen_modules/getpath.h ] || { echo "FATAL: getpath.h still absent from the source tree" >&2; exit 1; }

echo '== Building wwhd-python (UWP) =='
fresh_build "$root/build/python"
cmake -S "$(cygpath -m "$PWD/platforms/uwp-python")" -B "$(cygpath -m "$root/build/python")" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DWWHD_PYTHON_SOURCE="$(cygpath -m "$PWD/deps-cpython")" -DWWHD_ZLIB_SOURCE="$(cygpath -m "$PWD/deps-zlib")"
cmake --build "$(cygpath -m "$root/build/python")" --target wwhd-python wwhd-python-host

echo '== Packing the standard library (python311.zip) =='
mkdir -p artifacts/python-uwp
python - deps-cpython/Lib artifacts/python-uwp/python311.zip <<'EOF'
import sys, zipfile, os
lib, out = sys.argv[1], sys.argv[2]
excluded = {'__pycache__', 'test', 'tests', 'idlelib', 'tkinter', 'turtledemo',
            'site-packages', 'config-3.11', 'dist-packages'}
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for folder, dirs, files in os.walk(lib):
        rel = os.path.relpath(folder, lib).replace(os.sep, '/')
        parts = rel.split('/')
        if parts[0] in excluded or '__pycache__' in parts:
            dirs[:] = []
            continue
        for f in files:
            if f.endswith(('.pyc', '.exe', '.dll')):
                continue
            z.write(os.path.join(folder, f), os.path.relpath(os.path.join(folder, f), lib))
print('python311.zip written')
EOF

find build/python -name 'wwhd-python.dll' -exec cp {} artifacts/python-uwp/ \;
find build/python -name 'python311.lib' -exec cp {} artifacts/python-uwp/ \;
find build/python -name 'wwhd-python-host.lib' -exec cp {} artifacts/python-uwp/ \;
ls -la artifacts/python-uwp
echo 'PASS python-uwp'
