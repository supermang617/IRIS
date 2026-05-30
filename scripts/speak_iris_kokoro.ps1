param(
    [string] $Text = "Hello, I am Iris. This is my local Kokoro voice.",
    [string] $Voice = "af_heart",
    [double] $Speed = 1.0,
    [string] $OutFile = "tools\kokoro\iris_output.wav",
    [string] $Model = "kokoro-v1.0.onnx",
    [switch] $NoPlay,
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

$kokoroDir = Join-Path (Get-Location) "tools\kokoro"
$ttsScript = Join-Path $kokoroDir "tts.py"
$modelPath = Join-Path $kokoroDir $Model
$voicesPath = Join-Path $kokoroDir "voices-v1.0.bin"
$outputPath = Join-Path (Get-Location) $OutFile

Write-Host ""
Write-Host "=== Project Iris Kokoro speak helper ==="
Write-Host "Voice: $Voice"
Write-Host "Speed: $Speed"
Write-Host "Output: $outputPath"

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run only."
    Write-Host "This script will generate a local WAV with Kokoro ONNX and play it unless -NoPlay is set."
    Write-Host "No model call was made."
    Write-Host "No audio was generated."
    Write-Host "Result: PASS"
    return
}

if (-not (Test-Path $ttsScript)) {
    throw "Missing TTS helper: $ttsScript"
}

if (-not (Test-Path $modelPath)) {
    throw "Missing Kokoro model file: $modelPath. Run scripts\setup_iris_kokoro_tts.ps1 -Install first."
}

if (-not (Test-Path $voicesPath)) {
    throw "Missing Kokoro voices file: $voicesPath. Run scripts\setup_iris_kokoro_tts.ps1 -Install first."
}

$uvCommand = Get-Command uv -ErrorAction SilentlyContinue
if ($null -eq $uvCommand) {
    throw "uv not found. Run scripts\setup_iris_kokoro_tts.ps1 -Install first."
}

Push-Location $kokoroDir
try {
    uv run python "tts.py" --text $Text --voice $Voice --speed $Speed --out $outputPath --model $Model --voices "voices-v1.0.bin"
    if ($LASTEXITCODE -ne 0) { throw "Kokoro TTS generation failed" }
} finally {
    Pop-Location
}

if (-not (Test-Path $outputPath)) {
    throw "Expected Kokoro output file was not created: $outputPath"
}

Write-Host ""
Write-Host "Generated: $outputPath"

if ($NoPlay) {
    Write-Host "Playback skipped because -NoPlay was provided."
    Write-Host "Result: PASS"
    return
}

Write-Host ""
Write-Host "Playing generated Kokoro voice locally."

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$player = New-Object System.Media.SoundPlayer
$player.SoundLocation = $outputPath

try {
    $player.Load()
    $player.PlaySync()
} finally {
    $player.Dispose()
}

Write-Host ""
Write-Host "Result: PASS"
