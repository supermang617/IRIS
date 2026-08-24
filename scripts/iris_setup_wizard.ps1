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

$ollamaModelLockHelper = Join-Path $root "scripts\iris_ollama_model_lock.ps1"
if (-not (Test-Path -LiteralPath $ollamaModelLockHelper -PathType Leaf)) {
    throw "Missing Iris Ollama model-lock verifier: $ollamaModelLockHelper"
}
. $ollamaModelLockHelper

$reportRoot = if ($env:IRIS_DATA_ROOT) { [System.IO.Path]::GetFullPath($env:IRIS_DATA_ROOT) } else { $root }
$diagnosticsDir = Join-Path $reportRoot "diagnostics"
$preflightJson = Join-Path $diagnosticsDir "preflight-report.json"
$setupReport = Join-Path $diagnosticsDir "setup-wizard-report.txt"
$modelId = [string](Get-IrisOllamaModelLock -Root $root).model_id
$visionModelId = [string](Get-IrisOllamaModelLock -Root $root -Role Vision).model_id
$modelIds = @($modelId, $visionModelId)

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

function Find-Python313 {
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        try {
            $candidate = (& $py.Source -3.13 -c "import sys; print(sys.executable)" 2>$null | Select-Object -First 1)
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                return [System.IO.Path]::GetFullPath($candidate)
            }
        } catch {
        }
    }
    foreach ($commandName in @("python3.13", "python")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if (-not $command -or -not $command.Source) {
            continue
        }
        try {
            $version = (& $command.Source -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null | Select-Object -First 1)
            if ($version -eq "3.13") {
                return [System.IO.Path]::GetFullPath($command.Source)
            }
        } catch {
            continue
        }
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
        "^System browser executable$" {
            return [pscustomobject]@{
                Title = "Install Google Chrome"
                Description = "Iris uses an installed Google Chrome executable in an isolated, domain-contained browser session. Manual sign-ins do not persist after that session closes."
                Link = "https://www.google.com/chrome/"
                Commands = @(
                    "winget install --id Google.Chrome -e --accept-source-agreements --accept-package-agreements"
                )
                Action = "winget:chrome"
            }
        }
        "^Ollama executable$" {
            return [pscustomobject]@{
                Title = "Install Ollama for Windows"
                Description = "Iris uses loopback-only Ollama with an exact companion model and an exact visual-only model. Startup verifies both locks and a raw visual projector canary. This does not add a cloud API."
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
        "^Configured Ollama (vision )?model( identity)?$" {
            $description = if ($NonInteractive) {
                "Open Iris after installation; the launcher self-check will verify the configured local model and report a clear error if it is unavailable."
            } else {
                "This downloads Iris's exact companion and visual models into the local Ollama model store. If either locked digest still differs afterward, update Iris or restore its audited model store instead of bypassing verification."
            }
            return [pscustomobject]@{
                Title = "Download the configured local models"
                Description = $description
                Link = "https://ollama.com/library"
                Commands = @(
                    "ollama pull $modelId",
                    "ollama pull $visionModelId"
                )
                Action = "ollama:pull-model"
            }
        }
        "^Python executable$" {
            return [pscustomobject]@{
                Title = "Install exact Python 3.13"
                Description = "Iris uses this interpreter with its own pinned Hermes, image-provider, and Kokoro voice package layers."
                Link = "https://www.python.org/downloads/windows/"
                Commands = @(
                    "winget install --id Python.Python.3.13 -e --accept-source-agreements --accept-package-agreements"
                )
                Action = "winget:python"
            }
        }
        "^Iris-owned voice Python layer$" {
            return [pscustomobject]@{
                Title = "Restore the Iris-owned voice runtime"
                Description = "The voice layer is part of Iris and must be replaced as a hash-locked unit. Re-extract the release or upgrade Iris; do not install unpinned packages globally."
                Link = "https://github.com/supermang617/IRIS/releases/latest"
                Commands = @(
                    "winget upgrade --id AlejandroPinto.Iris -e"
                )
                Action = "manual:restore-release"
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
        "winget:chrome" {
            if (-not (Test-CommandAvailable -Name "winget")) {
                throw "winget is not available. Use the official link instead: $($Plan.Link)"
            }
            & winget install --id Google.Chrome -e --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) { throw "Google Chrome winget install failed with exit code $LASTEXITCODE" }
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
            & winget install --id Python.Python.3.13 -e --accept-source-agreements --accept-package-agreements
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
            $env:OLLAMA_HOST = "127.0.0.1:11434"
            Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
            Start-Sleep -Seconds 3
        }
        "ollama:pull-model" {
            if (-not (Test-CommandAvailable -Name "ollama")) {
                throw "ollama is not available on PATH."
            }
            foreach ($requiredModelId in $modelIds) {
                & ollama pull $requiredModelId
                if ($LASTEXITCODE -ne 0) { throw "ollama pull $requiredModelId failed with exit code $LASTEXITCODE" }
            }
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
