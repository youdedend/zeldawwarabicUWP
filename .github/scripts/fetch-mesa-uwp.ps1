# Collects the Mesa Dozen UWP driver (vulkan_dzn.dll and companions) from the mesa-uwp project's
# releases, and the Vulkan headers the runtime compiles against.
#
# Layout produced in artifacts/:
#   mesa-driver/            the driver DLLs (copied into the package root)
#   vulkan-headers/         include/vulkan/... (WWHD_VULKAN_HEADERS)
#
# The game loads the driver with LoadPackagedLibrary(L"vulkan_dzn.dll") (gfx/vulkan/uwp_driver.cpp),
# so every DLL found here ships in the package root. mesa-uwp's releases are built for UWP/Xbox;
# the exact pin is recorded in the log for traceability.
$ErrorActionPreference = 'Stop'

# Surface terminating errors as workflow annotations (visible through the API).
trap {
	Write-Host ("::error::FAILED: " + $_.Exception.Message)
	if ($_.InvocationInfo) { Write-Host ("::error::at: " + $_.InvocationInfo.PositionMessage.Trim()) }
	break
}
$ProgressPreference = 'SilentlyContinue'

$root = $PWD.Path
$release = $env:MESA_UWP_RELEASE
$asset = $env:MESA_UWP_ASSET

Write-Host "== Downloading mesa-uwp $release / $asset =="
Invoke-WebRequest "https://github.com/aerisarn/mesa-uwp/releases/download/$release/$asset" -OutFile mesa-uwp.zip
New-Item -ItemType Directory -Force -Path mesa-uwp | Out-Null
Expand-Archive mesa-uwp.zip -DestinationPath mesa-uwp -Force

Write-Host '== Archive contents (traceability) =='
Get-ChildItem mesa-uwp -Recurse | Select-Object FullName, Length

$dlls = Get-ChildItem mesa-uwp -Recurse -Filter *.dll
if (-not ($dlls | Where-Object Name -eq 'vulkan_dzn.dll')) {
    throw 'vulkan_dzn.dll not found in the mesa-uwp release archive; cannot ship a working driver'
}
New-Item -ItemType Directory -Force -Path "$root\artifacts\mesa-driver" | Out-Null
foreach ($dll in $dlls) { Copy-Item $dll.FullName "$root\artifacts\mesa-driver\" }

Write-Host '== Fetching Vulkan headers =='
$headers = "v$($env:VULKAN_HEADERS_VERSION.TrimStart('v'))"
Invoke-WebRequest "https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/$($env:VULKAN_HEADERS_VERSION).tar.gz" -OutFile vk-headers.tar.gz
tar -xzf vk-headers.tar.gz
New-Item -ItemType Directory -Force -Path "$root\artifacts\vulkan-headers" | Out-Null
Copy-Item "Vulkan-Headers-$($env:VULKAN_HEADERS_VERSION.TrimStart('v'))\include" "$root\artifacts\vulkan-headers\include" -Recurse

Write-Host 'Driver DLLs:'
Get-ChildItem "$root\artifacts\mesa-driver" | Select-Object Name, Length
Write-Host 'PASS mesa-uwp'
