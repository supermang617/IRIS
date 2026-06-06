$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot

$zipPath = Join-Path $repoRoot "release\dist\iris-windows.zip"
$shaPath = "$zipPath.sha256"
$installer = Join-Path $repoRoot "scripts\install_iris_windows.ps1"

foreach ($path in @($zipPath, $shaPath, $installer)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required installer test input: $path"
    }
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-installer-smoke-" + [System.Guid]::NewGuid().ToString("N"))
$installRoot = Join-Path $testRoot "Install"
$startMenuDir = Join-Path $testRoot "StartMenu"
$desktopDir = Join-Path $testRoot "Desktop"
New-Item -ItemType Directory -Force -Path $testRoot, $desktopDir | Out-Null

try {
    & $installer -SourceZip $zipPath -Sha256Path $shaPath -InstallRoot $installRoot -StartMenuDir $startMenuDir -DesktopDir $desktopDir -RunSetup -SetupNonInteractive
    if ($LASTEXITCODE -ne 0) {
        throw "Installer failed with exit code $LASTEXITCODE"
    }

    foreach ($relative in @(
        "Start Iris.bat",
        "Iris Document OCR.ps1",
        "Iris Setup Wizard.ps1",
        "Uninstall Iris.ps1",
        "install-manifest.json",
        "bin\iris-runtime.exe",
        "models\kokoro\kokoro-v1.0.onnx",
        "models\whisper\ggml-tiny.en.bin",
        "plugins\hermes_sidecar\sidecar.py",
        "plugins\memory\iris_broker\provider.py"
    )) {
        $path = Join-Path $installRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Installed file missing: $path"
        }
    }

    foreach ($shortcut in @(
        (Join-Path $startMenuDir "Iris.lnk"),
        (Join-Path $startMenuDir "Iris Setup Wizard.lnk"),
        (Join-Path $startMenuDir "Uninstall Iris.lnk"),
        (Join-Path $desktopDir "Iris.lnk")
    )) {
        if (-not (Test-Path -LiteralPath $shortcut -PathType Leaf)) {
            throw "Shortcut missing: $shortcut"
        }
    }

    & (Join-Path $installRoot "Uninstall Iris.ps1") -Quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Uninstaller failed with exit code $LASTEXITCODE"
    }
    foreach ($shortcut in @(
        (Join-Path $startMenuDir "Iris.lnk"),
        (Join-Path $startMenuDir "Iris Setup Wizard.lnk"),
        (Join-Path $startMenuDir "Uninstall Iris.lnk"),
        (Join-Path $desktopDir "Iris.lnk")
    )) {
        if (Test-Path -LiteralPath $shortcut) {
            throw "Shortcut remained after uninstall: $shortcut"
        }
    }

    Write-Host "Windows installer smoke test passed."
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
