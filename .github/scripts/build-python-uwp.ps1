# Builds CPython 3.11 as a UWP component (platforms/uwp-python) and packs the standard library
# for the package's python311.zip.
#
# Layout produced in artifacts/python-uwp/ (what WWHD_PYTHON_BUILD and the package expect):
#   wwhd-python.dll, python311.lib (its import library), wwhd-python-host.lib, python311.zip
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = $PWD.Path

Write-Host "== Downloading CPython $($env:CPYTHON_VERSION) and zlib $($env:ZLIB_VERSION) =="
foreach ($dep in @(
    @{ name = 'cpython'; url = "https://github.com/python/cpython/archive/refs/tags/$($env:CPYTHON_VERSION).tar.gz"; dir = "cpython-$($env:CPYTHON_VERSION.TrimStart('v'))" },
    @{ name = 'zlib'; url = "https://github.com/madler/zlib/archive/refs/tags/v$($env:ZLIB_VERSION).tar.gz"; dir = "zlib-$($env:ZLIB_VERSION)" }
)) {
    $file = "$($dep.name).tar.gz"
    if (-not (Test-Path $file)) { Invoke-WebRequest $dep.url -OutFile $file }
    if (-not (Test-Path $dep.dir)) { tar -xzf $file; Move-Item $dep.dir "deps-$($dep.name)" }
}
$cpython = Join-Path $root 'deps-cpython'
$zlib = Join-Path $root 'deps-zlib'

Write-Host '== Building wwhd-python (UWP) =='
cmake -S (Join-Path $root 'platforms\uwp-python') -B build\python `
    -G 'Visual Studio 17 2022' -A x64 `
    "-DWWHD_PYTHON_SOURCE=$cpython" "-DWWHD_ZLIB_SOURCE=$zlib"
if ($LASTEXITCODE -ne 0) { throw 'python configure failed' }
cmake --build build\python --config Release --target wwhd-python wwhd-python-host
if ($LASTEXITCODE -ne 0) { throw 'python build failed' }

Write-Host '== Packing the standard library (python311.zip) =='
$excluded = @('__pycache__', 'test', 'tests', 'idlelib', 'tkinter', 'turtledemo',
    'site-packages', 'config-3.11', 'config-3.11-darwin', 'dist-packages')
$lib = Join-Path $cpython 'Lib'
python - "$lib" "$excluded" (Join-Path $root 'artifacts\python-uwp\python311.zip') @'
import sys, zipfile, os
lib, excluded, out = sys.argv[1], set(sys.argv[2].split(','), ), sys.argv[3]
os.makedirs(os.path.dirname(out), exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for folder, _, files in os.walk(lib):
        rel = os.path.relpath(folder, lib).replace('\\', '/')
        top = rel.split('/')[0]
        if top in excluded or '__pycache__' in rel.split('/'):
            continue
        for f in files:
            if f.endswith(('.pyc', '.exe', '.dll')):
                continue
            z.write(os.path.join(folder, f), os.path.relpath(os.path.join(folder, f), lib))
print('python311.zip written')
'@

New-Item -ItemType Directory -Force -Path "$root\artifacts\python-uwp" | Out-Null
Copy-Item build\python\Release\wwhd-python.dll "$root\artifacts\python-uwp\"
Copy-Item build\python\Release\python311.lib "$root\artifacts\python-uwp\"
Copy-Item build\python\Release\wwhd-python-host.lib "$root\artifacts\python-uwp\"
Get-ChildItem $root\artifacts\python-uwp -Recurse | Select-Object FullName, Length
Write-Host 'PASS python-uwp'
