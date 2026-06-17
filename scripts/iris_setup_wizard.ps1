param(
    [switch]$NonInteractive,
    [switch]$InstallMissing,
    [switch]$OpenLinks
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ((Split-Path -Leaf $root) -ieq "scripts") {
    $root = (Resolve-Path -LiteralPath (Join-Path $root "..")).Path
}
Set-Location -LiteralPath $root

$diagnosticsDir = Join-Path $root "diagnostics"
$preflightJson = Join-Path $diagnosticsDir "preflight-report.json"
$setupReport = Join-Path $diagnosticsDir "setup-wizard-report.txt"
$modelId = "huihui_ai/gemma-4-abliterated:e2b"

function Write-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    $prefix = switch ($Status) {
        "PASS" { "[PASS]" }
        "WARN" { "[WARN]" }
        "FAIL" { "[FAIL]" }
        default { "[$Status]" }
    }
    Write-Host "$prefix $Name"
    Write-Host "       $Detail"
}

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    return $null
}

function Get-RepairPlan {
    param([Parameter(Mandatory = $true)]$Check)

    switch -Regex ($Check.Name) {
        "^WebView2 Runtime$" {
            return [pscustomobject]@{
                Title = "Install Microsoft Edge WebView2 Runtime"
                Description = "Iris desktop uses Tauri, which needs WebView2 on Windows."
                Link = "https://developer.microsoft.com/microsoft-edge/webview2/"
                Commands = @(
                    "winget install --id Microsoft.EdgeWebView2Runtime -e --accept-source-agreements --accept-package-agreements"
                )
                Action = "winget:webview2"
            }
        }
        "^Ollama executable$" {
            return [pscustomobject]@{
                Title = "Install Ollama for Windows"
                Description = "Iris uses local Ollama for text and vision. This does not add a cloud API."
                Link = "https://ollama.com/download/windows"
                Commands = @(
                    "winget install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements"
                )
                Action = "winget:ollama"
            }
        }
        "^Ollama service$" {
            return [pscustomobject]@{
                Title = "Start the local Ollama service"
                Description = "The model list failed because the local Ollama service is not responding."
                Link = "https://ollama.com/download/windows"
                Commands = @(
                    "ollama serve"
                )
                Action = "start:ollama"
            }
        }
        "^Configured Ollama model$" {
            $description = if ($NonInteractive) {
                "Open Iris after installation; the launcher self-check will verify the configured local model and report a clear error if it is unavailable."
            } else {
                "This downloads $modelId into the local Ollama model store."
            }
            return [pscustomobject]@{
                Title = "Download the configured local model"
                Description = $description
                Link = "https://ollama.com/library"
                Commands = @(
                    "ollama pull $modelId"
                )
                Action = "ollama:pull-model"
            }
        }
        "^Python executable$" {
            return [pscustomobject]@{
                Title = "Install Python for Kokoro voice"
                Description = "Text and vision can run without Python, but Kokoro speech needs Python."
                Link = "https://www.python.org/downloads/windows/"
                Commands = @(
                    "winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements"
                )
                Action = "winget:python"
            }
        }
        "^Python package kokoro-onnx$|^Python package soundfile$" {
            return [pscustomobject]@{
                Title = "Install Kokoro voice Python packages"
                Description = "These packages let Iris use the bundled Kokoro voice assets locally."
                Link = "https://pypi.org/project/kokoro-onnx/"
                Commands = @(
                    "python -m pip install kokoro-onnx soundfile"
                )
                Action = "pip:kokoro"
            }
        }
        "^Tesseract document OCR$" {
            return [pscustomobject]@{
                Title = "Install Tesseract OCR for document images"
                Description = "This installs a local OCR engine so Iris can read user-selected document images without cloud OCR."
                Link = "https://github.com/tesseract-ocr/tesseract"
                Commands = @(
                    "winget install --id tesseract-ocr.tesseract -e --accept-source-agreements --accept-package-agreements"
                )
                Action = "winget:tesseract"
            }
        }
        "^Kokoro ONNX model$|^Kokoro voices$|^Whisper ASR model$" {
            return [pscustomobject]@{
                Title = "Restore bundled Iris model assets"
                Description = "The portable Iris ZIP should include these local assets. Re-extract the complete release if they are missing."
                Link = "https://github.com/supermang617/IRIS/releases/latest"
                Commands = @(
                    "Expand-Archive -LiteralPath .\iris-windows.zip -DestinationPath .\iris-windows -Force"
                )
                Action = "manual:extract-release"
            }
        }
        "^Release ZIP integrity$" {
            return [pscustomobject]@{
                Title = "Verify or redownload the release ZIP"
                Description = "The ZIP and SHA256 must match before a beginner installs from it."
                Link = "https://github.com/supermang617/IRIS/releases/latest"
                Commands = @(
                    "Get-FileHash .\iris-windows.zip -Algorithm SHA256"
                )
                Action = "manual:verify-zip"
            }
        }
        default {
            return [pscustomobject]@{
                Title = "Manual repair needed"
                Description = $Check.Repair
                Link = ""
                Commands = @()
                Action = "manual:none"
            }
        }
    }
}

