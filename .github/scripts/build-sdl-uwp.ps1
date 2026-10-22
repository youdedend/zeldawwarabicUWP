# Builds the SDL3 UWP fork with this repo's input patches.
#
# Layout produced in artifacts/sdl-uwp/ (what WWHD_SDL_BUILD and WWHD_SDL_SOURCE expect):
#   SDL3.lib, SDL3.dll, include/   (the include/ tree of the patched SDL source)
$ErrorActionPreference = 'Stop'

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
    git apply --whitespace=nowarn (Join-Path $root "platforms\uwp-game\patches\$patch")
    if ($LASTEXITCODE -ne 0) { git apply --3way (Join-Path $root "platforms\uwp-game\patches\$patch") }
    if ($LASTEXITCODE -ne 0) { throw "$patch did not apply" }
}
Pop-Location

Write-Host '== Building SDL3 (UWP shared) =='
cmake -S sdl-src -B build\sdl `
    -G 'Visual Studio 17 2022' -A x64 `
    -DCMAKE_SYSTEM_NAME=WindowsStore -DCMAKE_SYSTEM_VERSION=10.0 `
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
if ($LASTEXITCODE -ne 0) { throw 'SDL configure failed' }
cmake --build build\sdl --config Release --target SDL3-shared
if ($LASTEXITCODE -ne 0) { throw 'SDL build failed' }

$dll = Get-ChildItem build\sdl -Recurse -Filter SDL3.dll | Select-Object -First 1
$lib = Get-ChildItem build\sdl -Recurse -Filter SDL3.lib | Select-Object -First 1
if (-not $dll -or -not $lib) { throw 'SDL3.dll/SDL3.lib not found after build' }

New-Item -ItemType Directory -Force -Path "$root\artifacts\sdl-uwp" | Out-Null
Copy-Item $dll.FullName "$root\artifacts\sdl-uwp\SDL3.dll"
Copy-Item $lib.FullName "$root\artifacts\sdl-uwp\SDL3.lib"
Copy-Item sdl-src\include "$root\artifacts\sdl-uwp\include" -Recurse
Get-ChildItem $root\artifacts\sdl-uwp | Select-Object Name, Length
Write-Host 'PASS sdl-uwp'
