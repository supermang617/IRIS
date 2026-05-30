[CmdletBinding()]
param(
    [switch] $NoPlay
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$resolver = Join-Path $PSScriptRoot "resolve_iris_kokoro_provider.ps1"
$speak = Join-Path $PSScriptRoot "speak_iris_kokoro.ps1"

Write-Host "=== Iris Kokoro direct voice validation ==="

$provider = (& $resolver -AsJson) | ConvertFrom-Json

Write-Host "Model candidates: $($provider.model_candidate_count)"
Write-Host "Voice candidates: $($provider.voice_candidate_count)"
Write-Host "Model: $($provider.model_relative_path)"
Write-Host "Voices: $($provider.voices_relative_path)"

if (-not $provider.ok) {
    throw "Kokoro provider resolution failed. Need both Kokoro ONNX model and voices asset."
}

Write-Host ""
Write-Host "=== Direct Kokoro speech ==="

$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $speak,
    "-Text", "Iris Kokoro voice provider is working.",
    "-OutWav", ".iris-dev\diagnostics\kokoro-direct-validation.wav"
)

if ($NoPlay) {
    $args += "-NoPlay"
}

& powershell @args

if ($LASTEXITCODE -ne 0) {
    throw "Direct Kokoro speech failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "PASS: Kokoro direct voice validation completed."
