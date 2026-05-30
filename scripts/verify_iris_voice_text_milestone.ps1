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

function Get-InstalledIrisModel {
    param([string] $Prefix)

    Write-Section "Ollama installed models"

    $list = @(ollama list)

    foreach ($line in $list) {
        Write-Host $line
    }

    foreach ($line in ($list | Select-Object -Skip 1)) {
        $trimmed = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        $name = ($trimmed -split "\s+")[0]

        if ($name.StartsWith($Prefix)) {
            return $name
        }
    }

    throw "No installed Ollama model found with prefix: $Prefix"
}

function Invoke-Step {
    param(
        [string] $Name,
        [string] $Command,
        [string[]] $Arguments
    )

    Write-Section $Name

    & $Command @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

function Assert-NoKnownModelDrift {
    param([string] $ActiveModel)

    Write-Section "Model drift scan"

    $oldPatterns = @(
        "qwen3-vl:4b",
        "qwen3.6",
        "gemma4",
        "local-coder",
        "qwen2.5-coder",
        "huihui_ai/qwen2.5-vl-abliterated"
    )

    $scriptFullPath = (Resolve-Path "scripts\verify_iris_voice_text_milestone.ps1").Path

    $files = Get-ChildItem -Path "." -Recurse -File |
        Where-Object {
            $_.FullName -notmatch "\\\.git\\" -and
            $_.FullName -notmatch "\\target\\" -and
            $_.FullName -notmatch "\\\.iris-dev\\" -and
            $_.FullName -ne $scriptFullPath -and
            $_.Extension -in @(".rs", ".toml", ".md", ".ps1", ".txt")
        }

    $hits = @()

    foreach ($pattern in $oldPatterns) {
        $found = $files | Select-String -Pattern $pattern -SimpleMatch -ErrorAction SilentlyContinue

        if ($found) {
            $hits += $found
        }
    }

    if ($hits.Count -gt 0) {
        Write-Host "Old model references found:"

        foreach ($hit in $hits) {
            Write-Host "$($hit.Path):$($hit.LineNumber): $($hit.Line.Trim())"
        }

        throw "Model drift detected. Current active model should be: $ActiveModel"
    }

    Write-Host "PASS: no known old model references found."
}

function Assert-RuntimeSafetyBoundary {
    Write-Section "Runtime safety boundary scan"

    $runtimePath = "crates\iris-runtime\src\main.rs"

    if (-not (Test-Path $runtimePath)) {
        throw "Missing runtime path: $runtimePath"
    }

    $runtime = Get-Content -Raw -Path $runtimePath

    $forbiddenRuntimeStrings = @(
        "std::net",
        "TcpStream",
        "Command::new",
        "powershell",
        "cmd.exe",
        "python.exe"
    )

    foreach ($needle in $forbiddenRuntimeStrings) {
        if ($runtime.Contains($needle)) {
            throw "Runtime contains forbidden direct capability string: $needle"
        }
    }

    Write-Host "PASS: runtime boundary scan passed."
}

$Model = Get-InstalledIrisModel -Prefix $ModelPrefix

Write-Section "Verification environment"

$env:IRIS_MODEL_ID = $Model
$env:IRIS_OLLAMA_MODEL = $Model
$env:IRIS_LOCAL_MODEL = $Model
$env:IRIS_MODEL_NUM_CTX = "$NumCtx"
$env:IRIS_MODEL_NUM_PREDICT = "$NumPredict"

Write-Host "IRIS_MODEL_ID=$env:IRIS_MODEL_ID"
Write-Host "IRIS_MODEL_NUM_CTX=$env:IRIS_MODEL_NUM_CTX"
Write-Host "IRIS_MODEL_NUM_PREDICT=$env:IRIS_MODEL_NUM_PREDICT"

Assert-NoKnownModelDrift -ActiveModel $Model
Assert-RuntimeSafetyBoundary

Invoke-Step "Cargo format" "cargo" @("fmt", "--all")
Invoke-Step "Cargo build" "cargo" @("build", "--workspace")
Invoke-Step "Cargo test" "cargo" @("test", "--workspace")

Invoke-Step "Addressee intent test" "cargo" @(
    "run",
    "-p",
    "iris-runtime",
    "--",
    "addressee-intent-test"
)

Invoke-Step "Deictic role test" "cargo" @(
    "run",
    "-p",
    "iris-runtime",
    "--",
    "deictic-role-test"
)

Invoke-Step "HUD praise ownership test" "cargo" @(
    "run",
    "-p",
    "iris-runtime",
    "--",
    "hud-submit-test",
    "Awesome, you passed our test, Iris. I am proud of you."
)

Invoke-Step "HUD voice ownership test" "cargo" @(
    "run",
    "-p",
    "iris-runtime",
    "--",
    "hud-submit-test",
    "Iris, your voice sounds awesome."
)

Invoke-Step "HUD profanity fidelity test" "cargo" @(
    "run",
    "-p",
    "iris-runtime",
    "--",
    "hud-submit-test",
    "can you say fuckin shit without using asterisks"
)

Invoke-Step "Xtask audit" "cargo" @("run", "-p", "xtask")

Invoke-Step "Foundation guard" "powershell" @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\verify_iris_foundation_guard.ps1"
)

Write-Section "Milestone result"
Write-Host "PASS: Iris voice/text milestone guard passed."
Write-Host "Active model: $Model"
Write-Host "Next milestone: open back-and-forth typed and spoken conversation."
