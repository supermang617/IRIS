$ErrorActionPreference = "Stop"
Set-Location -Path "C:\Projects\IRIS"

New-Item -ItemType Directory -Force ".iris-dev\diagnostics" | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = ".iris-dev\diagnostics\iris-kokoro-provider-discovery-$timestamp.txt"

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

function Invoke-Capture {
    param(
        [string] $Name,
        [string] $FilePath,
        [string[]] $Arguments
    )

    Write-Section $Name

    if (-not (Get-Command $FilePath -ErrorAction SilentlyContinue)) {
        Write-Report "SKIP: command not found: $FilePath"
        return
    }

    $base = Join-Path $env:TEMP ("iris-kokoro-discovery-" + [guid]::NewGuid().ToString())
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

        Write-Report "Exit code: $($process.ExitCode)"
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $stdout, $stderr
    }
}

Write-Section "Iris Kokoro provider discovery"
Write-Report "No installs. No network. Discovery only."
Write-Report "Working directory: C:\Projects\IRIS"

Write-Section "Repo Kokoro file scan"

$repoHits = @(Get-ChildItem -Path "." -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notmatch "\\.git\\" -and
    $_.FullName -notmatch "\\target\\" -and
    $_.FullName -notmatch "\\.iris-dev\\" -and
    (
        $_.Name -match "kokoro" -or
        $_.Extension -eq ".onnx" -or
        $_.Name -match "voice" -or
        $_.Name -match "tts"
    )
})

if ($repoHits.Count -eq 0) {
    Write-Report "No Kokoro/TTS files found inside repo."
} else {
    $repoHits | Sort-Object FullName | Select-Object -First 120 | ForEach-Object {
        Write-Report $_.FullName
    }
}

Write-Section "Python command discovery"

foreach ($cmd in @("py", "python", "python3")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Report "FOUND command: $cmd"
    } else {
        Write-Report "MISSING command: $cmd"
    }
}

Invoke-Capture "Python version via py" "py" @("-3", "--version")
Invoke-Capture "Python version via python" "python" @("--version")

Write-Section "Python package probes"

$probeCode = "import importlib.util; packages = ['kokoro', 'kokoro_onnx', 'onnxruntime', 'numpy', 'soundfile', 'scipy', 'piper']; [print(('FOUND ' + name + ': ' + str(importlib.util.find_spec(name).origin)) if importlib.util.find_spec(name) else ('MISSING ' + name)) for name in packages]"

Invoke-Capture "Package probe via py" "py" @("-3", "-c", $probeCode)
Invoke-Capture "Package probe via python" "python" @("-c", $probeCode)

Write-Section "Common local Kokoro path scan"

$commonRoots = @(
    "$env:USERPROFILE\.cache",
    "$env:USERPROFILE\.local",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\AppData\Local",
    "$env:USERPROFILE\AppData\Roaming",
    "C:\Coding-Agent",
    "C:\Projects"
)

foreach ($root in $commonRoots) {
    if (-not (Test-Path $root)) {
        continue
    }

    Write-Report "Scanning: $root"

    try {
        $hits = @(Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match "kokoro" -or $_.Extension -eq ".onnx"
        } | Select-Object -First 80)

        foreach ($hit in $hits) {
            Write-Report $hit.FullName
        }
    } catch {
        Write-Report ("WARN: scan failed for {0}: {1}" -f $root, $_.Exception.Message)
    }
}

Write-Section "Discovery result"
Write-Report "PASS: Kokoro provider discovery completed."
Write-Report "Report: $report"
Write-Report "Next step: wire Kokoro as preferred provider using the discovered path."
