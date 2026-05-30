$ErrorActionPreference = "Continue"

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

Set-Location -Path "C:\Projects\IRIS"

New-Item -ItemType Directory -Force ".iris-dev\diagnostics" | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = ".iris-dev\diagnostics\iris-diagnostics-$timestamp.txt"
$failures = New-Object System.Collections.Generic.List[string]

function Write-ReportLine {
    param([string] $Text)

    $Text | Tee-Object -FilePath $report -Append
}

function Join-NativeArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $quoted = foreach ($argument in $Arguments) {
        if ($null -eq $argument) {
            '""'
        } elseif ($argument -match '[\s"]') {
            '"' + ($argument.Replace('"', '\"')) + '"'
        } else {
            $argument
        }
    }

    $quoted -join " "
}

function Invoke-NativeStep {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $CommandName,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    Write-ReportLine ""
    Write-ReportLine "=== $Name ==="

    $command = Get-Command $CommandName -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        $failures.Add("$Name failed because command was not found: $CommandName")
        Write-ReportLine "FAIL: command not found: $CommandName"
        return
    }

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()

    try {
        $argumentString = Join-NativeArguments -Arguments $Arguments

        $process = Start-Process `
            -FilePath $command.Source `
            -ArgumentList $argumentString `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stdout = Get-Content -Raw -ErrorAction SilentlyContinue -Path $stdoutPath
        $stderr = Get-Content -Raw -ErrorAction SilentlyContinue -Path $stderrPath

        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            Write-ReportLine "--- stdout ---"
            Write-ReportLine $stdout.TrimEnd()
        }

        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            Write-ReportLine "--- stderr ---"
            Write-ReportLine $stderr.TrimEnd()
        }

        if ($process.ExitCode -ne 0) {
            $failures.Add("$Name failed with exit code $($process.ExitCode)")
            Write-ReportLine "FAIL: $Name"
        } else {
            Write-ReportLine "PASS: $Name"
        }
    } catch {
        $failures.Add("$Name threw: $_")
        Write-ReportLine "FAIL: $Name"
        Write-ReportLine "$_"
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $stdoutPath
        Remove-Item -Force -ErrorAction SilentlyContinue $stderrPath
    }
}

Write-ReportLine "Project Iris diagnostics"
Write-ReportLine "Timestamp: $timestamp"
Write-ReportLine "Working directory: $(Get-Location)"

Invoke-NativeStep "Git status" "git" @("status", "--short", "--branch")

Invoke-NativeStep "Cargo format check" "cargo" @("fmt", "--all", "--", "--check")

Invoke-NativeStep "Cargo build" "cargo" @("build", "--workspace")

Invoke-NativeStep "Cargo test" "cargo" @("test", "--workspace")

Invoke-NativeStep "Xtask audit" "cargo" @("run", "-p", "xtask")

Invoke-NativeStep "Runtime self-check" "cargo" @("run", "-p", "iris-runtime", "--", "self-check")

Invoke-NativeStep "Runtime UI status" "cargo" @("run", "-p", "iris-runtime", "--", "ui-status")

Invoke-NativeStep "Runtime voice status" "cargo" @("run", "-p", "iris-runtime", "--", "voice-status")

Invoke-NativeStep "Runtime push-to-talk visible-state test" "cargo" @("run", "-p", "iris-runtime", "--", "voice-ptt-state-test")

Invoke-NativeStep "Runtime response post-check test" "cargo" @("run", "-p", "iris-runtime", "--", "response-check-test")

Invoke-NativeStep "Kokoro voice milestone verification" "powershell" @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\verify_iris_kokoro_voice_milestone.ps1"
)

Invoke-NativeStep "Live text and voice session dry-run" "powershell" @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\run_iris_live_text_voice_session.ps1",
    "-DryRun"
)

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
