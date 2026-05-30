param(
    [string] $ModelPrefix = "huihui_ai/qwen3.5-abliterated",
    [int] $NumCtx = 8192,
    [int] $NumPredict = 160,
    [switch] $SkipManualSmoke
)

$ErrorActionPreference = "Stop"
Set-Location -Path "C:\Projects\IRIS"

New-Item -ItemType Directory -Force ".iris-dev\diagnostics" | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = ".iris-dev\diagnostics\iris-full-preflight-$timestamp.txt"

function Write-Report {
    param([string] $Text)
    Write-Host $Text
    Add-Content -Encoding UTF8 -Path $report -Value $Text
}

function Write-Section {
    param([string] $Text)
    Write-Report ""
    Write-Report "=== $Text ==="
}

function Invoke-IrisNative {
    param(
        [string] $Name,
        [string] $FilePath,
        [string[]] $Arguments
    )

    Write-Section $Name

    $base = Join-Path $env:TEMP ("iris-full-preflight-" + [guid]::NewGuid().ToString())
    $stdout = "$base.out"
    $stderr = "$base.err"

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr

        if (Test-Path $stdout) {
            Get-Content -Path $stdout | ForEach-Object { Write-Report $_ }
        }

        if (Test-Path $stderr) {
            Get-Content -Path $stderr | ForEach-Object { Write-Report $_ }
        }

        if ($process.ExitCode -ne 0) {
            throw "$Name failed with exit code $($process.ExitCode)"
        }
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $stdout, $stderr
    }
}

Write-Section "Project Iris full preflight"
Write-Report "Timestamp: $timestamp"
Write-Report "Working directory: C:\Projects\IRIS"

Write-Section "Ollama model state"

if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    throw "Ollama command not found."
}

$ollamaList = @(ollama list)
$ollamaList | ForEach-Object { Write-Report $_ }

$modelLine = @(
    $ollamaList |
        Select-Object -Skip 1 |
        Where-Object { $_.Trim() -match "^huihui_ai/qwen3\.5-abliterated(:\S+)?\s+" } |
        Select-Object -First 1
)

if (-not $modelLine) {
    throw "Qwen 3.5 target model is not installed."
}

$TargetModel = (($modelLine[0].Trim()) -split "\s+")[0]

$env:IRIS_MODEL_ID = $TargetModel
$env:IRIS_OLLAMA_MODEL = $TargetModel
$env:IRIS_LOCAL_MODEL = $TargetModel
$env:IRIS_MODEL_NUM_CTX = "$NumCtx"
$env:IRIS_MODEL_NUM_PREDICT = "$NumPredict"

Write-Report "IRIS_MODEL_ID=$env:IRIS_MODEL_ID"
Write-Report "IRIS_MODEL_NUM_CTX=$env:IRIS_MODEL_NUM_CTX"
Write-Report "IRIS_MODEL_NUM_PREDICT=$env:IRIS_MODEL_NUM_PREDICT"

Invoke-IrisNative "Cargo format" "cargo" @("fmt", "--all")
Invoke-IrisNative "Cargo build" "cargo" @("build", "--workspace")
Invoke-IrisNative "Cargo test" "cargo" @("test", "--workspace")
Invoke-IrisNative "Cargo clippy" "cargo" @("clippy", "--workspace")

Invoke-IrisNative "Deterministic foundation guard" "powershell" @(
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

Invoke-IrisNative "Voice/text milestone preflight guard" "powershell" @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\verify_iris_voice_text_milestone.ps1",
    "-ModelPrefix",
    $ModelPrefix,
    "-NumCtx",
    "$NumCtx",
    "-NumPredict",
    "$NumPredict"
)

Invoke-IrisNative "HUD addressee intent" "cargo" @("run", "-p", "iris-runtime", "--", "addressee-intent-test")
Invoke-IrisNative "HUD deictic ownership" "cargo" @("run", "-p", "iris-runtime", "--", "deictic-role-test")
Invoke-IrisNative "HUD praise ownership" "cargo" @("run", "-p", "iris-runtime", "--", "hud-submit-test", "Awesome, you passed our test, Iris. I am proud of you.")
Invoke-IrisNative "HUD voice ownership" "cargo" @("run", "-p", "iris-runtime", "--", "hud-submit-test", "Iris, your voice sounds awesome.")
Invoke-IrisNative "HUD profanity fidelity" "cargo" @("run", "-p", "iris-runtime", "--", "hud-submit-test", "can you say fuckin shit without using asterisks")

if ($SkipManualSmoke) {
    Write-Section "Manual live voice/text smoke"
    Write-Report "SKIP: manual live voice/text smoke skipped by request."
} elseif (Test-Path "scripts\smoke_iris_live_voice_text_manual.ps1") {
    Invoke-IrisNative "Manual live voice/text smoke non-blocking" "powershell" @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "scripts\smoke_iris_live_voice_text_manual.ps1",
        "-NonBlocking"
    )
} else {
    Write-Section "Manual live voice/text smoke"
    Write-Report "SKIP: scripts\smoke_iris_live_voice_text_manual.ps1 not found."
}

Write-Section "Git status"
git status --short | ForEach-Object { Write-Report $_ }

Write-Section "Full preflight result"
Write-Report "PASS: Iris full preflight completed."
Write-Report "Manual live smoke warnings do not invalidate deterministic guards."
Write-Report "Next milestone: open back-and-forth typed and spoken conversation."
Write-Report "Report: $report"
