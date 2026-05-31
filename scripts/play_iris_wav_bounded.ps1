[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $WavPath,
    [int] $PlaybackSeconds = 10,
    [int] $LeadSilenceMs = 1000,
    [int] $TrailSilenceMs = 250
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location -Path $repoRoot

if (-not (Test-Path $WavPath)) {
    throw "Missing WAV file: $WavPath"
}

$resolvedWav = (Resolve-Path $WavPath).Path
$diagDir = Join-Path $repoRoot ".iris-dev\diagnostics"
New-Item -ItemType Directory -Force $diagDir | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$paddedWav = Join-Path $diagDir ("playback-padded-" + $timestamp + ".wav")

Write-Host "=== Iris bounded WAV playback ==="
Write-Host ("Input WAV: " + $resolvedWav)
Write-Host ("Padded WAV: " + $paddedWav)
Write-Host ("Lead silence ms: " + $LeadSilenceMs)
Write-Host ("Trail silence ms: " + $TrailSilenceMs)
Write-Host ("Playback seconds: " + $PlaybackSeconds)

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    throw "Python is required for WAV padding but was not found on PATH."
}

& python "scripts\pad_iris_wav.py" --inwav $resolvedWav --outwav $paddedWav --lead-ms $LeadSilenceMs --trail-ms $TrailSilenceMs

if ($LASTEXITCODE -ne 0) {
    throw "WAV padding failed."
}

Add-Type -AssemblyName System

$soundPlayer = New-Object System.Media.SoundPlayer
$soundPlayer.SoundLocation = $paddedWav
$soundPlayer.Load()

Write-Host "Playback: start"
$soundPlayer.Play()
Start-Sleep -Seconds $PlaybackSeconds
$soundPlayer.Stop()
Write-Host "Playback: bounded stop"
Write-Host "Result: PASS"