function Approve-Repair {
    param([Parameter(Mandatory = $true)]$Plan)

    if ($NonInteractive) {
        return $false
    }
    if ($InstallMissing) {
        return $true
    }

    Write-Host ""
    Write-Host $Plan.Title
    Write-Host $Plan.Description
    if ($Plan.Link) {
        Write-Host "Official link: $($Plan.Link)"
    }
    foreach ($command in @($Plan.Commands)) {
        Write-Host "Command: $command"
    }
    $answer = Read-Host "Run this repair now? Type YES to continue"
    return $answer -ceq "YES"
}

function Invoke-Repair {
    param([Parameter(Mandatory = $true)]$Plan)

    switch ($Plan.Action) {
        "winget:webview2" {
            if (-not (Test-CommandAvailable -Name "winget")) {
                throw "winget is not available. Use the official link instead: $($Plan.Link)"
            }
            & winget install --id Microsoft.EdgeWebView2Runtime -e --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) { throw "WebView2 winget install failed with exit code $LASTEXITCODE" }
        }
        "winget:ollama" {
            if (-not (Test-CommandAvailable -Name "winget")) {
                throw "winget is not available. Use the official link instead: $($Plan.Link)"
            }
            & winget install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) { throw "Ollama winget install failed with exit code $LASTEXITCODE" }
        }
        "winget:python" {
            if (-not (Test-CommandAvailable -Name "winget")) {
                throw "winget is not available. Use the official link instead: $($Plan.Link)"
            }
            & winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) { throw "Python winget install failed with exit code $LASTEXITCODE" }
        }
        "winget:tesseract" {
            if (-not (Test-CommandAvailable -Name "winget")) {
                throw "winget is not available. Use the official link instead: $($Plan.Link)"
            }
            & winget install --id tesseract-ocr.tesseract -e --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) { throw "Tesseract winget install failed with exit code $LASTEXITCODE" }
        }
        "start:ollama" {
            if (-not (Test-CommandAvailable -Name "ollama")) {
                throw "ollama is not available on PATH."
            }
            Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
            Start-Sleep -Seconds 3
        }
        "ollama:pull-model" {
            if (-not (Test-CommandAvailable -Name "ollama")) {
                throw "ollama is not available on PATH."
            }
            & ollama pull $modelId
            if ($LASTEXITCODE -ne 0) { throw "ollama pull failed with exit code $LASTEXITCODE" }
        }
        "pip:kokoro" {
            if (-not (Test-CommandAvailable -Name "python")) {
                throw "python is not available on PATH."
            }
            & python -m pip install kokoro-onnx soundfile
            if ($LASTEXITCODE -ne 0) { throw "pip install failed with exit code $LASTEXITCODE" }
        }
        default {
            if ($OpenLinks -and $Plan.Link) {
                Start-Process $Plan.Link
            }
            Write-Host "Manual step only. Use the guidance above."
        }
    }
}

