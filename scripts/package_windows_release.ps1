$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot

$releaseRoot = Join-Path $repoRoot "release"
$stagingRoot = Join-Path $releaseRoot "staging"
$distRoot = Join-Path $releaseRoot "dist"
$packageRoot = Join-Path $stagingRoot "iris-windows"
$zipPath = Join-Path $distRoot "iris-windows.zip"
$shaPath = "$zipPath.sha256"
$installerPath = Join-Path $distRoot "install-iris-windows.ps1"
$installerShaPath = "$installerPath.sha256"

function Require-File {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required file: $Path"
    }
}

function Require-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Missing required directory: $Path"
    }
}

function Copy-RequiredFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    Require-File -Path $Source
    $destinationDir = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Copy-RequiredDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    Require-Directory -Path $Source
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

Write-Host "Packaging Iris Windows portable release from $repoRoot"

Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $distRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $packageRoot, $distRoot | Out-Null

Write-Host "Building release executables..."
& cargo build --workspace --release
if ($LASTEXITCODE -ne 0) {
    throw "cargo build --workspace --release failed with exit code $LASTEXITCODE"
}

$runtimeExe = Join-Path $repoRoot "target\release\iris-runtime.exe"
$tauriExe = Join-Path $repoRoot "target\release\iris-tauri.exe"
Require-File -Path $runtimeExe
Require-File -Path $tauriExe

Copy-RequiredFile -Source $runtimeExe -Destination (Join-Path $packageRoot "bin\iris-runtime.exe")
Copy-RequiredFile -Source $tauriExe -Destination (Join-Path $packageRoot "bin\iris-tauri.exe")

Copy-RequiredFile -Source (Join-Path $repoRoot "manifest.json") -Destination (Join-Path $packageRoot "manifest.json")
Copy-RequiredFile -Source (Join-Path $repoRoot "LICENSE") -Destination (Join-Path $packageRoot "LICENSE")
Copy-RequiredFile -Source (Join-Path $repoRoot "NOTICE.md") -Destination (Join-Path $packageRoot "NOTICE.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "SECURITY.md") -Destination (Join-Path $packageRoot "SECURITY.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "known-limitations.md") -Destination (Join-Path $packageRoot "known-limitations.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\download-and-run.md") -Destination (Join-Path $packageRoot "README_RELEASE.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\dynamic-system-context.md") -Destination (Join-Path $packageRoot "docs\dynamic-system-context.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\installer-preflight.md") -Destination (Join-Path $packageRoot "docs\installer-preflight.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\iris-architecture.md") -Destination (Join-Path $packageRoot "docs\iris-architecture.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\windows-installer.md") -Destination (Join-Path $packageRoot "docs\windows-installer.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\signed-installer-decision.md") -Destination (Join-Path $packageRoot "docs\signed-installer-decision.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\runtime-orchestration.md") -Destination (Join-Path $packageRoot "docs\runtime-orchestration.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\manual-end-user-test-v0.1.0.md") -Destination (Join-Path $packageRoot "docs\manual-end-user-test-v0.1.0.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "tools\kokoro_tts.py") -Destination (Join-Path $packageRoot "tools\kokoro_tts.py")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\iris_preflight_wizard.ps1") -Destination (Join-Path $packageRoot "Iris Preflight.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\iris_setup_wizard.ps1") -Destination (Join-Path $packageRoot "Iris Setup Wizard.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\iris_document_ocr.ps1") -Destination (Join-Path $packageRoot "Iris Document OCR.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\install_iris_windows.ps1") -Destination (Join-Path $packageRoot "Install Iris.ps1")

Copy-RequiredDirectory -Source (Join-Path $repoRoot "models") -Destination (Join-Path $packageRoot "models")
Copy-RequiredDirectory -Source (Join-Path $repoRoot "profiles") -Destination (Join-Path $packageRoot "profiles")
Copy-RequiredDirectory -Source (Join-Path $repoRoot "capabilities") -Destination (Join-Path $packageRoot "capabilities")
Copy-RequiredDirectory -Source (Join-Path $repoRoot "assets") -Destination (Join-Path $packageRoot "assets")
Copy-RequiredDirectory -Source (Join-Path $repoRoot "plugins") -Destination (Join-Path $packageRoot "plugins")

