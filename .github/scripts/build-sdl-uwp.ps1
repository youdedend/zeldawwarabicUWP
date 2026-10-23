# Builds the SDL3 UWP fork with this repo's input patches.
#
# Layout produced in artifacts/sdl-uwp/ (what WWHD_SDL_BUILD and WWHD_SDL_SOURCE expect):
#   SDL3.lib, SDL3.dll, include/   (the include/ tree of the patched SDL source)
$ErrorActionPreference = 'Stop'

# Runs a native build step, capturing output; on failure the last 50 lines are emitted as
# error annotations (the readable channel when the log download is unavailable).
function Invoke-Logged([string]$name, [scriptblock]$block) {
    $log = Join-Path $env:RUNNER_TEMP ($name -replace '\\s+', '_') 
    & $block 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) {
        Get-Content $log -Tail 50 | ForEach-Object { Write-Host "::error::[$name] $_" }
        throw "$name failed (tail emitted as annotations)"
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

Write-Host '== Cloning SDL3_UWP =='
if (-not (Test-Path 'sdl-src')) {
    git clone --depth 1 https://github.com/rodrigoandrigo/SDL3_UWP sdl-src
    if ($LASTEXITCODE -ne 0) { throw 'SDL3_UWP clone failed' }
}
Push-Location sdl-src
Write-Host "SDL3_UWP commit: $(git rev-parse HEAD)"
Write-Host '== Applying the repo SDL patches =='
foreach ($patch in 'sdl-pixel-format.patch', 'sdl-wgi-input.patch') {
    # Windows checkouts are CRLF (the runner image's global core.autocrlf): normalize to LF first.
    # Skipped when the cached source tree already carries the patch (incremental builds).
    $patchText = [System.IO.File]::ReadAllText((Join-Path $root "platforms\uwp-game\patches\$patch")) -replace "`r`n", "`n"
    $patchFile = Join-Path $env:RUNNER_TEMP $patch
    [System.IO.File]::WriteAllText($patchFile, $patchText)
    git apply --check --ignore-whitespace $patchFile 2>$null
    if ($LASTEXITCODE -eq 0) {
        git apply --ignore-whitespace --whitespace=nowarn $patchFile
        if ($LASTEXITCODE -ne 0) { throw "$patch did not apply" }
    } else {
        git apply --check --reverse --ignore-whitespace $patchFile 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "$patch already applied (cached source tree)" }
        else { git apply --3way $patchFile; if ($LASTEXITCODE -ne 0) { throw "$patch neither applies nor is applied" } }
    }
}
Pop-Location

Write-Host '== Building SDL3 (UWP shared) =='
Invoke-Logged 'sdl-configure' {
    cmake -S sdl-src -B build\sdl `
        -G 'Visual Studio 17 2022' -A x64 `
        -DCMAKE_SYSTEM_NAME=WindowsStore -DCMAKE_SYSTEM_VERSION=10.0 `
        -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
}
Invoke-Logged 'sdl-build' { cmake --build build\sdl --config Release --target SDL3-shared }

$dll = Get-ChildItem build\sdl -Recurse -Filter SDL3.dll | Select-Object -First 1
$lib = Get-ChildItem build\sdl -Recurse -Filter SDL3.lib | Select-Object -First 1
if (-not $dll -or -not $lib) { throw 'SDL3.dll/SDL3.lib not found after build' }

New-Item -ItemType Directory -Force -Path "$root\artifacts\sdl-uwp" | Out-Null
Copy-Item $dll.FullName "$root\artifacts\sdl-uwp\SDL3.dll"
Copy-Item $lib.FullName "$root\artifacts\sdl-uwp\SDL3.lib"
Copy-Item sdl-src\include "$root\artifacts\sdl-uwp\include" -Recurse
Get-ChildItem $root\artifacts\sdl-uwp | Select-Object Name, Length
Write-Host 'PASS sdl-uwp'
