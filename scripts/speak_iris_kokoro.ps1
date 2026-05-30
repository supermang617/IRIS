param(
    [string] $Text = "Hello, I am Iris. This is my Kokoro voice.",
    [string] $Voice = "af_heart",
    [double] $Speed = 0.95,
    [int] $WakeSignalMs = 900,
    [double] $WakeSignalAmplitude = 0.004,
    [double] $WakeSignalHz = 220.0,
    [int] $LeadSilenceMs = 300,
    [int] $TailSilenceMs = 300,
    [switch] $NoPlay,
    [switch] $UseInt8,
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

$ttsRoot = Join-Path (Get-Location) ".iris-dev\tts\kokoro"
$modelPath = Join-Path $ttsRoot "kokoro-v1.0.onnx"
if ($UseInt8) {
    $modelPath = Join-Path $ttsRoot "kokoro-v1.0.int8.onnx"
}
$voicesPath = Join-Path $ttsRoot "voices-v1.0.bin"
$venvPython = Join-Path $ttsRoot ".venv\Scripts\python.exe"
$outputPath = Join-Path $ttsRoot "iris_output.wav"

Write-Host ""
Write-Host "=== Project Iris Kokoro speak test ==="
Write-Host "Voice: $Voice"
Write-Host "Speed: $Speed"
Write-Host "Wake signal ms: $WakeSignalMs"
Write-Host "Lead silence ms: $LeadSilenceMs"
Write-Host "Tail silence ms: $TailSilenceMs"

if ($DryRun) {
    Write-Host "Dry run only. No TTS generation or playback performed."
    Write-Host "Result: PASS"
    return
}

if (-not (Test-Path $venvPython) -or -not (Test-Path $modelPath) -or -not (Test-Path $voicesPath)) {
    throw "Kokoro is not set up. Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_kokoro_onnx.ps1"
}

if ($WakeSignalMs -lt 0) { throw "WakeSignalMs must not be negative." }
if ($WakeSignalAmplitude -lt 0) { throw "WakeSignalAmplitude must not be negative." }
if ($LeadSilenceMs -lt 0) { throw "LeadSilenceMs must not be negative." }
if ($TailSilenceMs -lt 0) { throw "TailSilenceMs must not be negative." }

& $venvPython "scripts\iris_kokoro_tts.py" `
    --text $Text `
    --model $modelPath `
    --voices $voicesPath `
    --output $outputPath `
    --voice $Voice `
    --speed $Speed `
    --lang "en-us" `
    --wake-signal-ms $WakeSignalMs `
    --wake-signal-amplitude $WakeSignalAmplitude `
    --wake-signal-hz $WakeSignalHz `
    --lead-silence-ms $LeadSilenceMs `
    --tail-silence-ms $TailSilenceMs

if ($LASTEXITCODE -ne 0) { throw "Kokoro TTS generation failed" }

if (-not (Test-Path $outputPath)) {
    throw "Kokoro output file missing: $outputPath"
}

Write-Host ""
Write-Host "Audio generated: $outputPath"

if ($NoPlay) {
    Write-Host "Playback skipped because -NoPlay was provided."
    Write-Host "Result: PASS"
    return
}

Write-Host ""
Write-Host "=== Playing Kokoro audio ==="

Add-Type -AssemblyName System
$player = New-Object System.Media.SoundPlayer $outputPath
$player.Load()
Start-Sleep -Milliseconds 250
$player.PlaySync()

Write-Host ""
Write-Host "Result: PASS"
