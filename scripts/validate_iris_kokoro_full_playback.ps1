[CmdletBinding()]
param(
    [string] $Text = "Hello. This is Iris. This is a voice test.",
    [switch] $NoPlay
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location -Path "C:\Projects\IRIS"

Write-Host "=== Iris Kokoro full playback validation ==="
Write-Host "Purpose: verify the beginning of Kokoro speech is not clipped."
Write-Host ("Expected spoken text: " + $Text)

$outWav = ".iris-dev\diagnostics\kokoro-full-playback-validation.wav"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "scripts\speak_iris_kokoro.ps1",
    "-Text", $Text,
    "-OutWav", $outWav,
    "-PlaybackSeconds", "10"
)

if ($NoPlay) {
    $argsList += "-NoPlay"
}

powershell @argsList

if ($LASTEXITCODE -ne 0) {
    throw "Kokoro full playback validation failed."
}

if (-not (Test-Path $outWav)) {
    throw "Kokoro output WAV was not created: $outWav"
}

Write-Host "Result: PASS"
Write-Host "PASS: Kokoro full playback validation completed."
