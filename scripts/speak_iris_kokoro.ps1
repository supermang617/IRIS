[CmdletBinding()]
param(
    [string] $Text = "Iris Kokoro voice provider is working.",
    [string] $OutWav = ".iris-dev\diagnostics\kokoro-direct-validation.wav",
    [string] $Voice = "af_heart,af_bella,af_sky,am_adam",
    [int] $PlaybackSeconds = 6,
    [switch] $NoPlay
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$resolver = Join-Path $PSScriptRoot "resolve_iris_kokoro_provider.ps1"
$helper = Join-Path $PSScriptRoot "invoke_iris_kokoro_tts.py"
$boundedPlayer = Join-Path $PSScriptRoot "play_iris_wav_bounded.ps1"

if (-not (Test-Path $resolver)) {
    throw "Missing Kokoro resolver: $resolver"
}

if (-not (Test-Path $helper)) {
    throw "Missing Kokoro Python helper: $helper"
}

if (-not (Test-Path $boundedPlayer)) {
    throw "Missing bounded WAV player: $boundedPlayer"
}

$provider = (& $resolver -AsJson) | ConvertFrom-Json

if (-not $provider.ok) {
    throw "Kokoro provider is incomplete. Model candidates: $($provider.model_candidate_count). Voice candidates: $($provider.voice_candidate_count)."
}

$pythonExe = Join-Path $RepoRoot ".iris-dev\tts\kokoro\.venv\Scripts\python.exe"
$pythonArgsPrefix = @()

if (-not (Test-Path $pythonExe)) {
    $py = Get-Command "py" -ErrorAction SilentlyContinue

    if ($py) {
        $pythonExe = $py.Source
        $pythonArgsPrefix = @("-3")
    } else {
        $python = Get-Command "python" -ErrorAction SilentlyContinue

        if ($python) {
            $pythonExe = $python.Source
            $pythonArgsPrefix = @()
        } else {
            throw "No Python runtime found for Kokoro."
        }
    }
}

$outFull = if ([System.IO.Path]::IsPathRooted($OutWav)) {
    $OutWav
} else {
    Join-Path $RepoRoot $OutWav
}

New-Item -ItemType Directory -Force (Split-Path -Parent $outFull) | Out-Null

$pythonCommandArgs = @()
$pythonCommandArgs += $pythonArgsPrefix
$pythonCommandArgs += @(
    $helper,
    "--model", $provider.model_path,
    "--voices", $provider.voices_path,
    "--text", $Text,
    "--out", $outFull,
    "--voice", $Voice
)

& $pythonExe @pythonCommandArgs

if ($LASTEXITCODE -ne 0) {
    throw "Kokoro Python helper failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $outFull)) {
    throw "Kokoro did not create WAV output: $outFull"
}

$wav = Get-Item $outFull

if ($wav.Length -lt 1000) {
    throw "Kokoro WAV output is too small: $($wav.Length) bytes"
}

Write-Host "Model: $($provider.model_relative_path)"
Write-Host "Voices: $($provider.voices_relative_path)"
Write-Host "WAV: $outFull"

if ($NoPlay) {
    Write-Host "Playback: skipped"
} else {
    powershell -NoProfile -ExecutionPolicy Bypass -File $boundedPlayer -WavPath $outFull -Seconds $PlaybackSeconds

    if ($LASTEXITCODE -ne 0) {
        throw "Bounded WAV playback failed with exit code $LASTEXITCODE"
    }
}

Write-Host "Result: PASS"
