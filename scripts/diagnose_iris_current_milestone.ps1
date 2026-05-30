$ErrorActionPreference = "Continue"

Set-Location -Path "C:\Projects\IRIS"

New-Item -ItemType Directory -Force ".iris-dev\diagnostics" | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = ".iris-dev\diagnostics\iris-diagnostics-$timestamp.txt"
$failures = New-Object System.Collections.Generic.List[string]

function Write-ReportLine {
    param([string] $Text)

    $Text | Tee-Object -FilePath $report -Append
}

function Invoke-DiagnosticStep {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Command
    )

    Write-ReportLine ""
    Write-ReportLine "=== $Name ==="

    $global:LASTEXITCODE = 0

    try {
        & $Command *>&1 | Tee-Object -FilePath $report -Append

        if ($LASTEXITCODE -ne 0) {
            $failures.Add("$Name failed with exit code $LASTEXITCODE")
            Write-ReportLine "FAIL: $Name"
        } else {
            Write-ReportLine "PASS: $Name"
        }
    } catch {
        $failures.Add("$Name threw: $_")
        Write-ReportLine "FAIL: $Name"
        Write-ReportLine "$_"
    }
}

Write-ReportLine "Project Iris diagnostics"
Write-ReportLine "Timestamp: $timestamp"
Write-ReportLine "Working directory: $(Get-Location)"

Invoke-DiagnosticStep "Git status" {
    git status --short --branch
}

Invoke-DiagnosticStep "Cargo format check" {
    cargo fmt --all --check
}

Invoke-DiagnosticStep "Cargo build" {
    cargo build --workspace
}

Invoke-DiagnosticStep "Cargo test" {
    cargo test --workspace
}

Invoke-DiagnosticStep "Xtask audit" {
    cargo run -p xtask
}

Invoke-DiagnosticStep "Runtime self-check" {
    cargo run -p iris-runtime -- self-check
}

Invoke-DiagnosticStep "Runtime UI status" {
    cargo run -p iris-runtime -- ui-status
}

Invoke-DiagnosticStep "Runtime voice status" {
    cargo run -p iris-runtime -- voice-status
}

Invoke-DiagnosticStep "Runtime push-to-talk visible-state test" {
    cargo run -p iris-runtime -- voice-ptt-state-test
}

Invoke-DiagnosticStep "Runtime response post-check test" {
    cargo run -p iris-runtime -- response-check-test
}

Invoke-DiagnosticStep "Kokoro voice milestone verification" {
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\verify_iris_kokoro_voice_milestone.ps1"
}

Invoke-DiagnosticStep "Live text and voice session dry-run" {
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\run_iris_live_text_voice_session.ps1" -DryRun
}

Write-ReportLine ""
Write-ReportLine "=== Diagnostic summary ==="

if ($failures.Count -eq 0) {
    Write-ReportLine "PASS: all diagnostics passed"
    Write-Host ""
    Write-Host "PASS: all diagnostics passed"
    Write-Host "Report: $report"
    exit 0
}

Write-ReportLine "FAIL: $($failures.Count) diagnostic step(s) failed"

foreach ($failure in $failures) {
    Write-ReportLine "- $failure"
}

Write-Host ""
Write-Host "FAIL: $($failures.Count) diagnostic step(s) failed"
Write-Host "Report: $report"
exit 1
