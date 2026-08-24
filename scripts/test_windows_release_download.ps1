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

$maximumPortableBytes = 600MB
$portableBytes = (Get-Item -LiteralPath $zipPath).Length
if ($portableBytes -gt $maximumPortableBytes) {
    throw "Portable Iris ZIP exceeds the 600 MiB release budget: $portableBytes bytes."
}

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
$ciMode = $env:GITHUB_ACTIONS -eq "true"
$previousDataRoot = $env:IRIS_DATA_ROOT
$env:IRIS_DATA_ROOT = Join-Path $extractRoot "user-data"

function Invoke-CapturedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $output = @()
    $exitCode = 0
    try {
        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } catch {
        $output = @($output; ($_ | Out-String))
        $exitCode = 1
    }
    [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join "`n")
    }
}

function Find-TestPython313 {
    $candidates = New-Object System.Collections.Generic.List[string]
    $uv = Get-Command uv -ErrorAction SilentlyContinue
    if ($uv) {
        try {
            $candidate = (& $uv.Source python find 3.13 2>$null | Select-Object -First 1)
            if ($candidate) {
                $candidates.Add([string]$candidate) | Out-Null
            }
        } catch {
        }
    }
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        try {
            $candidate = (& $py.Source -3.13 -c "import sys; print(sys.executable)" 2>$null | Select-Object -First 1)
            if ($candidate) {
                $candidates.Add([string]$candidate) | Out-Null
            }
        } catch {
        }
    }
    foreach ($commandName in @("python3.13", "python")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command -and $command.Source) {
            $candidates.Add([string]$command.Source) | Out-Null
        }
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        try {
            $version = (& $candidate -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null | Select-Object -First 1)
            if ($version -eq "3.13") {
                return [System.IO.Path]::GetFullPath($candidate)
            }
        } catch {
            continue
        }
    }
    throw "Test requires an exact Python 3.13 interpreter."
}

function Test-ExpectedCiPrerequisiteFailure {
    param([Parameter(Mandatory = $true)][string]$Output)
    return $Output.Contains("Python 3.13") -or
        $Output.Contains("Ollama is not available on PATH") -or
        $Output.Contains("Ollama/model health check failed") -or
        $Output.Contains("Iris's digest-verified model is not installed") -or
        $Output.Contains("[FAIL] Ollama executable") -or
        $Output.Contains("[FAIL] Configured Ollama model")
}

if (-not (Test-ExpectedCiPrerequisiteFailure -Output "Iris's digest-verified model is not installed on this clean runner.")) {
    throw "CI prerequisite classification must allow the packaged model-store diagnostic."
}

