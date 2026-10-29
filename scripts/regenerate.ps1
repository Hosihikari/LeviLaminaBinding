param(
    [Parameter(Mandatory = $true)]
    [string]$IrDirectory,
    [string]$LeviLaminaRoot = "",
    [string]$GeneratorRoot = "",
    [string]$Output = "artifacts/regenerated",
    [string]$AbiRoot = ""
)
if ([string]::IsNullOrWhiteSpace($LeviLaminaRoot)) {
    $LeviLaminaRoot = Join-Path $PSScriptRoot "..\..\Third\LeviLamina"
}

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$IrDirectory = (Resolve-Path $IrDirectory).Path
if ([string]::IsNullOrWhiteSpace($GeneratorRoot)) {
    $GeneratorRoot = (Resolve-Path (Join-Path $RepoRoot "..\Binding.Generator")).Path
} else {
    $GeneratorRoot = (Resolve-Path $GeneratorRoot).Path
}
$LeviLaminaRoot = (Resolve-Path $LeviLaminaRoot).Path
$Output = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $RepoRoot $Output }

$Manifest = Join-Path $IrDirectory "ir-manifest.json"
if (-not (Test-Path $Manifest)) {
    throw "ir-manifest.json was not found under $IrDirectory."
}

$AbiRoot = if ([string]::IsNullOrWhiteSpace($AbiRoot)) {
    Join-Path (Split-Path $RepoRoot -Parent) "Binding.Abi"
} else {
    (Resolve-Path $AbiRoot).Path
}
$AbiHeader = Join-Path $AbiRoot "native\hosihikari_abi.h"
if (-not (Test-Path $AbiHeader)) {
    throw "hosihikari_abi.h was not found under $AbiRoot."
}

$GeneratorProject = Join-Path $GeneratorRoot "src\Hosihikari.Bindings.Generator\Hosihikari.Bindings.Generator.csproj"
dotnet run --project $GeneratorProject -c Release -- emit $Manifest $IrDirectory $Output --native-root $LeviLaminaRoot --link-carrier --ll-allocator --abi-header $AbiHeader

$InteropGenerated = Join-Path $RepoRoot "src\Hosihikari.Bindings.LeviLamina.Interop\Generated"
$ShimTarget = Join-Path $RepoRoot "native\BindingShim\generated\win-x64-server\levilamina"
$CoverageTarget = Join-Path $RepoRoot "coverage"

if (Test-Path $InteropGenerated) {
    Remove-Item $InteropGenerated -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $InteropGenerated | Out-Null
Copy-Item (Join-Path $Output "interop\levilamina\*") $InteropGenerated -Recurse -Force

if (Test-Path $ShimTarget) {
    Remove-Item $ShimTarget -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $ShimTarget | Out-Null
Copy-Item (Join-Path $Output "shim\win-x64-server\levilamina\*") $ShimTarget -Recurse -Force

New-Item -ItemType Directory -Force -Path $CoverageTarget | Out-Null
Copy-Item (Join-Path $Output "coverage\manifest.jsonl") $CoverageTarget -Force
Copy-Item (Join-Path $Output "coverage\summary.json") $CoverageTarget -Force

$Summary = Get-Content (Join-Path $CoverageTarget "summary.json") -Raw | ConvertFrom-Json
$Header = Join-Path $ShimTarget "binding_table.h"
$Functions = (Select-String -Path $Header -Pattern '\(\*hs_' -AllMatches).Count
$CarrierCommit = (& git -C $LeviLaminaRoot rev-parse HEAD).Trim()
$GeneratorVersion = (& dotnet run --project $GeneratorProject -c Release -- version).Trim()

$Provenance = [ordered]@{
    generator = $GeneratorVersion
    irVersion = $Summary.irVersion
    irManifestSha256 = $Summary.irManifestSha256
    carrierCommit = $CarrierCommit
    surface = "levilamina"
    configuration = "win-x64-server"
    mode = "link-carrier"
    tableVersion = 1
    functions = $Functions
    coverageManifestSha256 = $Summary.manifestSha256
}
$ProvenancePath = Join-Path $CoverageTarget "provenance.json"
[System.IO.File]::WriteAllText(
    $ProvenancePath,
    ($Provenance | ConvertTo-Json),
    (New-Object System.Text.UTF8Encoding($false)))

$HashFiles = @()
$HashFiles += Get-ChildItem $InteropGenerated -Recurse -Filter "*.g.cs"
$HashFiles += Get-ChildItem $ShimTarget -File
$HashFiles += Get-Item (Join-Path $CoverageTarget "manifest.jsonl"), (Join-Path $CoverageTarget "summary.json")
$HashLines = foreach ($File in $HashFiles | Sort-Object FullName) {
    $Relative = $File.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
    $Hash = (Get-FileHash $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$Hash  $Relative"
}
[System.IO.File]::WriteAllText(
    (Join-Path $CoverageTarget "generated.sha256"),
    (($HashLines -join "`n") + "`n"),
    (New-Object System.Text.UTF8Encoding($false)))

$Baseline = Get-Content (Join-Path $CoverageTarget "baseline.json") -Raw | ConvertFrom-Json
if ($Summary.declarations.bound -lt $Baseline.declarationsBound -or
    $Summary.members.bound -lt $Baseline.membersBound -or
    $Functions -lt $Baseline.functions) {
    Write-Warning "Generated coverage is below coverage/baseline.json; review the change before updating the baseline."
}

Write-Output "Regenerated: $Functions functions, $($Summary.declarations.bound) bound declarations, $($Summary.members.bound) bound members."
Write-Output "Review the diff, then run scripts/verify_generated.py."