$hermesRuntime = Join-Path $repoRoot ".iris-runtime\hermes"
$browserRuntime = Join-Path $repoRoot ".iris-runtime\browser"
Copy-RequiredDirectory -Source (Join-Path $hermesRuntime ".venv") -Destination (Join-Path $packageRoot ".iris-runtime\hermes\.venv")
Copy-RequiredDirectory -Source (Join-Path $browserRuntime "node_modules") -Destination (Join-Path $packageRoot ".iris-runtime\browser\node_modules")
Copy-RequiredDirectory -Source (Join-Path $browserRuntime "browsers") -Destination (Join-Path $packageRoot ".iris-runtime\browser\browsers")
Copy-RequiredFile -Source (Join-Path $browserRuntime "package.json") -Destination (Join-Path $packageRoot ".iris-runtime\browser\package.json")
Copy-RequiredFile -Source (Join-Path $browserRuntime "package-lock.json") -Destination (Join-Path $packageRoot ".iris-runtime\browser\package-lock.json")

$runtimeManifest = [ordered]@{
    hermes_agent = [ordered]@{
        version = "0.16.0"
        wheel_sha256 = "accb5a4a4827b41b3d162d2eb0b5f6db585d942ee23a3678ef21fc94d21c34a2"
    }
    agent_browser = [ordered]@{
        version = "0.27.2"
        binary_sha256 = "013c9bb6084e72d69a8ebb6c3d5669ba117129479b81d9336012b36b91f490e5"
    }
    chrome_for_testing = [ordered]@{
        version = "149.0.7827.115"
        executable_sha256 = "815ac13164ee3a5fa15a0e119fe868ec8d6ef6b3bd16bbe35ddd1da57c515c56"
    }
    volatile_data_packaged = $false
}
$runtimeManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $packageRoot ".iris-runtime\runtime-manifest.json") -Encoding utf8

$startPs1 = @'
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeExe = Join-Path $root "bin\iris-runtime.exe"
$desktopExe = Join-Path $root "bin\iris-tauri.exe"
$manifestPath = Join-Path $root "manifest.json"
$kokoroModel = Join-Path $root "models\kokoro\kokoro-v1.0.onnx"
$kokoroVoices = Join-Path $root "models\kokoro\voices-v1.0.bin"
$whisperModel = Join-Path $root "models\whisper\ggml-tiny.en.bin"
$hermesPython = Join-Path $root ".iris-runtime\hermes\.venv\Scripts\python.exe"
$agentBrowser = Join-Path $root ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
$browserExe = Join-Path $root ".iris-runtime\browser\browsers\chrome-149.0.7827.115\chrome.exe"

function Require-File {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Iris release is missing required file: $Path"
    }
}

Require-File -Path $runtimeExe
Require-File -Path $desktopExe
Require-File -Path $manifestPath
Require-File -Path $kokoroModel
Require-File -Path $kokoroVoices
Require-File -Path $whisperModel
Require-File -Path $hermesPython
Require-File -Path $agentBrowser
Require-File -Path $browserExe

Set-Location -LiteralPath $root

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-OllamaReady {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -UseBasicParsing -TimeoutSec 2
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 500
    } catch {
        return $false
    }
}

function Get-IrisModelId {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        return [string]$manifest.model_policy.model_id
    } catch {
        return ""
    }
}

function Get-IrisNumCtx {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        return [int]$manifest.model_policy.num_ctx_ceiling
    } catch {
        return 8192
    }
}

function Test-OllamaModelManifest {
    param(
        [Parameter(Mandatory = $true)][string]$ModelsRoot,
        [Parameter(Mandatory = $true)][string]$ModelId
    )
    $parts = $ModelId.Split(":", 2)
    if ($parts.Count -ne 2) {
        return $false
    }
    $nameParts = $parts[0].Split("/", 2)
    $namespace = if ($nameParts.Count -eq 2) { $nameParts[0] } else { "library" }
    $name = if ($nameParts.Count -eq 2) { $nameParts[1] } else { $nameParts[0] }
    $manifest = Join-Path $ModelsRoot (Join-Path "manifests\registry.ollama.ai" (Join-Path $namespace (Join-Path $name $parts[1])))
    return Test-Path -LiteralPath $manifest -PathType Leaf
}

function Use-IrisOllamaModelStore {
    $modelId = Get-IrisModelId
    if (-not $modelId) {
        return
    }
    $candidates = @($env:OLLAMA_MODELS, "C:\.ollama", (Join-Path $env:USERPROFILE ".ollama\models")) | Where-Object { $_ }
    foreach ($candidate in $candidates) {
        if (Test-OllamaModelManifest -ModelsRoot $candidate -ModelId $modelId) {
            $env:OLLAMA_MODELS = $candidate
            return
        }
    }
}

function Test-OllamaModelAvailable {
    $modelId = Get-IrisModelId
    if (-not $modelId) {
        return $true
    }
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -UseBasicParsing -TimeoutSec 2
        $tags = $response.Content | ConvertFrom-Json
        return [bool](@($tags.models) | Where-Object { $_.name -eq $modelId } | Select-Object -First 1)
    } catch {
        return $false
    }
}

