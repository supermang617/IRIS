$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot

$script = Join-Path $repoRoot "scripts\package_windows_msix.ps1"
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    throw "Missing MSIX packaging script: $script"
}

& $script -ReadinessOnly
if ($LASTEXITCODE -ne 0) {
    throw "MSIX readiness check failed with exit code $LASTEXITCODE"
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
        "signing input"
    )) {
    if (-not $content.Contains($required)) {
        throw "MSIX readiness report missing: $required"
    }
}

Write-Host "Windows signed-installer readiness test passed."
