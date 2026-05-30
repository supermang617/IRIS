param(
    [string] $Text = "Hello, I am Iris. This is my Kokoro voice.",
    [string] $Voice = "af_heart",
    [double] $Speed = 1.0,
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

if ($DryRun) {
    Write-Host "Dry run only. No TTS generation or playback performed."
    Write-Host "Result: PASS"
    return
}

if (-not (Test-Path $venvPython) -or -not (Test-Path $modelPath) -or -not (Test-Path $voicesPath)) {
    throw "Kokoro is not set up. Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_kokoro_onnx.ps1"
}

& $venvPython "scripts\iris_kokoro_tts.py" `
    --text $Text `
    --model $modelPath `
    --voices $voicesPath `
    --output $outputPath `
    --voice $Voice `
    --speed $Speed `
    --lang "en-us"

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
$player.PlaySync()

Write-Host ""
Write-Host "Result: PASS"
