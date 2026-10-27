param(
    [Parameter(Mandatory = $true)]
    [string]$ServerRoot,
    [string]$GeneratorRoot = "",
    [string]$LlvmRoot = "$env:LOCALAPPDATA\Temp\hosihikari-llvm\clang+llvm-23.1.3-x86_64-pc-windows-msvc",
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ServerRoot = (Resolve-Path $ServerRoot).Path
if ([string]::IsNullOrWhiteSpace($GeneratorRoot)) {
    $GeneratorRoot = (Resolve-Path (Join-Path $RepoRoot "..\Binding.Generator")).Path
} else {
    $GeneratorRoot = (Resolve-Path $GeneratorRoot).Path
}

$ServerExecutable = Join-Path $ServerRoot "bedrock_server_mod.exe"
if (-not (Test-Path $ServerExecutable)) {
    throw "bedrock_server_mod.exe was not found under $ServerRoot."
}

dotnet build (Join-Path $RepoRoot "Hosihikari.Bindings.LeviLamina.slnx") -c Release --nologo -v:q
& (Join-Path $RepoRoot "native\BindingShim\build.ps1") -LlvmRoot $LlvmRoot -GeneratorRoot $GeneratorRoot

$InteropDll = Join-Path $RepoRoot "src\Hosihikari.Bindings.LeviLamina.Interop\bin\Release\net10.0\Hosihikari.Bindings.LeviLamina.Interop.dll"
$AbiDll = Join-Path (Split-Path $InteropDll -Parent) "Hosihikari.Bindings.Abi.dll"
$ShimDll = Join-Path $RepoRoot "artifacts\native\Hosihikari.Bindings.LeviLamina.Shim.dll"
$PluginSource = Join-Path $RepoRoot "tests\runtime-smoke"
$PluginTarget = Join-Path $ServerRoot "plugins\shim-smoke"
$DataTarget = Join-Path $ServerRoot "data\hosihikari\shim-smoke"

foreach ($file in @($InteropDll, $AbiDll, $ShimDll, (Join-Path $PluginSource "main.cs"), (Join-Path $PluginSource "manifest.json"))) {
    if (-not (Test-Path $file)) {
        throw "Runtime smoke input is missing: $file"
    }
}

if (Test-Path $PluginTarget) {
    Remove-Item $PluginTarget -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $PluginTarget | Out-Null
Copy-Item (Join-Path $PluginSource "main.cs") $PluginTarget -Force
Copy-Item (Join-Path $PluginSource "manifest.json") $PluginTarget -Force
Copy-Item $InteropDll $PluginTarget -Force
Copy-Item $AbiDll $PluginTarget -Force
Copy-Item $ShimDll $PluginTarget -Force

if (Test-Path $DataTarget) {
    Remove-Item $DataTarget -Recurse -Force
}

Set-Content -Path (Join-Path $ServerRoot "eula.txt") -Value "eula=true"
$LogDirectory = Join-Path $RepoRoot "artifacts"
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$StandardOutput = Join-Path $LogDirectory "runtime-smoke.out.log"
$StandardError = Join-Path $LogDirectory "runtime-smoke.err.log"
Remove-Item $StandardOutput, $StandardError -Force -ErrorAction SilentlyContinue

$Process = Start-Process `
    -FilePath $ServerExecutable `
    -WorkingDirectory $ServerRoot `
    -RedirectStandardOutput $StandardOutput `
    -RedirectStandardError $StandardError `
    -PassThru `
    -NoNewWindow

$ResultPath = Join-Path $DataTarget "shim-smoke.txt"
$Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while ([DateTime]::UtcNow -lt $Deadline) {
    if (Test-Path $ResultPath) {
        break
    }

    if ($Process.HasExited) {
        break
    }

    Start-Sleep -Seconds 1
}

if (-not $Process.HasExited) {
    Stop-Process -Id $Process.Id -Force
    Start-Sleep -Seconds 2
}

if (-not (Test-Path $ResultPath)) {
    Get-Content $StandardOutput -Tail 80 -ErrorAction SilentlyContinue
    Get-Content $StandardError -Tail 40 -ErrorAction SilentlyContinue
    throw "Runtime smoke did not produce $ResultPath within $TimeoutSeconds seconds."
}

$Result = Get-Content $ResultPath -Raw
Write-Output $Result
if ($Result -notmatch "(?m)^result=OK\s*$") {
    Get-Content $StandardOutput -Tail 80 -ErrorAction SilentlyContinue
    throw "Runtime smoke failed; see $ResultPath."
}

Write-Output "Runtime smoke passed."
