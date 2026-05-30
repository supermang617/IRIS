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

Write-Section "Voice/text milestone preflight guard"

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

Write-Section "Milestone result"
Write-Host "PASS: Iris voice/text milestone preflight guard passed."
Write-Host "Live Kokoro/model/HUD checks are not part of this deterministic guard."
Write-Host "Next milestone: implement open back-and-forth typed and spoken conversation."