function Invoke-Preflight {
    $preflightScript = Join-Path $root "scripts\iris_preflight_wizard.ps1"
    if (-not (Test-Path -LiteralPath $preflightScript -PathType Leaf)) {
        $preflightScript = Join-Path $root "Iris Preflight.ps1"
    }
    if (-not (Test-Path -LiteralPath $preflightScript -PathType Leaf)) {
        throw "Could not find Iris preflight script."
    }
    & $preflightScript -JsonPath $preflightJson -Quiet
    $exit = $LASTEXITCODE
    if (-not (Test-Path -LiteralPath $preflightJson -PathType Leaf)) {
        throw "Preflight did not write $preflightJson"
    }
    return [pscustomobject]@{
        ExitCode = $exit
        Report = Get-Content -LiteralPath $preflightJson -Raw | ConvertFrom-Json
    }
}

New-Item -ItemType Directory -Force -Path $diagnosticsDir | Out-Null
$transcript = New-Object System.Collections.Generic.List[string]

Write-Host "Iris setup wizard"
Write-Host "Root: $root"
Write-Host "Mode: $(if ($NonInteractive) { 'noninteractive diagnostics' } elseif ($InstallMissing) { 'install/download approved' } else { 'interactive approval per step' })"
Write-Host ""

$preflight = Invoke-Preflight
$report = $preflight.Report
$issues = @($report.checks | Where-Object { $_.Status -ne "PASS" })

foreach ($check in @($report.checks)) {
    Write-Step -Status $check.Status -Name $check.Name -Detail $check.Detail
    $transcript.Add("[$($check.Status)] $($check.Name): $($check.Detail)") | Out-Null
    if ($check.Status -ne "PASS") {
        $plan = Get-RepairPlan -Check $check
        Write-Host "       Repair: $($plan.Description)"
        if ($plan.Link) {
            Write-Host "       Link: $($plan.Link)"
        }
        foreach ($command in @($plan.Commands)) {
            Write-Host "       Copy/paste: $command"
        }
        if (Approve-Repair -Plan $plan) {
            Write-Host "       Running approved repair..."
            Invoke-Repair -Plan $plan
            $transcript.Add("REPAIR-RAN $($check.Name): $($plan.Action)") | Out-Null
        } else {
            $transcript.Add("REPAIR-SKIPPED $($check.Name): $($plan.Action)") | Out-Null
        }
    }
    Write-Host ""
}

if ((-not $NonInteractive) -and $issues.Count -gt 0) {
    Write-Host "Rerunning preflight after selected repairs..."
    $preflight = Invoke-Preflight
    $report = $preflight.Report
}

$failCount = [int]$report.summary.fail
$warnCount = [int]$report.summary.warn
$passCount = [int]$report.summary.pass

$lines = @(
    "Iris setup wizard report",
    "Root: $root",
    "Generated: $(Get-Date -Format o)",
    "Summary: PASS=$passCount WARN=$warnCount FAIL=$failCount",
    "Mode: $(if ($NonInteractive) { 'noninteractive diagnostics' } elseif ($InstallMissing) { 'install/download approved' } else { 'interactive approval per step' })",
    "",
    "Repairs:",
    $transcript,
    "",
    "Safety: repairs are fixed allowlisted commands or official links only. Iris runtime remains local-only and non-agentic."
)
Set-Content -LiteralPath $setupReport -Value $lines -Encoding utf8

Write-Host "Setup report: $setupReport"
Write-Host "Summary: PASS=$passCount WARN=$warnCount FAIL=$failCount"

if ($failCount -gt 0) {
    exit 1
}
exit 0
