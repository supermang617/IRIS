$ErrorActionPreference = "Stop"
Set-Location -Path "C:\Projects\IRIS"

New-Item -ItemType Directory -Force ".iris-dev\diagnostics" | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = ".iris-dev\diagnostics\iris-kokoro-direct-voice-$timestamp.txt"

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

function Invoke-NativeCapture {
    param(
        [string] $Name,
        [string] $FilePath,
        [string[]] $Arguments
    )

    Write-Section $Name

    $base = Join-Path $env:TEMP ("iris-kokoro-direct-" + [guid]::NewGuid().ToString())
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

Write-Section "Iris Kokoro direct voice validation"
Write-Report "Purpose: test Kokoro speech directly, without old mixed model-response scripts."

$kokoroModel = "C:\Projects\IRIS\.iris-dev\tts\kokoro\kokoro-v1_0.onnx"
$speakScript = "scripts\speak_iris_kokoro.ps1"

if (-not (Test-Path $kokoroModel)) {
    throw "Missing Kokoro model: $kokoroModel"
}

if (-not (Test-Path $speakScript)) {
    throw "Missing Kokoro speak script: $speakScript"
}

Write-Report "Kokoro model: $kokoroModel"
Write-Report "Speak script: $speakScript"

Invoke-NativeCapture "Direct Kokoro speak test" "powershell" @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $speakScript,
    "-Text",
    "Iris Kokoro voice provider is ready."
)

Write-Section "Result"
Write-Report "PASS: Kokoro direct voice validation passed."
Write-Report "Report: $report"
