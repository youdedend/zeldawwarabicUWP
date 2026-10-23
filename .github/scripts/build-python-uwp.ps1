# Builds CPython 3.11 as a UWP component (platforms/uwp-python) and packs the standard library
# for the package's python311.zip.
#
# Layout produced in artifacts/python-uwp/ (what WWHD_PYTHON_BUILD and the package expect):
#   wwhd-python.dll, python311.lib (its import library), wwhd-python-host.lib, python311.zip
$ErrorActionPreference = 'Stop'

# Runs a native build step, capturing output; on failure the tail is emitted as a few packed
# error annotations (GitHub shows only ~10 per step, and the log download is unavailable here).
function Invoke-Logged([string]$name, [scriptblock]$block) {
    $log = Join-Path $env:RUNNER_TEMP ("$name.log")
    & $block 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) {
        $lines = @(Get-Content $log -Tail 60 | ForEach-Object { "$_" })
        $per = 8
        for ($start = 0; $start -lt $lines.Count; $start += $per) {
            $chunk = $lines[$start..([Math]::Min($start + $per - 1, $lines.Count - 1))] -join ' \n '
            Write-Host "::error::[$name] $chunk"
        }
        throw "$name failed (tail emitted as packed annotations)"
    }
}
}

# Surface terminating errors as workflow annotations (visible through the API).
trap {
	Write-Host ("::error::FAILED: " + $_.Exception.Message)
	if ($_.InvocationInfo) { Write-Host ("::error::at: " + $_.InvocationInfo.PositionMessage.Trim()) }
	break
}
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
# Ninja + the MSVC environment from msvc-dev-cmd: no quoted arguments, fast incremental builds.
Invoke-Logged 'python-configure' {
    cmake -S (Join-Path $root 'platforms\uwp-python') -B build\python `
        -G Ninja -DCMAKE_BUILD_TYPE=Release `
        "-DWWHD_PYTHON_SOURCE=$cpython" "-DWWHD_ZLIB_SOURCE=$zlib"
}
Invoke-Logged 'python-build' { cmake --build build\python --target wwhd-python wwhd-python-host }

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
