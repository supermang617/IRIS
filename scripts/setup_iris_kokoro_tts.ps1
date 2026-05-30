param(
    [switch] $Install,
    [switch] $UseInt8,
    [string] $Voice = "af_heart",
    [string] $TestText = "Hello, I am Iris. This is my local Kokoro voice test.",
    [switch] $NoPlay,
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

$kokoroDir = Join-Path (Get-Location) "tools\kokoro"
$ttsScript = Join-Path $kokoroDir "tts.py"
$modelName = if ($UseInt8) { "kokoro-v1.0.int8.onnx" } else { "kokoro-v1.0.onnx" }
$modelPath = Join-Path $kokoroDir $modelName
$voicesPath = Join-Path $kokoroDir "voices-v1.0.bin"

$modelUrl = if ($UseInt8) {
    "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.int8.onnx"
} else {
    "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx"
}

$voicesUrl = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin"

Write-Host ""
Write-Host "=== Project Iris Kokoro ONNX setup ==="
Write-Host "Directory: $kokoroDir"
Write-Host "Model: $modelName"
Write-Host "Voice: $Voice"

if ($DryRun -or -not $Install) {
    Write-Host ""
    Write-Host "Dry run / planning mode."
    Write-Host "No packages installed."
    Write-Host "No files downloaded."
    Write-Host ""
    Write-Host "To install and test Kokoro later, run:"
    Write-Host 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_kokoro_tts.ps1 -Install'
    Write-Host ""
    Write-Host "For smaller model:"
    Write-Host 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_kokoro_tts.ps1 -Install -UseInt8'
    Write-Host ""
    Write-Host "Result: PASS"
    return
}

New-Item -ItemType Directory -Force $kokoroDir | Out-Null

$pythonCommand = Get-Command py -ErrorAction SilentlyContinue
if ($null -eq $pythonCommand) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
}

if ($null -eq $pythonCommand) {
    throw "Python was not found. Install Python 3.12+ first, then rerun this script."
}

$uvCommand = Get-Command uv -ErrorAction SilentlyContinue
if ($null -eq $uvCommand) {
    Write-Host ""
    Write-Host "uv not found. Installing uv through pip for the current user."

    if ($pythonCommand.Name -eq "py.exe" -or $pythonCommand.Name -eq "py") {
        py -m pip install --user uv
    } else {
        python -m pip install --user uv
    }

    if ($LASTEXITCODE -ne 0) { throw "uv install failed" }

    $uvCommand = Get-Command uv -ErrorAction SilentlyContinue
    if ($null -eq $uvCommand) {
        throw "uv was installed but is not available on PATH. Open a new PowerShell window and rerun this script."
    }
}

Push-Location $kokoroDir
try {
    if (-not (Test-Path "pyproject.toml")) {
        uv init -p 3.12
        if ($LASTEXITCODE -ne 0) { throw "uv init failed" }
    }

    uv add kokoro-onnx soundfile numpy
    if ($LASTEXITCODE -ne 0) { throw "uv add failed" }
} finally {
    Pop-Location
}

if (-not (Test-Path $modelPath)) {
    Write-Host ""
    Write-Host "Downloading Kokoro model file..."
    Invoke-WebRequest -Uri $modelUrl -OutFile $modelPath
}

if (-not (Test-Path $voicesPath)) {
    Write-Host ""
    Write-Host "Downloading Kokoro voices file..."
    Invoke-WebRequest -Uri $voicesUrl -OutFile $voicesPath
}

Write-Host ""
Write-Host "=== Running Kokoro test ==="

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\speak_iris_kokoro.ps1" -Text $TestText -Voice $Voice -NoPlay:$NoPlay -Model $modelName
if ($LASTEXITCODE -ne 0) { throw "Kokoro speak test failed" }

Write-Host ""
Write-Host "Result: PASS"
