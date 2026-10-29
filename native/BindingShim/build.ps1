param(
    [string]$LeviLaminaRoot = "",
    [string]$GeneratorRoot = "",
    [string]$LlvmRoot = "$env:LOCALAPPDATA\Temp\hosihikari-llvm\clang+llvm-23.1.3-x86_64-pc-windows-msvc",
    [string]$FmtLib = "",
    [string]$Output = "artifacts/native"
)
if ([string]::IsNullOrWhiteSpace($LeviLaminaRoot)) {
    $LeviLaminaRoot = Join-Path $PSScriptRoot "..\..\..\Third\LeviLamina"
}

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ([string]::IsNullOrWhiteSpace($GeneratorRoot)) {
    $GeneratorRoot = (Resolve-Path (Join-Path $RepoRoot "..\Binding.Generator")).Path
} else {
    $GeneratorRoot = (Resolve-Path $GeneratorRoot).Path
}
$LeviLaminaRoot = (Resolve-Path $LeviLaminaRoot).Path
$Output = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $RepoRoot $Output }
New-Item -ItemType Directory -Force -Path $Output | Out-Null

$ShimDirectory = Join-Path $PSScriptRoot "generated\win-x64-server\levilamina"
if (-not (Test-Path (Join-Path $ShimDirectory "binding_table.cpp"))) {
    throw "Generated BindingShim sources are missing under $ShimDirectory."
}

$CarrierImportLibrary = Join-Path $LeviLaminaRoot "build\windows\x64\release\LeviLamina.lib"
if (-not (Test-Path $CarrierImportLibrary)) {
    throw "LeviLamina.lib was not found at $CarrierImportLibrary."
}

if ([string]::IsNullOrWhiteSpace($FmtLib)) {
    $Fmt = Get-ChildItem "$env:LOCALAPPDATA\.xmake\packages\f\fmt" -Recurse -Filter fmt.lib -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $Fmt) {
        throw "fmt.lib was not found; pass -FmtLib explicitly."
    }

    $FmtLib = $Fmt.FullName
} else {
    $FmtLib = (Resolve-Path $FmtLib).Path
}

& (Join-Path $GeneratorRoot "frontend\build-carrier-shim.ps1") `
    -ShimDirectory $ShimDirectory `
    -OutputDll (Join-Path $Output "Hosihikari.Bindings.LeviLamina.Shim.dll") `
    -LlvmRoot $LlvmRoot `
    -LeviLaminaRoot $LeviLaminaRoot `
    -CarrierImportLibrary $CarrierImportLibrary `
    -FmtLib $FmtLib
