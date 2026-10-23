# Builds the WWHD-UWP Arabic Edition package: runtime (dynamic game code + unified on-console
# preparation), staged Arabic mod, Tools/ and CompilerHeaders/ for on-console preparation, and the
# .appx (unsigned plus a self-signed copy for direct Device Portal installs).
#
# Expects in artifacts/ (built by the other .github/scripts steps):
#   clang-uwp\{bin\wwhd-clang-bridge.dll,lib\wwhd-clang-bridge.lib}
#   python-uwp\{wwhd-python.dll,python311.lib,wwhd-python-host.lib,python311.zip}
#   sdl-uwp\{SDL3.dll,SDL3.lib,include\}
#   sdl-src\                      (patched SDL3_UWP checkout)
#   mesa-driver\*.dll
#   vulkan-headers\include\
#   upstream-tools\               (ZeldaWWHDRecomp tools/ at the pinned upstream commit)
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
$art = Join-Path $root 'artifacts'
$profileText = 'arabic-unified-1'

Write-Host '== Host tools for FetchContent (glslang, zlib source dirs) =='
New-Item -ItemType Directory -Force -Path "$root\.local\host-tools\_deps" | Out-Null
foreach ($dep in @(
    @{ dir = 'glslang-src'; file = "glslang-$($env:GLSLANG_TAG).tar.gz"; extracted = "glslang-$($env:GLSLANG_TAG)"; url = "https://github.com/KhronosGroup/glslang/archive/refs/tags/$($env:GLSLANG_TAG).tar.gz" },
    @{ dir = 'zlib-src'; file = "zlib-$($env:ZLIB_TAG).tar.gz"; extracted = "zlib-$($env:ZLIB_TAG)"; url = "https://github.com/madler/zlib/archive/refs/tags/v$($env:ZLIB_TAG).tar.gz" }
)) {
    $target = "$root\.local\host-tools\_deps\$($dep.dir)"
    if (-not (Test-Path $target)) {
        Invoke-WebRequest $dep.url -OutFile $dep.file
        tar -xzf $dep.file
        if (-not (Test-Path $dep.extracted)) { throw "expected $($dep.extracted) after extracting $($dep.file)" }
        Move-Item $dep.extracted $target
    }
}

Write-Host '== Building the runtime (dynamic game code, unified preparation) =='
Invoke-Logged 'runtime-configure' {
    cmake -S (Join-Path $root 'platforms\uwp-game') -B build\game `
        -G 'Visual Studio 17 2022' -A x64 `
        -DCMAKE_SYSTEM_NAME=WindowsStore -DCMAKE_SYSTEM_VERSION=10.0 `
        "-DWWHD_SDL_SOURCE=$(Join-Path $art 'sdl-src')" `
        "-DWWHD_SDL_BUILD=$(Join-Path $art 'sdl-uwp')" `
        "-DWWHD_VULKAN_HEADERS=$(Join-Path $art 'vulkan-headers\include')" `
        "-DWWHD_PYTHON_BUILD=$(Join-Path $art 'python-uwp')" `
        "-DWWHD_CLANG_BUILD=$(Join-Path $art 'clang-uwp')" `
        -DWWHD_DYNAMIC_GAMECODE=ON -DWWHD_UNIFIED_PREPARATION=ON
}
Invoke-Logged 'runtime-build' { cmake --build build\game --config Release --target wwhd-uwp-game }

Write-Host '== Staging the package =='
$pkg = Join-Path $root 'package'
New-Item -ItemType Directory -Force -Path $pkg | Out-Null
Copy-Item build\game\Release\wwhd-uwp-game.exe $pkg\
Copy-Item "$art\sdl-uwp\SDL3.dll" $pkg\
Copy-Item "$art\python-uwp\wwhd-python.dll" $pkg\
Copy-Item "$art\python-uwp\python311.zip" $pkg\
Copy-Item "$art\mesa-driver\*" $pkg\
[System.IO.File]::WriteAllText((Join-Path $pkg 'preparation-profile.txt'), $profileText)
Copy-Item (Join-Path $root 'platforms\uwp-game\Assets') "$pkg\Assets" -Recurse

