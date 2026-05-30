param(
    [switch] $UseInt8,
    [switch] $Force,
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
$venvDir = Join-Path $ttsRoot ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"

$modelUrl = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx"
if ($UseInt8) {
    $modelUrl = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.int8.onnx"
}
$voicesUrl = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin"

Write-Host ""
Write-Host "=== Project Iris Kokoro ONNX setup ==="
Write-Host "Root: $ttsRoot"
Write-Host "Model: $modelPath"
Write-Host "Voices: $voicesPath"

if ($DryRun) {
    Write-Host "Dry run only. No install or download performed."
    Write-Host "Result: PASS"
    return
}

New-Item -ItemType Directory -Force $ttsRoot | Out-Null

$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
    throw "Python was not found on PATH. Install Python 3.10+ and rerun this script."
}

if (-not (Test-Path $venvPython) -or $Force) {
    if (Test-Path $venvDir) {
        Remove-Item -Recurse -Force $venvDir
    }

    Write-Host ""
    Write-Host "=== Creating Python virtual environment ==="
    & $python.Source -m venv $venvDir
    if ($LASTEXITCODE -ne 0) { throw "python -m venv failed" }
}

Write-Host ""
Write-Host "=== Installing Kokoro ONNX Python packages ==="
& $venvPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed" }

& $venvPython -m pip install kokoro-onnx soundfile numpy
if ($LASTEXITCODE -ne 0) { throw "pip install Kokoro dependencies failed" }

if (-not (Test-Path $modelPath) -or $Force) {
    Write-Host ""
    Write-Host "=== Downloading Kokoro model ==="
    Invoke-WebRequest -UseBasicParsing -Uri $modelUrl -OutFile $modelPath
}

if (-not (Test-Path $voicesPath) -or $Force) {
    Write-Host ""
    Write-Host "=== Downloading Kokoro voices ==="
    Invoke-WebRequest -UseBasicParsing -Uri $voicesUrl -OutFile $voicesPath
}

if (-not (Test-Path $modelPath)) {
    throw "Kokoro model file missing after setup: $modelPath"
}

if (-not (Test-Path $voicesPath)) {
    throw "Kokoro voices file missing after setup: $voicesPath"
}

Write-Host ""
Write-Host "=== Kokoro setup test generation ==="

$outputPath = Join-Path $ttsRoot "setup_test.wav"

& $venvPython "scripts\iris_kokoro_tts.py" `
    --text "Iris Kokoro voice setup is complete." `
    --model $modelPath `
    --voices $voicesPath `
    --output $outputPath `
    --voice "af_heart" `
    --speed 1.0 `
    --lang "en-us"

if ($LASTEXITCODE -ne 0) { throw "Kokoro setup test generation failed" }

if (-not (Test-Path $outputPath)) {
    throw "Kokoro setup test output missing: $outputPath"
}

Write-Host ""
Write-Host "Result: PASS"
Write-Host "Kokoro ONNX is installed for Iris development TTS."
