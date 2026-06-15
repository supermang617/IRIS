$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot
$originalLocation = (Get-Location).Path

$zipPath = Join-Path $repoRoot "release\dist\iris-windows.zip"
$shaPath = "$zipPath.sha256"
$installerPath = Join-Path $repoRoot "release\dist\install-iris-windows.ps1"
$installerShaPath = "$installerPath.sha256"

function Require-File {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required file: $Path"
    }
}

function Get-ListeningLoopbackState {
    $connections = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, OwningProcess)
    $nonLoopback = @($connections | Where-Object {
        $_.LocalAddress -notin @("127.0.0.1", "::1")
    })
    [pscustomobject]@{
        Connections = @($connections)
        NonLoopback = $nonLoopback
    }
}

Require-File -Path $zipPath
Require-File -Path $shaPath
Require-File -Path $installerPath
Require-File -Path $installerShaPath

$expectedHash = ((Get-Content -LiteralPath $shaPath -Raw).Trim() -split "\s+")[0]
$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash.ToLowerInvariant()) {
    throw "SHA256 mismatch. Expected $expectedHash but got $actualHash"
}
$expectedInstallerHash = ((Get-Content -LiteralPath $installerShaPath -Raw).Trim() -split "\s+")[0]
$actualInstallerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualInstallerHash -ne $expectedInstallerHash.ToLowerInvariant()) {
    throw "Installer SHA256 mismatch. Expected $expectedInstallerHash but got $actualInstallerHash"
}

$extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-release-smoke-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

    $required = @(
        "Start Iris.bat",
        "Start Iris.ps1",
        "Check Iris Preflight.bat",
        "Iris Preflight.ps1",
        "Iris Document OCR.ps1",
        "Iris Setup Wizard.bat",
        "Iris Setup Wizard.ps1",
        "Install Iris.bat",
        "Install Iris.ps1",
        "README_RELEASE.md",
        "docs\finish-checklist.md",
        "docs\installer-preflight.md",
        "docs\iris-architecture.md",
        "docs\windows-installer.md",
        "docs\signed-installer-decision.md",
        "docs\runtime-orchestration.md",
        "docs\manual-end-user-test-v0.1.0.md",
        "manifest.json",
        "bin\iris-runtime.exe",
        "bin\iris-tauri.exe",
        "models\kokoro\kokoro-v1.0.onnx",
        "models\kokoro\voices-v1.0.bin",
        "models\whisper\ggml-tiny.en.bin",
        "tools\kokoro_tts.py",
        "plugins\hermes_sidecar\sidecar.py",
        "plugins\memory\iris_broker\provider.py",
        "plugins\hermes_acp\iris_acp.py",
        "profiles\iris_restricted.json",
        "profiles\iris_agentic.json",
        "profiles\iris_browser.json",
        ".iris-runtime\hermes\.venv\Scripts\python.exe",
        ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe",
        ".iris-runtime\browser\browsers\chrome-149.0.7827.115\chrome.exe",
        ".iris-runtime\runtime-manifest.json",
        "capabilities\v0_1_capability_ledger.toml"
    )

    foreach ($relative in $required) {
        Require-File -Path (Join-Path $extractRoot $relative)
    }
    foreach ($volatile in @(
        ".iris-data",
        ".iris-runtime\hermes\home",
        ".iris-runtime\browser\profile",
        ".iris-runtime\browser\downloads",
        ".iris-runtime\browser\command-output"
    )) {
        if (Test-Path -LiteralPath (Join-Path $extractRoot $volatile)) {
            throw "Release ZIP contains volatile runtime data: $volatile"
        }
    }
    $pythonCaches = @(Get-ChildItem -LiteralPath $extractRoot -Recurse -Force -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue)
    if ($pythonCaches.Count -gt 0) {
        throw "Release ZIP contains Python cache directories."
    }
    $pythonBytecode = @(Get-ChildItem -LiteralPath $extractRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".pyc", ".pyo") })
    if ($pythonBytecode.Count -gt 0) {
        throw "Release ZIP contains Python bytecode files."
    }
    $runtimeManifest = Get-Content -LiteralPath (Join-Path $extractRoot ".iris-runtime\runtime-manifest.json") -Raw | ConvertFrom-Json
    $agentBrowserHash = (Get-FileHash -LiteralPath (Join-Path $extractRoot ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe") -Algorithm SHA256).Hash.ToLowerInvariant()
    $chromeHash = (Get-FileHash -LiteralPath (Join-Path $extractRoot ".iris-runtime\browser\browsers\chrome-149.0.7827.115\chrome.exe") -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($runtimeManifest.hermes_agent.version -ne "0.16.0") {
        throw "Packaged Hermes Agent version is not pinned to 0.16.0."
    }
    if ($agentBrowserHash -ne $runtimeManifest.agent_browser.binary_sha256) {
        throw "Packaged agent-browser binary hash does not match runtime-manifest.json."
    }
    if ($chromeHash -ne $runtimeManifest.chrome_for_testing.executable_sha256) {
        throw "Packaged Chrome for Testing hash does not match runtime-manifest.json."
    }

    $before = Get-ListeningLoopbackState
    $startScript = Join-Path $extractRoot "Start Iris.ps1"
    $env:IRIS_SELF_CHECK = "1"
    & $startScript --self-check
    $exitCode = $LASTEXITCODE
    Remove-Item Env:\IRIS_SELF_CHECK -ErrorAction SilentlyContinue
    if ($exitCode -ne 0) {
        throw "Release launcher self-check failed with exit code $exitCode"
    }

    $setupScript = Join-Path $extractRoot "Iris Setup Wizard.ps1"
    $env:IRIS_PREFLIGHT_FAST_LOCAL_ONLY = "1"
    & $setupScript -NonInteractive
    $setupExitCode = $LASTEXITCODE
    Remove-Item Env:\IRIS_PREFLIGHT_FAST_LOCAL_ONLY -ErrorAction SilentlyContinue
    Set-Location -LiteralPath $originalLocation
    if ($setupExitCode -ne 0) {
        throw "Packaged setup wizard failed with exit code $setupExitCode"
    }

    $after = Get-ListeningLoopbackState
    $newNonLoopback = @($after.NonLoopback | Where-Object {
        $candidate = $_
        -not ($before.NonLoopback | Where-Object {
            $_.LocalAddress -eq $candidate.LocalAddress -and
            $_.LocalPort -eq $candidate.LocalPort -and
            $_.OwningProcess -eq $candidate.OwningProcess
        })
    })

    if ($newNonLoopback.Count -gt 0) {
        $details = ($newNonLoopback | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort) pid=$($_.OwningProcess)" }) -join ", "
        throw "Smoke test found new non-loopback listeners: $details"
    }

    Write-Host "Release ZIP smoke test passed."
    Write-Host "Extracted to: $extractRoot"
    Write-Host "SHA256: $actualHash"
} finally {
    Remove-Item Env:\IRIS_SELF_CHECK -ErrorAction SilentlyContinue
    Remove-Item Env:\IRIS_PREFLIGHT_FAST_LOCAL_ONLY -ErrorAction SilentlyContinue
    Set-Location -LiteralPath $originalLocation
    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
}
