param(
    [switch] $NonBlocking
)

$ErrorActionPreference = "Stop"
Set-Location -Path "C:\Projects\IRIS"

function Write-Section {
    param([string] $Text)
    Write-Host ""
    Write-Host "=== $Text ==="
}

Write-Section "Manual live voice/text smoke"
Write-Host "This smoke check is intentionally separate from deterministic guards."

$diagnosticPath = "scripts\diagnose_iris_current_milestone.ps1"

if (-not (Test-Path $diagnosticPath)) {
    $message = "Missing scripts\diagnose_iris_current_milestone.ps1"

    if ($NonBlocking) {
        Write-Host "WARN: $message"
        exit 0
    }

    throw $message
}

$base = Join-Path $env:TEMP ("iris-manual-smoke-" + [guid]::NewGuid().ToString())
$stdout = "$base.out"
$stderr = "$base.err"

try {
    $argsList = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $diagnosticPath
    )

    $process = Start-Process -FilePath "powershell" -ArgumentList $argsList -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr

    if (Test-Path $stdout) {
        Get-Content -Path $stdout | ForEach-Object { Write-Host $_ }
    }

    if (Test-Path $stderr) {
        Get-Content -Path $stderr | ForEach-Object { Write-Host $_ }
    }

    if ($process.ExitCode -ne 0) {
        $message = "Manual live voice/text smoke failed with exit code $($process.ExitCode). This does not invalidate deterministic foundation checks."

        if ($NonBlocking) {
            Write-Host "WARN: $message"
            exit 0
        }

        throw $message
    }

    Write-Host ""
    Write-Host "PASS: Manual live voice/text smoke passed."
} finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $stdout, $stderr
}
