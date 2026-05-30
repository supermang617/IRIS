$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

New-Item -ItemType Directory -Force ".iris-dev\foundation" | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = ".iris-dev\foundation\iris-foundation-$timestamp.txt"
$timings = New-Object System.Collections.Generic.List[string]

function Write-Report {
    param([string] $Text)

    $Text | Tee-Object -FilePath $report -Append
}

function Invoke-FoundationStep {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Command
    )

    Write-Host ""
    Write-Host "=== $Name ==="
    Write-Report ""
    Write-Report "=== $Name ==="

    $start = Get-Date

    & $Command 2>&1 | Tee-Object -FilePath $report -Append

    $exitCode = $LASTEXITCODE
    $elapsed = (Get-Date) - $start
    $seconds = [Math]::Round($elapsed.TotalSeconds, 2)

    $timings.Add("$Name`t$seconds sec")

    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode"
    }

    Write-Report "PASS: $Name in $seconds sec"
}

function Assert-FileDoesNotContain {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Pattern,

        [Parameter(Mandatory = $true)]
        [string] $Failure
    )

    $matches = Select-String -Path $Path -Pattern $Pattern -ErrorAction SilentlyContinue

    if ($matches) {
        Write-Host ""
        Write-Host "Forbidden pattern found in $Path"
        $matches | ForEach-Object { Write-Host "$($_.LineNumber): $($_.Line)" }
        throw $Failure
    }
}

function Assert-NoReadHostCommand {
    $files = Get-ChildItem -Path "scripts" -Filter "*.ps1" -File -Recurse
    $violations = New-Object System.Collections.Generic.List[string]

    foreach ($file in $files) {
        $content = Get-Content -Raw -Path $file.FullName
        $parseErrors = $null
        $tokens = [System.Management.Automation.PSParser]::Tokenize($content, [ref] $parseErrors)

        foreach ($token in $tokens) {
            if ($token.Type -eq "Command" -and $token.Content -eq "Read-Host") {
                $violations.Add("$($file.FullName):$($token.StartLine):$($token.Content)")
            }
        }
    }

    if ($violations.Count -gt 0) {
        Write-Host ""
        Write-Host "Forbidden interactive command found:"
        $violations | ForEach-Object { Write-Host $_ }
        throw "Development scripts must not use interactive Read-Host prompts."
    }
}

function Assert-OutputContains {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Output,

        [Parameter(Mandatory = $true)]
        [string] $Needle,

        [Parameter(Mandatory = $true)]
        [string] $Failure
    )

    if (-not $Output.Contains($Needle)) {
        Write-Host $Output
        throw $Failure
    }
}

function Assert-OutputDoesNotContain {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Output,

        [Parameter(Mandatory = $true)]
        [string] $Needle,

        [Parameter(Mandatory = $true)]
        [string] $Failure
    )

    if ($Output.Contains($Needle)) {
        Write-Host $Output
        throw $Failure
    }
}

Write-Report "Project Iris foundation guard"
Write-Report "Timestamp: $timestamp"
Write-Report "Working directory: $(Get-Location)"

Invoke-FoundationStep "Git status" {
    git status --short --branch
}

Write-Host ""
Write-Host "=== Static foundation checks ==="
Write-Report ""
Write-Report "=== Static foundation checks ==="

Assert-FileDoesNotContain `
    -Path "crates\iris-runtime\src\main.rs" `
    -Pattern "checked_local_response_for_hud_v[0-9]" `
    -Failure "Runtime must use one canonical HUD response function, not suffixed helper chains."

Assert-FileDoesNotContain `
    -Path "crates\iris-runtime\src\main.rs" `
    -Pattern "run_assistant_role_response_repair_test_v[0-9]" `
    -Failure "Runtime tests must use one canonical assistant role repair test, not suffixed test chains."

Assert-NoReadHostCommand

