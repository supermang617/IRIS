param(
    [int] $TimeoutSeconds = 8,
    [switch] $NoSpeak,
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

if ($DryRun) {
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\listen_iris_local_speak.ps1" -DryRun
    if ($LASTEXITCODE -ne 0) { throw "voice text response dry-run failed" }
    return
}

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\listen_iris_local_speak.ps1" -TimeoutSeconds $TimeoutSeconds -NoSpeak:$NoSpeak
if ($LASTEXITCODE -ne 0) {
    throw "voice text response test failed"
}
