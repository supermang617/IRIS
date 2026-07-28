param(
    [switch]$RequireReady
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot

$script = Join-Path $repoRoot "scripts\package_windows_msix.ps1"
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    throw "Missing MSIX packaging script: $script"
}
$packagingSource = Get-Content -LiteralPath $script -Raw
foreach ($requiredManifestFragment in @(
        'xmlns:desktop6="http://schemas.microsoft.com/appx/manifest/desktop/windows10/6"',
        'IgnorableNamespaces="uap desktop desktop6 rescap"',
        '<desktop6:FileSystemWriteVirtualization>disabled</desktop6:FileSystemWriteVirtualization>',
        '<rescap:Capability Name="unvirtualizedResources" />',
        '/tr $TimestampUrl /td SHA256'
    )) {
    if (-not $packagingSource.Contains($requiredManifestFragment)) {
        throw "MSIX packaging source is missing durable AppData state protection: $requiredManifestFragment"
    }
}

$readinessRejected = $false
try {
    & $script -ReadinessOnly
} catch {
    $readinessRejected = $true
}

$report = Join-Path $repoRoot "release\dist\iris-msix-readiness.txt"
if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
    throw "MSIX readiness report was not written: $report"
}
$content = Get-Content -LiteralPath $report -Raw
foreach ($required in @(
        "Iris MSIX/App Installer readiness",
        "MSIX/App Installer",
        "makeappx.exe",
        "signtool.exe",
        "signing input",
        "Overall production readiness:"
    )) {
    if (-not $content.Contains($required)) {
        throw "MSIX readiness report missing: $required"
    }
}

$hasFailure = $content.Contains("[FAIL]")
$reportsReady = $content.Contains("Overall production readiness: READY")
$reportsNotReady = $content.Contains("Overall production readiness: NOT READY")
if ($reportsNotReady -and -not $readinessRejected) {
    throw "Readiness script returned success despite reporting NOT READY."
}
if ($reportsReady -and $readinessRejected) {
    throw "Readiness script rejected a report that says READY."
}
if ($hasFailure -and -not $reportsNotReady) {
    throw "Readiness report has failures but does not say NOT READY."
}
if (-not $hasFailure -and -not $reportsReady) {
    throw "Readiness report has no failures but does not say READY."
}
if ($RequireReady -and -not $reportsReady) {
    throw "A production-ready signed installer was required, but the MSIX readiness report is NOT READY."
}

if ($reportsReady) {
    Write-Host "Windows signed-installer readiness is READY."
} else {
    Write-Host "Windows signed-installer readiness accurately reported NOT READY."
}