try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

    $required = @(
        "Start Iris.bat",
        "Start Iris.ps1",
        "Check Iris Preflight.bat",
        "Iris Preflight.ps1",
        "Iris Document OCR.ps1",
        "Initialize Iris Data Root.ps1",
        "Iris Setup Wizard.bat",
        "Iris Setup Wizard.ps1",
        "Install Iris.bat",
        "Install Iris.ps1",
        "Update Iris.bat",
        "Update Iris.ps1",
        "README_RELEASE.md",
        "docs\finish-checklist.md",
        "docs\installer-preflight.md",
        "docs\iris-architecture.md",
        "docs\windows-installer.md",
        "docs\signed-installer-decision.md",
        "docs\winget-release.md",
        "docs\runtime-orchestration.md",
        "docs\manual-test.md",
        "docs\manual-end-user-test.md",
        "manifest.json",
        "bin\iris-runtime.exe",
        "bin\iris-tauri.exe",
        "models\kokoro\kokoro-v1.0.onnx",
        "models\kokoro\voices-v1.0.bin",
        "models\whisper\ggml-tiny.en.bin",
        "tools\kokoro_tts.py",
        "tools\iris_image_provider.py",
        "plugins\hermes_sidecar\sidecar.py",
        "plugins\memory\iris_broker\provider.py",
        "plugins\hermes_acp\iris_acp.py",
        "profiles\iris_restricted.json",
        "profiles\iris_agentic.json",
        "profiles\iris_browser.json",
        "profiles\iris_ollama_model.lock.json",
        "profiles\iris_ollama_vision_model.lock.json",
        ".iris-runtime\hermes\.venv\Lib\site-packages\hermes_agent-0.18.0.dist-info\METADATA",
        ".iris-runtime\hermes\.venv\Lib\site-packages\agent_client_protocol-0.9.0.dist-info\METADATA",
        ".iris-runtime\voice\Lib\site-packages\kokoro_onnx-0.5.0.dist-info\METADATA",
        ".iris-runtime\voice\Lib\site-packages\soundfile-0.14.0.dist-info\METADATA",
        ".iris-runtime\voice\Lib\site-packages\numpy-2.5.1.dist-info\METADATA",
        ".iris-runtime\voice\Lib\site-packages\onnxruntime-1.28.0.dist-info\METADATA",
        ".iris-runtime\voice\runtime-lock.txt",
        "profiles\iris_voice_python_3_13.lock.txt",
        "scripts\iris_ollama_model_lock.ps1",
        ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe",
        ".iris-runtime\runtime-manifest.json",
        "capabilities\v0_1_capability_ledger.toml"
    )

    foreach ($relative in $required) {
        Require-File -Path (Join-Path $extractRoot $relative)
    }

    . (Join-Path $extractRoot "scripts\iris_ollama_model_lock.ps1")
    $packagedOllamaLock = Get-IrisOllamaModelLock -Root $extractRoot
    if ([string]$packagedOllamaLock.manifest_digest -cne "7c4fbc4573d646fa7a2bcd940cd682a57c5717fcd1b48fd96ea45b1ef24d499f" -or
        $packagedOllamaLock.general_vision_verified -ne $false) {
        throw "Packaged Ollama model lock differs from the audited runtime identity or general-vision policy."
    }
    $packagedVisionLock = Get-IrisOllamaModelLock -Root $extractRoot -Role Vision
    if ([string]$packagedVisionLock.model_id -cne "qwen3.5:4b" -or
        [string]$packagedVisionLock.manifest_digest -cne "2a654d98e6fba55d452b7043684e9b57a947e393bbffa62485a7aac05ee4eefd" -or
        $packagedVisionLock.general_vision_verified -ne $true) {
        throw "Packaged Ollama vision lock differs from the audited runtime identity or general-vision policy."
    }

    $releaseReadme = Get-Content -LiteralPath (Join-Path $extractRoot "README_RELEASE.md") -Raw
    foreach ($requiredManualLink in @("docs/manual-test.md", "docs/manual-end-user-test.md")) {
        if (-not $releaseReadme.Contains($requiredManualLink)) {
            throw "README_RELEASE.md must link to the packaged $requiredManualLink guide."
        }
    }
    $releaseDocReferences = @([regex]::Matches($releaseReadme, "docs/[A-Za-z0-9._/-]+\.md") |
            ForEach-Object { $_.Value } |
            Sort-Object -Unique)
    foreach ($releaseDocReference in $releaseDocReferences) {
        Require-File -Path (Join-Path $extractRoot $releaseDocReference.Replace("/", "\"))
    }
    foreach ($manualRelative in @("docs\manual-test.md", "docs\manual-end-user-test.md")) {
        $manual = Get-Content -LiteralPath (Join-Path $extractRoot $manualRelative) -Raw
        foreach ($requiredGuidance in @(
                "Safe is the startup default",
                "Agentic Session",
                "file, PowerShell, process, and isolated browser tools",
                "separate confirmation"
            )) {
            if (-not $manual.Contains($requiredGuidance)) {
                throw "$manualRelative is missing current Hermes guidance: $requiredGuidance"
            }
        }
        foreach ($staleGuidance in @(
                "v0.1.0",
                "latest Windows end-user test",
                "should expose no acting tools",
                "Hermes cannot run commands, edit files, control browsers/windows",
                "- No system control should occur."
            )) {
            if ($manual.Contains($staleGuidance)) {
                throw "$manualRelative contains stale Hermes/release guidance: $staleGuidance"
            }
        }
    }
    foreach ($volatile in @(
        ".iris-data",
        ".iris-runtime\hermes\home",
        ".iris-runtime\browser\browsers",
        ".iris-runtime\browser\profile",
        ".iris-runtime\browser\downloads",
        ".iris-runtime\browser\command-output"
    )) {
        if (Test-Path -LiteralPath (Join-Path $extractRoot $volatile)) {
            throw "Release ZIP contains volatile runtime data: $volatile"
        }
    }
    foreach ($unusedVenvPath in @(
        ".iris-runtime\hermes\.venv\Scripts",
        ".iris-runtime\hermes\.venv\locales",
        ".iris-runtime\hermes\.venv\pyvenv.cfg",
        ".iris-runtime\hermes\.venv\.gitignore",
        ".iris-runtime\hermes\.venv\.lock",
        ".iris-runtime\hermes\.venv\CACHEDIR.TAG"
    )) {
        if (Test-Path -LiteralPath (Join-Path $extractRoot $unusedVenvPath)) {
            throw "Release ZIP contains unused bundled-interpreter content: $unusedVenvPath"
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
    $foreignBrowserBinaries = @(Get-ChildItem -LiteralPath (Join-Path $extractRoot ".iris-runtime\browser\node_modules\agent-browser\bin") -File -Filter "agent-browser-*" |
            Where-Object Name -ne "agent-browser-win32-x64.exe")
    if ($foreignBrowserBinaries.Count -gt 0) {
        throw "Windows release contains non-Windows agent-browser binaries: $($foreignBrowserBinaries.Name -join ', ')"
    }
    $runtimeManifest = Get-Content -LiteralPath (Join-Path $extractRoot ".iris-runtime\runtime-manifest.json") -Raw | ConvertFrom-Json
    $agentBrowserHash = (Get-FileHash -LiteralPath (Join-Path $extractRoot ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe") -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($runtimeManifest.hermes_agent.version -ne "0.18.0" -or
        $runtimeManifest.hermes_agent.upstream_tag -ne "v2026.7.1" -or
        $runtimeManifest.hermes_agent.upstream_commit -ne "7c1a029553d87c43ecff8a3821336bc95872213b" -or
        $runtimeManifest.hermes_agent.wheel_sha256 -ne "bf75c02d59f7c464cd0d85026fb7ee2e6bb15f003beccab3442b572f1ae1fd37" -or
        [string]$runtimeManifest.hermes_agent.sigstore_entry -ne "2040635656" -or
        $runtimeManifest.hermes_agent.required_python -ne "3.13" -or
        $runtimeManifest.hermes_agent.bundled_site_packages -ne $true -or
        $runtimeManifest.hermes_agent.bundled_interpreter -ne $false) {
        throw "Packaged Hermes Agent metadata does not describe pinned site-packages with external Python 3.13."
    }
    $voiceProfileLock = Join-Path $extractRoot "profiles\iris_voice_python_3_13.lock.txt"
    $voiceRuntimeLock = Join-Path $extractRoot ".iris-runtime\voice\runtime-lock.txt"
    $voiceLockHash = (Get-FileHash -LiteralPath $voiceProfileLock -Algorithm SHA256).Hash.ToLowerInvariant()
    if (
        (Get-FileHash -LiteralPath $voiceRuntimeLock -Algorithm SHA256).Hash.ToLowerInvariant() -ne $voiceLockHash -or
        $runtimeManifest.voice_python.required_python -ne "3.13" -or
        $runtimeManifest.voice_python.platform -ne "win_amd64" -or
        $runtimeManifest.voice_python.bundled_site_packages -ne $true -or
        $runtimeManifest.voice_python.bundled_interpreter -ne $false -or
        $runtimeManifest.voice_python.lock_sha256 -ne $voiceLockHash -or
        [int]$runtimeManifest.voice_python.package_count -ne 32 -or
        $runtimeManifest.voice_python.core_versions.numpy -ne "2.5.1" -or
        $runtimeManifest.voice_python.core_versions.onnxruntime -ne "1.28.0" -or
        $runtimeManifest.voice_python.upgrade_owner -ne "AlejandroPinto.Iris"
    ) {
        throw "Packaged voice metadata does not describe the pinned Iris-owned Python 3.13 layer."
    }
    if ($agentBrowserHash -ne $runtimeManifest.agent_browser.binary_sha256) {
        throw "Packaged agent-browser binary hash does not match runtime-manifest.json."
    }
    if ($runtimeManifest.agent_browser.platform -ne "windows-x64" -or
        [int]$runtimeManifest.agent_browser.pruned_non_windows_binaries -lt 1 -or
        [int64]$runtimeManifest.agent_browser.pruned_bytes -le 0) {
        throw "Packaged agent-browser footprint metadata does not confirm Windows-only pruning."
    }
    if ($runtimeManifest.system_browser.bundled -ne $false -or
        $runtimeManifest.system_browser.preferred -ne "Google Chrome" -or
        $runtimeManifest.system_browser.winget_package -ne "Google.Chrome" -or
        $runtimeManifest.system_browser.executable_override -ne "IRIS_BROWSER_EXECUTABLE_PATH" -or
        $runtimeManifest.system_browser.isolated_session -ne $true -or
        $runtimeManifest.system_browser.persistent_profile -ne $false) {
        throw "Packaged system-browser metadata is incomplete or inaccurate."
    }
    $packagedLauncher = Get-Content -LiteralPath (Join-Path $extractRoot "Start Iris.ps1") -Raw
    foreach ($name in @(
            "OLLAMA_FLASH_ATTENTION",
            "OLLAMA_KV_CACHE_TYPE",
            "OLLAMA_NUM_PARALLEL",
            "OLLAMA_MAX_LOADED_MODELS"
        )) {
        if (-not $packagedLauncher.Contains("Set-IrisOllamaDefault -Name `"$name`"")) {
            throw "Packaged launcher is missing Ollama runtime default: $name"
        }
    }

    $before = Get-ListeningLoopbackState
    $startScript = Join-Path $extractRoot "Start Iris.ps1"
    $env:IRIS_SELF_CHECK = "1"
    $selfCheck = Invoke-CapturedCommand -FilePath $startScript -Arguments @("-SelfCheck")
    Remove-Item Env:\IRIS_SELF_CHECK -ErrorAction SilentlyContinue
    if ($ciMode) {
        if ($selfCheck.ExitCode -eq 0) {
            throw "CI release launcher self-check unexpectedly succeeded without runner prerequisites."
        }
        if (-not (Test-ExpectedCiPrerequisiteFailure -Output $selfCheck.Output)) {
            throw "CI release launcher self-check did not report a clear prerequisite failure: $($selfCheck.Output)"
        }
    } elseif ($selfCheck.ExitCode -ne 0) {
        throw "Release launcher self-check failed with exit code $($selfCheck.ExitCode): $($selfCheck.Output)"
    }
    $hermesPython = Find-TestPython313
    $hermesSitePackages = Join-Path $extractRoot ".iris-runtime\hermes\.venv\Lib\site-packages"
    $previousPythonPath = $env:PYTHONPATH
    $env:PYTHONPATH = if ($previousPythonPath) { "$hermesSitePackages;$previousPythonPath" } else { $hermesSitePackages }
    try {
        $hermesVersions = & $hermesPython -c "import hermes_cli, acp, importlib.metadata as m; print(m.version('hermes-agent')); print(m.version('agent-client-protocol'))" 2>&1
        if ($LASTEXITCODE -ne 0 -or ((@($hermesVersions) -join "`n").Trim() -ne "0.18.0`n0.9.0")) {
            throw "External Python 3.13 could not load the packaged Hermes packages: $(@($hermesVersions) -join "`n")"
        }
    } finally {
        if ($null -eq $previousPythonPath) {
            Remove-Item Env:\PYTHONPATH -ErrorAction SilentlyContinue
        } else {
            $env:PYTHONPATH = $previousPythonPath
        }
    }

    $voiceSitePackages = Join-Path $extractRoot ".iris-runtime\voice\Lib\site-packages"
    $voiceSiteEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($voiceSitePackages))
    $voiceLockEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($voiceProfileLock))
    $voiceProbeCode = @"
import base64
import importlib.metadata as metadata
import pathlib
import re
import sys
site = pathlib.Path(base64.b64decode("$voiceSiteEncoded").decode()).resolve()
lock_text = pathlib.Path(base64.b64decode("$voiceLockEncoded").decode()).read_text(encoding="utf-8-sig")
normalize = lambda name: re.sub(r"[-_.]+", "-", name).lower()
expected = {
    normalize(match.group(1)): match.group(2)
    for match in re.finditer(r"^([a-z0-9][a-z0-9._-]*)==([^ \\\r\n]+) \\$", lock_text, re.MULTILINE)
}
actual = {normalize(dist.metadata["Name"]): dist.version for dist in metadata.distributions(path=[str(site)])}
assert actual == expected, (actual, expected)
sys.path.insert(0, str(site))
import kokoro_onnx, numpy, onnxruntime, soundfile
for module in (kokoro_onnx, numpy, onnxruntime, soundfile):
    assert site in pathlib.Path(module.__file__).resolve().parents, module.__file__
print(actual["kokoro-onnx"], actual["soundfile"], actual["numpy"], actual["onnxruntime"])
"@
    $voiceProbeEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($voiceProbeCode))
    $voiceVersions = & $hermesPython -S -c "import base64;exec(base64.b64decode('$voiceProbeEncoded'))" 2>&1
    if ($LASTEXITCODE -ne 0 -or ((@($voiceVersions) -join "`n").Trim() -ne "0.5.0 0.14.0 2.5.1 1.28.0")) {
        throw "Exact Python 3.13 could not load only the packaged, lock-matched voice layer: $(@($voiceVersions) -join "`n")"
    }

    $setupScript = Join-Path $extractRoot "Iris Setup Wizard.ps1"
    $env:IRIS_PREFLIGHT_FAST_LOCAL_ONLY = "1"
    $setupOutput = & $setupScript -NonInteractive 2>&1
    $setup = [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($setupOutput -join "`n")
    }
    Remove-Item Env:\IRIS_PREFLIGHT_FAST_LOCAL_ONLY -ErrorAction SilentlyContinue
    Set-Location -LiteralPath $originalLocation
    if ($ciMode) {
        if ($setup.ExitCode -ne 0 -and -not (Test-ExpectedCiPrerequisiteFailure -Output $setup.Output)) {
            throw "Packaged setup wizard failed for an unexpected reason in CI: $($setup.Output)"
        }
    } elseif ($setup.ExitCode -ne 0) {
        throw "Packaged setup wizard failed with exit code $($setup.ExitCode): $($setup.Output)"
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
    if ($null -eq $previousDataRoot) {
        Remove-Item Env:\IRIS_DATA_ROOT -ErrorAction SilentlyContinue
    } else {
        $env:IRIS_DATA_ROOT = $previousDataRoot
    }
    Set-Location -LiteralPath $originalLocation
    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
}
