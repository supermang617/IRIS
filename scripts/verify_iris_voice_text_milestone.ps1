param(
    [string] $ModelPrefix = "huihui_ai/qwen3.5-abliterated",
    [int] $NumCtx = 8192,
    [int] $NumPredict = 160
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

function Write-Section {
    param([string] $Text)

    Write-Host ""
    Write-Host "=== $Text ==="
}

function Invoke-Step {
    param(
        [string] $Name,
        [string] $Command,
        [string[]] $Arguments
    )

    Write-Section $Name

    & $Command @Arguments
    $exit = $LASTEXITCODE

    if ($exit -ne 0) {
        throw "$Name failed with exit code $exit"
    }
}

Write-Section "Voice/text milestone guard"

Invoke-Step "Foundation guard" "powershell" @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\verify_iris_foundation_guard.ps1",
    "-ModelPrefix",
    $ModelPrefix,
    "-NumCtx",
    "$NumCtx",
    "-NumPredict",
    "$NumPredict"
)

Write-Section "Live text and voice session dry-run"

Invoke-Step "Kokoro voice milestone dry-run" "powershell" @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\diagnose_iris_current_milestone.ps1"
)

Write-Section "Milestone result"
Write-Host "PASS: Iris voice/text milestone guard passed."
Write-Host "Next milestone: open back-and-forth typed and spoken conversation."

