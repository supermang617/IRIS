$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot

$releaseRoot = Join-Path $repoRoot "release"
$stagingRoot = Join-Path $releaseRoot "staging"
$distRoot = Join-Path $releaseRoot "dist"
$packageRoot = Join-Path $stagingRoot "iris-windows"
$zipPath = Join-Path $distRoot "iris-windows.zip"
$shaPath = "$zipPath.sha256"

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
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\installer-preflight.md") -Destination (Join-Path $packageRoot "docs\installer-preflight.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\iris-architecture.md") -Destination (Join-Path $packageRoot "docs\iris-architecture.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\windows-installer.md") -Destination (Join-Path $packageRoot "docs\windows-installer.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\signed-installer-decision.md") -Destination (Join-Path $packageRoot "docs\signed-installer-decision.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\runtime-orchestration.md") -Destination (Join-Path $packageRoot "docs\runtime-orchestration.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "tools\kokoro_tts.py") -Destination (Join-Path $packageRoot "tools\kokoro_tts.py")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\iris_preflight_wizard.ps1") -Destination (Join-Path $packageRoot "Iris Preflight.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\iris_setup_wizard.ps1") -Destination (Join-Path $packageRoot "Iris Setup Wizard.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\install_iris_windows.ps1") -Destination (Join-Path $packageRoot "Install Iris.ps1")

Copy-RequiredDirectory -Source (Join-Path $repoRoot "models") -Destination (Join-Path $packageRoot "models")
Copy-RequiredDirectory -Source (Join-Path $repoRoot "profiles") -Destination (Join-Path $packageRoot "profiles")
Copy-RequiredDirectory -Source (Join-Path $repoRoot "capabilities") -Destination (Join-Path $packageRoot "capabilities")
Copy-RequiredDirectory -Source (Join-Path $repoRoot "assets") -Destination (Join-Path $packageRoot "assets")

$startPs1 = @'
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeExe = Join-Path $root "bin\iris-runtime.exe"
$desktopExe = Join-Path $root "bin\iris-tauri.exe"
$manifestPath = Join-Path $root "manifest.json"
$kokoroModel = Join-Path $root "models\kokoro\kokoro-v1.0.onnx"
$kokoroVoices = Join-Path $root "models\kokoro\voices-v1.0.bin"
$whisperModel = Join-Path $root "models\whisper\ggml-tiny.en.bin"

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

Set-Location -LiteralPath $root

if ($env:IRIS_SELF_CHECK -eq "1" -or $args -contains "--self-check") {
    & $runtimeExe --self-check
    exit $LASTEXITCODE
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

Write-Host "Iris Windows ZIP: $zipPath"
Write-Host "Iris Windows SHA256: $shaPath"
Write-Host "SHA256: $hash"
