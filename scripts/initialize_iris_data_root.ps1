param(
    [string]$InstallRoot = "",
    [switch]$PersistForCurrentUser,
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

function Resolve-IrisDataRoot {
    param([string]$CandidateInstallRoot)

    if ($env:IRIS_DATA_ROOT) {
        return [System.IO.Path]::GetFullPath($env:IRIS_DATA_ROOT)
    }
    if ($CandidateInstallRoot) {
        $candidateRoot = [System.IO.Path]::GetFullPath($CandidateInstallRoot).TrimEnd("\")
        if (Test-Path -LiteralPath (Join-Path $candidateRoot ".git")) {
            return $candidateRoot
        }
    }
    if ($env:LOCALAPPDATA) {
        return [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Iris"))
    }
    if ($env:USERPROFILE) {
        return [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE ".iris"))
    }
    throw "IRIS_DATA_ROOT could not be resolved because LOCALAPPDATA and USERPROFILE are unavailable."
}

function Copy-MissingTreeContent {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return 0
    }

    $sourceResolved = [System.IO.Path]::GetFullPath($Source).TrimEnd("\")
    $destinationResolved = [System.IO.Path]::GetFullPath($Destination).TrimEnd("\")
    if ($sourceResolved -ieq $destinationResolved) {
        return 0
    }

    New-Item -ItemType Directory -Force -Path $destinationResolved | Out-Null
    $copied = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $sourceResolved -Recurse -Force -File -ErrorAction SilentlyContinue)) {
        $relative = $file.FullName.Substring($sourceResolved.Length).TrimStart("\")
        $target = Join-Path $destinationResolved $relative
        if (Test-Path -LiteralPath $target) {
            continue
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
        $copied++
    }
    return $copied
}

$dataRoot = Resolve-IrisDataRoot -CandidateInstallRoot $InstallRoot
New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
$env:IRIS_DATA_ROOT = $dataRoot

if ($PersistForCurrentUser) {
    [Environment]::SetEnvironmentVariable("IRIS_DATA_ROOT", $dataRoot, "User")
}

$diagnosticsRoot = Join-Path $dataRoot "diagnostics"
$ownedDataRoot = Join-Path $dataRoot ".iris-data"
New-Item -ItemType Directory -Force -Path $diagnosticsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $ownedDataRoot | Out-Null
$migrationLog = Join-Path $diagnosticsRoot "data-migration.log"

if ($InstallRoot) {
    $installRootResolved = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd("\")
    $legacyData = Join-Path $installRootResolved ".iris-data"
    $legacyDiagnostics = Join-Path $installRootResolved "diagnostics"
    $dataCopied = Copy-MissingTreeContent -Source $legacyData -Destination $ownedDataRoot
    $diagnosticsCopied = Copy-MissingTreeContent -Source $legacyDiagnostics -Destination $diagnosticsRoot
    if ($dataCopied -gt 0 -or $diagnosticsCopied -gt 0) {
        "[$(Get-Date -Format o)] Preserved $dataCopied legacy data file(s) and $diagnosticsCopied diagnostic file(s) from $installRootResolved. Original files were retained." |
            Out-File -LiteralPath $migrationLog -Encoding utf8 -Append
    }
}

if ($PassThru) {
    Write-Output $dataRoot
}
