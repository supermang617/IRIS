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

function Invoke-IrisNative {
    param(
        [string] $Name,
        [string] $FilePath,
        [string[]] $Arguments
    )

    Write-Section $Name

    $base = Join-Path $env:TEMP ("iris-native-" + [guid]::NewGuid().ToString())
    $stdout = "$base.out"
    $stderr = "$base.err"

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr

        if (Test-Path $stdout) { Get-Content -Path $stdout | ForEach-Object { Write-Host $_ } }
        if (Test-Path $stderr) { Get-Content -Path $stderr | ForEach-Object { Write-Host $_ } }

        if ($process.ExitCode -ne 0) {
            throw "$Name failed with exit code $($process.ExitCode)"
        }
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $stdout, $stderr
    }
}

Write-Section "Voice/text milestone guard"

Invoke-IrisNative "Foundation guard" "powershell" @(
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

if (Test-Path "scripts\diagnose_iris_current_milestone.ps1") {
    Invoke-IrisNative "Current milestone diagnostic dry-run" "powershell" @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "scripts\diagnose_iris_current_milestone.ps1"
    )
} else {
    Write-Host "No diagnose_iris_current_milestone.ps1 script found. Skipping dry-run."
}

Write-Section "Milestone result"
Write-Host "PASS: Iris voice/text milestone guard passed."
Write-Host "Next milestone: open back-and-forth typed and spoken conversation."