function Test-OllamaRuntimeCompatible {
    $modelId = Get-IrisModelId
    $requiredContext = Get-IrisNumCtx
    if (-not $modelId -or $requiredContext -le 0) {
        return $false
    }
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/ps" -UseBasicParsing -TimeoutSec 2
        $status = $response.Content | ConvertFrom-Json
        $model = @($status.models) | Where-Object { $_.name -eq $modelId -or $_.model -eq $modelId } | Select-Object -First 1
        return $null -ne $model -and [int64]$model.context_length -ge $requiredContext
    } catch {
        return $false
    }
}

function Use-IrisOllamaRuntimeSettings {
    $env:OLLAMA_CONTEXT_LENGTH = [string](Get-IrisNumCtx)
}

function Stop-OllamaForIris {
    Get-Process "ollama", "ollama app", "llama-server" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Start-OllamaForIris {
    Use-IrisOllamaModelStore
    Use-IrisOllamaRuntimeSettings

    if (Test-OllamaReady) {
        if ((Test-OllamaModelAvailable) -and (Test-OllamaRuntimeCompatible)) {
            return
        }
        Stop-OllamaForIris
        Start-Sleep -Seconds 2
    }
    if (-not (Test-CommandAvailable -Name "ollama")) {
        throw "Ollama is not available on PATH. Run Iris Setup Wizard or install Ollama for Windows."
    }
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        Start-Sleep -Milliseconds 500
        if (Test-OllamaReady) {
            return
        }
    }
    throw "Ollama did not become ready on 127.0.0.1:11434 after launch."
}

function Test-IrisAlreadyRunning {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)
    $resolved = [System.IO.Path]::GetFullPath($ExecutablePath)
    foreach ($process in @(Get-Process iris-tauri -ErrorAction SilentlyContinue)) {
        try {
            if ([System.IO.Path]::GetFullPath($process.Path) -ieq $resolved) {
                return $true
            }
        } catch {
            continue
        }
    }
    return $false
}

if ($env:IRIS_SELF_CHECK -eq "1" -or $args -contains "--self-check") {
    Start-OllamaForIris
    & $runtimeExe --self-check
    exit $LASTEXITCODE
}

Start-OllamaForIris
if (Test-IrisAlreadyRunning -ExecutablePath $desktopExe) {
    exit 0
}
Start-Process -FilePath $desktopExe -WorkingDirectory $root
'@

$startBat = @'
@echo off
setlocal
set "IRIS_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%IRIS_ROOT%Start Iris.ps1" %*
exit /b %ERRORLEVEL%
'@

$preflightBat = @'
@echo off
setlocal
set "IRIS_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%IRIS_ROOT%Iris Preflight.ps1" %*
exit /b %ERRORLEVEL%
'@

$setupBat = @'
@echo off
setlocal
set "IRIS_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%IRIS_ROOT%Iris Setup Wizard.ps1" %*
exit /b %ERRORLEVEL%
'@

$installBat = @'
@echo off
setlocal
set "IRIS_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%IRIS_ROOT%Install Iris.ps1" -RunSetup %*
exit /b %ERRORLEVEL%
'@

Set-Content -LiteralPath (Join-Path $packageRoot "Start Iris.ps1") -Value $startPs1 -Encoding utf8
Set-Content -LiteralPath (Join-Path $packageRoot "Start Iris.bat") -Value $startBat -Encoding ascii
Set-Content -LiteralPath (Join-Path $packageRoot "Check Iris Preflight.bat") -Value $preflightBat -Encoding ascii
Set-Content -LiteralPath (Join-Path $packageRoot "Iris Setup Wizard.bat") -Value $setupBat -Encoding ascii
Set-Content -LiteralPath (Join-Path $packageRoot "Install Iris.bat") -Value $installBat -Encoding ascii

Write-Host "Creating $zipPath"
Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath -Force

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $shaPath -Value "$hash  iris-windows.zip" -Encoding ascii
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\install_iris_windows.ps1") -Destination $installerPath
$installerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $installerShaPath -Value "$installerHash  install-iris-windows.ps1" -Encoding ascii

Write-Host "Iris Windows ZIP: $zipPath"
Write-Host "Iris Windows SHA256: $shaPath"
Write-Host "SHA256: $hash"
Write-Host "Iris Windows installer wrapper: $installerPath"
Write-Host "Iris Windows installer wrapper SHA256: $installerShaPath"
Write-Host "Installer SHA256: $installerHash"
