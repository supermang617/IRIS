$ErrorActionPreference = "Stop"
Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Manual live voice/text smoke ==="
Write-Host "This is intentionally separate from the deterministic guards."
Write-Host ""

if (-not (Test-Path "scripts\diagnose_iris_current_milestone.ps1")) {
    throw "Missing scripts\diagnose_iris_current_milestone.ps1"
}

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\diagnose_iris_current_milestone.ps1"

if ($LASTEXITCODE -ne 0) {
    throw "Manual live voice/text smoke failed. This does not invalidate the deterministic foundation guard."
}

Write-Host ""
Write-Host "PASS: Manual live voice/text smoke passed."