# Tools/: the pinned upstream ZeldaWWHDRecomp tooling (translator and its hooks), unpacked.
Copy-Item "$art\upstream-tools" "$pkg\Tools" -Recurse

# CompilerHeaders/: the exact inputs of the on-console compiler (compile_host.cpp names[]).
$headers = Join-Path $pkg 'CompilerHeaders'
New-Item -ItemType Directory -Force -Path $headers | Out-Null
foreach ($h in 'ppc.h', 'guest_addr.h', 'recomp_table.h', 'wwhd_guest_abi.h', 'wwhd_mod.h', 'verify_tap.h', 'verify_tap_gen.h') {
    Copy-Item "$root\runtime\include\$h" $headers
}
foreach ($h in 'stdint.h', 'string.h', 'math.h', 'stdio.h', 'stdlib.h') {
    Copy-Item "$root\platforms\uwp-clang\include\$h" $headers
}

# BundledMods/: the staged Arabic Hesham translation (staged by fetch_patch.py + stage_mod.py;
# the game build's post-build step copies it next to the exe, which is where the runtime looks).
$modSource = Get-ChildItem (Join-Path $root 'build\game') -Recurse -Directory -Filter content.arabic_hesham -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') } | Select-Object -First 1
if (-not $modSource) { $modSource = Join-Path $root '.local\arabic\content.arabic_hesham' } else { $modSource = $modSource.FullName }
if (-not (Test-Path "$modSource\manifest.json")) { throw 'Arabic mod is not staged (run arabic/fetch_patch.py + arabic/stage_mod.py first)' }
New-Item -ItemType Directory -Force -Path "$pkg\BundledMods" | Out-Null
Copy-Item $modSource "$pkg\BundledMods\content.arabic_hesham" -Recurse

Write-Host 'Package contents:'
Get-ChildItem $pkg | Select-Object Name, Length

Write-Host '== Packing the APPX (MakeAppx) =='
$mapping = Join-Path $root 'mapping.txt'
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('[Files]')
Get-ChildItem $pkg -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($pkg.Length + 1)
    $lines.Add('"' + $_.FullName + '" "' + $relative + '"')
}
[System.IO.File]::WriteAllLines($mapping, $lines)
$sdk = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Directory |
    Where-Object Name -match '^10\.' | Sort-Object Name -Descending | Select-Object -First 1
$makeappx = Join-Path $sdk.FullName 'x64\makeappx.exe'
$signtool = Join-Path $sdk.FullName 'x64\signtool.exe'
Invoke-Logged 'makeappx' { & $makeappx pack /f $mapping /p "$root\wwhd-uwp-arabic-unsigned.appx" /o }

Write-Host '== Signing (self-signed, CN=WWHDRecompDevelopment to match the manifest publisher) =='
$cert = New-SelfSignedCertificate -Type Custom -Subject 'CN=WWHDRecompDevelopment' `
    -KeyUsage DigitalSignature -FriendlyName 'WWHD UWP Arabic Edition' `
    -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 `
    -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(5)
$password = ConvertTo-SecureString -String 'wwhd-uwp-arabic' -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "$root\wwhd-uwp-arabic.pfx" -Password $password | Out-Null
Export-Certificate -Cert $cert -FilePath "$root\wwhd-uwp-arabic.cer" | Out-Null
Copy-Item "$root\wwhd-uwp-arabic-unsigned.appx" "$root\wwhd-uwp-arabic.appx"
& $signtool sign /fd SHA256 /f "$root\wwhd-uwp-arabic.pfx" /p 'wwhd-uwp-arabic' "$root\wwhd-uwp-arabic.appx"
if ($LASTEXITCODE -ne 0) { throw 'signtool failed' }

Write-Host '== Verifying the package =='
& $signtool verify /pa "$root\wwhd-uwp-arabic.appx"
if ($LASTEXITCODE -ne 0) { Write-Warning 'signature self-verify failed (expected against an untrusted self-signed cert on a clean machine); package kept' }
Get-ChildItem $root -Filter 'wwhd-uwp-arabic.*' | Select-Object Name, Length
Write-Host 'PASS package'
