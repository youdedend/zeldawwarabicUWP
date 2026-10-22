# Builds LLVM/Clang 20.1.8 as UWP components plus this repo's wwhd-clang-bridge
# (the embedded frontend the console uses to compile the translated game code on-device).
#
# Layout produced in artifacts/clang-uwp/ (exactly what platforms/uwp-game expects from
# WWHD_CLANG_BUILD):  bin/wwhd-clang-bridge.dll, lib/wwhd-clang-bridge.lib
#
# Cross-build notes: table generators must run on the host, so llvm-tblgen/clang-tblgen are
# built first in a plain host tree and handed to the WindowsStore configuration
# (-DLLVM_TABLEGEN / -DCLANG_TABLEGEN). Only the bridge target is built: it compiles exactly
# the Clang/LLVM libraries the embedded frontend needs (clangCodeGen, clangFrontend, native
# codegen) and no clang.exe.
$ErrorActionPreference = 'Stop'

# Surface terminating errors as workflow annotations (visible through the API).
trap {
	Write-Host ("::error::FAILED: " + $_.Exception.Message)
	if ($_.InvocationInfo) { Write-Host ("::error::at: " + $_.InvocationInfo.PositionMessage.Trim()) }
	break
}
$ProgressPreference = 'SilentlyContinue'

$llvmVersion = $env:LLVM_VERSION
$root = $PWD.Path
$src = Join-Path $root 'llvm-project'
$out = Join-Path $root 'artifacts\clang-uwp'

Write-Host "== Downloading LLVM $llvmVersion component sources =="
New-Item -ItemType Directory -Force -Path $src | Out-Null
foreach ($c in 'llvm', 'clang', 'cmake', 'third-party') {
    $file = "$c-$llvmVersion.src.tar.xz"
    if (-not (Test-Path (Join-Path $src $c))) {
        if (-not (Test-Path $file)) {
            Write-Host "downloading $file"
            Invoke-WebRequest "https://github.com/llvm/llvm-project/releases/download/llvmorg-$llvmVersion/$file" -OutFile $file
        }
        Write-Host "extracting $file"
        tar -xJf $file
        Move-Item "$c-$llvmVersion.src" (Join-Path $src $c)
    }
}

Write-Host '== Applying the UWP patch (platforms/uwp-clang/patches) =='
# Windows checkouts are CRLF (the runner image's global core.autocrlf): normalize the patch to LF
# so it matches the LLVM tarball sources, then apply from the monorepo root.
$patchText = [System.IO.File]::ReadAllText((Join-Path $root 'platforms\uwp-clang\patches\llvm-20.1.8-uwp.patch')) -replace "`r`n", "`n"
$patchFile = Join-Path $env:RUNNER_TEMP 'llvm-uwp.patch'
[System.IO.File]::WriteAllText($patchFile, $patchText)
Push-Location $src
git apply --ignore-whitespace --whitespace=nowarn $patchFile
if ($LASTEXITCODE -ne 0) { throw 'llvm-20.1.8-uwp.patch did not apply cleanly' }
Pop-Location

$commonFlags = @(
    '-DLLVM_TARGETS_TO_BUILD=X86',
    '-DLLVM_INCLUDE_TESTS=OFF', '-DLLVM_INCLUDE_BENCHMARKS=OFF',
    '-DLLVM_INCLUDE_EXAMPLES=OFF', '-DLLVM_INCLUDE_DOCS=OFF',
    '-DLLVM_ENABLE_ZLIB=OFF', '-DLLVM_ENABLE_ZSTD=OFF', '-DLLVM_ENABLE_TERMINFO=OFF',
    '-DLLVM_ENABLE_LIBXML2=OFF', '-DLLVM_ENABLE_HTTPLIB=OFF', '-DLLVM_APPEND_VC_REV=OFF',
    '-DLLVM_ENABLE_ASSERTIONS=OFF'
)

Write-Host '== Host table generators (llvm-tblgen, clang-tblgen) =='
cmake -S (Join-Path $src 'llvm') -B build-host -G Ninja `
    -DCMAKE_BUILD_TYPE=Release `
    -DLLVM_ENABLE_PROJECTS=clang `
    @commonFlags
if ($LASTEXITCODE -ne 0) { throw 'host tablegen configure failed' }
cmake --build build-host --target llvm-tblgen clang-tblgen --config Release
if ($LASTEXITCODE -ne 0) { throw 'host tablegen build failed' }

Write-Host '== WindowsStore build of wwhd-clang-bridge =='
cmake -S (Join-Path $src 'llvm') -B build-uwp -G Ninja `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_SYSTEM_NAME=WindowsStore -DCMAKE_SYSTEM_VERSION=10.0 -DCMAKE_SYSTEM_PROCESSOR=AMD64 `
    -DLLVM_ENABLE_PROJECTS=clang `
    -DLLVM_EXTERNAL_PROJECTS=wwhd-clang `
    "-DLLVM_EXTERNAL_WWHD_CLANG_SOURCE_DIR=$(Join-Path $root 'platforms\uwp-clang')" `
    "-DLLVM_TABLEGEN=$(Join-Path $root 'build-host\bin\llvm-tblgen.exe')" `
    "-DCLANG_TABLEGEN=$(Join-Path $root 'build-host\bin\clang-tblgen.exe')" `
    -DCLANG_ENABLE_ARCMT=OFF -DCLANG_ENABLE_STATIC_ANALYZER=OFF -DCLANG_ENABLE_PROTO_FUZZER=OFF `
    '-DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-pc-windows-msvc' `
    @commonFlags
if ($LASTEXITCODE -ne 0) { throw 'UWP LLVM configure failed' }
cmake --build build-uwp --target wwhd-clang-bridge --config Release
if ($LASTEXITCODE -ne 0) { throw 'wwhd-clang-bridge build failed' }

New-Item -ItemType Directory -Force -Path "$out\bin", "$out\lib" | Out-Null
Copy-Item build-uwp\bin\wwhd-clang-bridge.dll "$out\bin\"
Copy-Item build-uwp\lib\wwhd-clang-bridge.lib "$out\lib\"
Get-ChildItem $out -Recurse | Select-Object FullName, Length
Write-Host 'PASS clang-uwp'
