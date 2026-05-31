[CmdletBinding()]
param(
    [switch] $RunSimulatedMilestone
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location -Path $repoRoot

function Write-Section {
    param([string] $Text)
    Write-Host ""
    Write-Host ("=== " + $Text + " ===")
}

function Assert-Parse {
    param([string] $Path)

    if (-not (Test-Path $Path)) {
        throw "Missing script: $Path"
    }

    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $Path).Path, [ref]$tokens, [ref]$errors) | Out-Null

    if ($errors -and $errors.Count -gt 0) {
        $errors | Format-List | Out-String | Write-Host
        throw "PowerShell parse failed: $Path"
    }

    Write-Host ("PASS parse: " + $Path)
}

Write-Section "Voice script parse checks"

$voiceScripts = @(
    "scripts\listen_iris_local_speak.ps1",
    "scripts\verify_iris_voice_input_boundary.ps1",
    "scripts\test_iris_voice_prompt_to_kokoro.ps1",
    "scripts\speak_iris_kokoro.ps1",
    "scripts\resolve_iris_kokoro_provider.ps1",
    "scripts\play_iris_wav_bounded.ps1"
)

foreach ($script in $voiceScripts) {
    Assert-Parse $script
}

Write-Section "Voice boundary contract scan"

$contractScripts = @(
    "scripts\verify_iris_voice_input_boundary.ps1",
    "scripts\test_iris_voice_prompt_to_kokoro.ps1"
)

$badExactAnchor = Select-String -Path $contractScripts -Pattern "(?<![A-Za-z0-9_])-AnchorWords(?![A-Za-z0-9_])" -ErrorAction SilentlyContinue

if ($badExactAnchor) {
    $badExactAnchor | ForEach-Object {
        Write-Host ($_.Path + ":" + $_.LineNumber + " " + $_.Line)
    }
    throw "Raw -AnchorWords contract still exists. Use -AnchorWordsCsv only."
}

$badNestedArray = Select-String -Path $contractScripts -Pattern "\$args\s*\+=\s*\$AnchorWords|\$boundaryArgs\s*\+=\s*\$AnchorWords|\$powershellArgs\s*\+=\s*\$AnchorWords" -ErrorAction SilentlyContinue

if ($badNestedArray) {
    $badNestedArray | ForEach-Object {
        Write-Host ($_.Path + ":" + $_.LineNumber + " " + $_.Line)
    }
    throw "Nested string-array AnchorWords contract still exists."
}

$csvUses = Select-String -Path $contractScripts -Pattern "AnchorWordsCsv" -ErrorAction SilentlyContinue

if (-not $csvUses) {
    throw "AnchorWordsCsv contract was not found."
}

Write-Host "PASS: voice boundary uses AnchorWordsCsv only."

Write-Section "Kokoro provider check"

$providerJson = powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\resolve_iris_kokoro_provider.ps1" -AsJson

if ($LASTEXITCODE -ne 0) {
    throw "Kokoro provider resolver failed."
}

$provider = $providerJson | ConvertFrom-Json

Write-Host ("Provider OK: " + $provider.ok)
Write-Host ("Model: " + $provider.model_relative_path)
Write-Host ("Voices: " + $provider.voices_relative_path)

if (-not $provider.ok) {
    throw "Kokoro provider is incomplete."
}

if ($RunSimulatedMilestone) {
    Write-Section "Deterministic simulated voice-to-Kokoro no-play milestone"

    $env:IRIS_MODEL_ID = "huihui_ai/qwen3.5-abliterated:9b"
    $env:IRIS_OLLAMA_MODEL = "huihui_ai/qwen3.5-abliterated:9b"
    $env:IRIS_LOCAL_MODEL = "huihui_ai/qwen3.5-abliterated:9b"
    $env:IRIS_MODEL_NUM_CTX = "8192"
    $env:IRIS_MODEL_NUM_PREDICT = "160"

    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\test_iris_voice_prompt_to_kokoro.ps1" -NoPlay -SimulatedTranscript "Testing now, Iris local voice test." -StrictAnchorGate

    if ($LASTEXITCODE -ne 0) {
        throw "Simulated voice-to-Kokoro no-play milestone failed."
    }
}

Write-Section "Result"
Write-Host "PASS: voice contract health guard passed."
