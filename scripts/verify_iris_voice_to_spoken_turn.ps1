param(
    [int] $TimeoutSeconds = 10,
    [switch] $NoPlay
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

New-Item -ItemType Directory -Force ".iris-dev\voice" | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptPath = ".iris-dev\voice\last-transcript.txt"
$report = ".iris-dev\voice\iris-voice-to-spoken-turn-$timestamp.txt"

Remove-Item -Force -ErrorAction SilentlyContinue $transcriptPath

function Write-ReportLine {
    param([string] $Text)

    Add-Content -Encoding UTF8 -Path $report -Value $Text
}

Write-Host ""
Write-Host "=== Project Iris voice-to-spoken turn milestone ==="
Write-Host "Timeout seconds: $TimeoutSeconds"
Write-Host "NoPlay: $NoPlay"
Write-Host ""
Write-Host "When prompted, say:"
Write-Host "Iris, your voice sounds awesome."
Write-Host ""

Write-ReportLine "Project Iris voice-to-spoken turn milestone"
Write-ReportLine "Timestamp: $timestamp"
Write-ReportLine "Timeout seconds: $TimeoutSeconds"
Write-ReportLine "NoPlay: $NoPlay"

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\verify_iris_voice_input_boundary.ps1" -TimeoutSeconds $TimeoutSeconds
if ($LASTEXITCODE -ne 0) {
    throw "Voice input boundary failed"
}

if (-not (Test-Path $transcriptPath)) {
    throw "Transcript file was not created: $transcriptPath"
}

$transcript = (Get-Content -Raw -Path $transcriptPath).Trim()

if ([string]::IsNullOrWhiteSpace($transcript)) {
    throw "Transcript file was empty"
}

if ($transcript.Length -lt 3) {
    throw "Transcript was too short to use"
}

Write-Host ""
Write-Host "=== Transcript for Iris ==="
Write-Host $transcript

Write-ReportLine ""
Write-ReportLine "Transcript:"
Write-ReportLine $transcript

$speechArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\test_iris_dev_hud_speech_boundary.ps1",
    "-Prompt",
    $transcript
)

if ($NoPlay) {
    $speechArgs += "-NoPlay"
}

Write-Host ""
Write-Host "=== Speaking Iris response ==="

powershell @speechArgs
if ($LASTEXITCODE -ne 0) {
    throw "Dev HUD speech boundary failed"
}

Write-ReportLine ""
Write-ReportLine "PASS: voice-to-spoken turn milestone passed"

Write-Host ""
Write-Host "PASS: Iris voice-to-spoken turn milestone passed"
Write-Host "Report: $report"
