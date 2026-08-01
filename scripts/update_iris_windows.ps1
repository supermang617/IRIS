param(
    [switch]$CheckOnly,
    [switch]$IncludeRuntimeDependencies
)

$ErrorActionPreference = "Stop"
$packageId = "AlejandroPinto.Iris"
# WinGet documents this as APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE.
# The native process exit code is surfaced as a signed Int32 by PowerShell.
$wingetUpdateNotApplicable = -1978335189
# APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND means the catalog entry exists
# but this Windows user has not installed the registered package yet.
$wingetNoApplicationsFound = -1978335212

function Initialize-IrisWingetMigrationData {
    $initializer = Join-Path $PSScriptRoot "initialize_iris_data_root.ps1"
    if (-not (Test-Path -LiteralPath $initializer -PathType Leaf)) {
        $initializer = Join-Path $PSScriptRoot "Initialize Iris Data Root.ps1"
    }
    if (-not (Test-Path -LiteralPath $initializer -PathType Leaf)) {
        throw "Iris cannot preserve legacy data because its data-root initializer is missing beside the update helper."
    }

    $legacyRoots = @()
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "Start Iris.ps1") -PathType Leaf) {
        $legacyRoots += $PSScriptRoot
    }
    if ($env:LOCALAPPDATA) {
        $legacyRoots += Join-Path $env:LOCALAPPDATA "Programs\Iris"
    }
    $seen = @{}
    foreach ($candidate in $legacyRoots) {
        $resolved = [System.IO.Path]::GetFullPath($candidate).TrimEnd("\")
        if ($seen.ContainsKey($resolved) -or -not (Test-Path -LiteralPath $resolved -PathType Container)) {
            continue
        }
        $seen[$resolved] = $true
        & $initializer -InstallRoot $resolved | Out-Null
    }
}

if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw "Windows Package Manager is unavailable. Install or update App Installer from Microsoft, then try again."
}

Write-Host "Checking the WinGet community catalog for $packageId..."
& winget.exe show --id $packageId -e --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) {
    throw @"
Iris is not available from the configured WinGet sources yet.
Repository tooling is ready, but public `winget install/upgrade` starts only after a signed versioned installer manifest is accepted into microsoft/winget-pkgs.
Until then, use the SHA-verified installer from https://github.com/supermang617/IRIS/releases.
"@
}

& winget.exe list --id $packageId -e --accept-source-agreements --disable-interactivity
$installedPackageExitCode = $LASTEXITCODE
if ($CheckOnly) {
    if ($installedPackageExitCode -eq $wingetNoApplicationsFound) {
        Write-Host "Iris is available in WinGet but this portable/legacy installation is not registered. Run Update Iris.ps1 without -CheckOnly for a one-time migration."
        exit 0
    }
    exit $installedPackageExitCode
}

$migratedToWinget = $false
if ($installedPackageExitCode -eq $wingetNoApplicationsFound) {
    Initialize-IrisWingetMigrationData
    Write-Host "Installing the registered Iris package as a one-time migration from the portable/legacy installer..."
    & winget.exe install --id $packageId -e --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "WinGet could not install the registered Iris package (exit code $LASTEXITCODE). The existing Iris installation and per-user data were not removed."
    }
    $migratedToWinget = $true
} elseif ($installedPackageExitCode -ne 0) {
    throw "WinGet could not determine whether Iris is installed (exit code $installedPackageExitCode)."
} else {
    & winget.exe upgrade --id $packageId -e --accept-source-agreements --accept-package-agreements --disable-interactivity
    $irisUpgradeExitCode = $LASTEXITCODE
    if ($irisUpgradeExitCode -eq $wingetUpdateNotApplicable) {
        Write-Host "Iris is already current; no applicable update was found."
    } elseif ($irisUpgradeExitCode -ne 0) {
        throw "WinGet could not upgrade Iris (exit code $irisUpgradeExitCode). Run 'winget upgrade --id $packageId -e' in an ordinary PowerShell window for details."
    }
}

if ($IncludeRuntimeDependencies) {
    foreach ($dependency in @(
        "Google.Chrome",
        "Microsoft.EdgeWebView2Runtime",
        "Ollama.Ollama",
        "Python.Python.3.13",
        "tesseract-ocr.tesseract"
        )) {
        Write-Host "Checking optional runtime package update: $dependency"
        & winget.exe upgrade --id $dependency -e --accept-source-agreements --accept-package-agreements --disable-interactivity
        $dependencyUpgradeExitCode = $LASTEXITCODE
        if ($dependencyUpgradeExitCode -eq $wingetUpdateNotApplicable) {
            Write-Host "$dependency is already current."
        } elseif ($dependencyUpgradeExitCode -ne 0) {
            Write-Warning "$dependency was not upgraded. It may already be current, absent, or unavailable from the configured source."
        }
    }
}

if ($migratedToWinget) {
    Write-Host "The WinGet-managed Iris app is installed and uses the same per-user Iris data root."
    Write-Host "Launch Iris from the Windows Start menu and confirm it works. You may then run the old installation's Uninstall Iris.ps1; it preserves per-user data."
}
Write-Host "Iris update command completed."
