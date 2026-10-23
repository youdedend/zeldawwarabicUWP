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

trap 'status=$?; exec 1>&3 2>&4; cat "$trace"; if [ $status -ne 0 ]; then tail -n 50 "$trace" | tr "\n" "~" | fold -w 900 | sed "s/^/::error::[python] /"; fi' EXIT

CPYTHON_VERSION=v3.11.17
ZLIB_VERSION=1.3.1

echo "== Downloading CPython $CPYTHON_VERSION and zlib $ZLIB_VERSION =="
if [ ! -d deps-cpython ]; then
    curl -sL -o cpython.tar.gz "https://github.com/python/cpython/archive/refs/tags/$CPYTHON_VERSION.tar.gz"
    tar -xzf cpython.tar.gz
    mv "cpython-${CPYTHON_VERSION#v}" deps-cpython
fi
if [ ! -d deps-zlib ]; then
    curl -sL -o zlib.tar.gz "https://github.com/madler/zlib/archive/refs/tags/v$ZLIB_VERSION.tar.gz"
    tar -xzf zlib.tar.gz
    mv "zlib-$ZLIB_VERSION" deps-zlib
fi

# Upstream's UWP support patch (WWHD_UWP guards over getpath.c, posixmodule, _io, ...):
# idempotent — apply once; if it no longer applies it is already in place (reverse-check).
UWP_PATCH="$root/platforms/uwp-python/patches/cpython-3.11.17-uwp.patch"
if git -C deps-cpython apply --check "$UWP_PATCH" 2>/dev/null; then
    git -C deps-cpython apply "$UWP_PATCH"
    echo "applied cpython-3.11.17-uwp.patch"
elif git -C deps-cpython apply --reverse --check "$UWP_PATCH" 2>/dev/null; then
    echo "cpython-3.11.17-uwp.patch already applied"
else
    echo "FATAL: the UWP patch neither applies nor reverses on this CPython tree" >&2
    exit 1
fi

# deepfreeze.c is generated during a CPython build and absent from the source tarball; the
# workflow builds it on Linux (host-independent C) and hands it over via DEEPFREEZE_C.
if [ -n "${DEEPFREEZE_C:-}" ] && [ -f "$DEEPFREEZE_C" ]; then
    mkdir -p deps-cpython/Python/deepfreeze
    cp "$DEEPFREEZE_C" deps-cpython/Python/deepfreeze/deepfreeze.c
    echo "deepfreeze.c installed ($(stat -c %s deps-cpython/Python/deepfreeze/deepfreeze.c) bytes)"
fi

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