Assert-FileDoesNotContain `
    -Path "scripts\diagnose_iris_current_milestone.ps1" `
    -Pattern "\*>\&1\s*\|\s*Tee-Object" `
    -Failure "Diagnostics must not pipe native command output through *>&1 | Tee-Object."

Write-Report "PASS: static foundation checks"

Invoke-FoundationStep "Cargo format check" {
    cargo fmt --all --check
}

Invoke-FoundationStep "Cargo build" {
    cargo build --workspace
}

Invoke-FoundationStep "Cargo test" {
    cargo test --workspace
}

Invoke-FoundationStep "Xtask audit" {
    cargo run -p xtask
}

Invoke-FoundationStep "Runtime self-check" {
    cargo run -p iris-runtime -- self-check
}

Invoke-FoundationStep "Runtime UI status" {
    cargo run -p iris-runtime -- ui-status
}

Invoke-FoundationStep "Runtime voice status" {
    cargo run -p iris-runtime -- voice-status
}

Invoke-FoundationStep "Runtime push-to-talk visible-state test" {
    cargo run -p iris-runtime -- voice-ptt-state-test
}

Invoke-FoundationStep "Runtime response post-check test" {
    cargo run -p iris-runtime -- response-check-test
}

Invoke-FoundationStep "Assistant output normalization test" {
    cargo run -p iris-runtime -- assistant-text-normalization-test
}

Invoke-FoundationStep "Addressee intent test" {
    cargo run -p iris-runtime -- addressee-intent-test
}

Invoke-FoundationStep "Deictic role test" {
    cargo run -p iris-runtime -- deictic-role-test
}

Invoke-FoundationStep "Assistant role repair test" {
    cargo run -p iris-runtime -- assistant-role-repair-test
}

Write-Host ""
Write-Host "=== HUD targeted behavior checks ==="
Write-Report ""
Write-Report "=== HUD targeted behavior checks ==="

$voiceOutput = cargo run -p iris-runtime -- hud-submit-test "Iris, your voice sounds awesome." 2>&1
$voiceText = $voiceOutput -join "`n"
$voiceText | Tee-Object -FilePath $report -Append
if ($LASTEXITCODE -ne 0) { throw "HUD voice role submit test failed" }
Assert-OutputContains $voiceText "my voice" "Iris must say my voice when referring to her own voice."
Assert-OutputDoesNotContain $voiceText "your voice sounds good" "Iris must not say your voice when referring to her own voice."

$passedOutput = cargo run -p iris-runtime -- hud-submit-test "Okay that was the test. You passed! Congrats!!!" 2>&1
$passedText = $passedOutput -join "`n"
$passedText | Tee-Object -FilePath $report -Append
if ($LASTEXITCODE -ne 0) { throw "HUD passed-role submit test failed" }
Assert-OutputContains $passedText "I passed" "Iris must say I passed when the user says you passed."
Assert-OutputDoesNotContain $passedText "you passed" "Iris must not redirect passed-role praise back onto the user."

$proudOutput = cargo run -p iris-runtime -- hud-submit-test "Awesome, you passed our test, Iris. I am proud of you." 2>&1
$proudText = $proudOutput -join "`n"
$proudText | Tee-Object -FilePath $report -Append
if ($LASTEXITCODE -ne 0) { throw "HUD pride submit test failed" }
Assert-OutputContains $proudText "proud of me" "Iris must understand proud of you means the user is proud of Iris."
Assert-OutputDoesNotContain $proudText "proud of yourself" "Iris must not redirect Iris-directed pride back onto the user."

$profanityOutput = cargo run -p iris-runtime -- hud-submit-test "can you say fuckin shit without using asterisks" 2>&1
$profanityText = $profanityOutput -join "`n"
$profanityText | Tee-Object -FilePath $report -Append
if ($LASTEXITCODE -ne 0) { throw "HUD profanity submit test failed" }
Assert-OutputDoesNotContain $profanityText "f*ck" "Assistant output must not contain f*ck censor marker."
Assert-OutputDoesNotContain $profanityText "f**k" "Assistant output must not contain f**k censor marker."
Assert-OutputDoesNotContain $profanityText "sh*t" "Assistant output must not contain sh*t censor marker."

Invoke-FoundationStep "Current milestone diagnostics" {
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\diagnose_iris_current_milestone.ps1"
}

Write-Report ""
Write-Report "=== Timing summary ==="

foreach ($timing in $timings) {
    Write-Report $timing
}

Write-Report ""
Write-Report "PASS: Iris foundation guard passed"

Write-Host ""
Write-Host "PASS: Iris foundation guard passed"
Write-Host "Report: $report"
