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
        "docs\dynamic-system-context.md",
        "plugins\hermes_sidecar\sidecar.py",
        "plugins\memory\iris_broker\provider.py"
        "plugins\hermes_acp\iris_acp.py"
        ".iris-runtime\hermes\.venv\Scripts\python.exe"
        ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
        ".iris-runtime\browser\browsers\chrome-149.0.7827.115\chrome.exe"
        ".iris-runtime\runtime-manifest.json"
    )) {
        $path = Join-Path $installRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Installed file missing: $path"
        }
    }
    $runtimeManifest = Get-Content -LiteralPath (Join-Path $installRoot ".iris-runtime\runtime-manifest.json") -Raw | ConvertFrom-Json
    $agentBrowserHash = (Get-FileHash -LiteralPath (Join-Path $installRoot ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe") -Algorithm SHA256).Hash.ToLowerInvariant()
    $chromeHash = (Get-FileHash -LiteralPath (Join-Path $installRoot ".iris-runtime\browser\browsers\chrome-149.0.7827.115\chrome.exe") -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($runtimeManifest.hermes_agent.version -ne "0.16.0" -or
        $agentBrowserHash -ne $runtimeManifest.agent_browser.binary_sha256 -or
        $chromeHash -ne $runtimeManifest.chrome_for_testing.executable_sha256) {
        throw "Installed Agentic runtime version/hash verification failed."
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
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcutPath in @(
        (Join-Path $startMenuDir "Iris.lnk"),
        (Join-Path $desktopDir "Iris.lnk")
    )) {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $expectedTarget = Join-Path $installRoot "bin\iris-tauri.exe"
        if ($shortcut.TargetPath -ne $expectedTarget) {
            throw "Iris shortcut must launch the GUI directly. Expected $expectedTarget but got $($shortcut.TargetPath)."
        }
        if ($shortcut.Arguments) {
            throw "Iris shortcut must not pass console-launcher arguments: $($shortcut.Arguments)"
        }
    }

    $profilePath = Join-Path $installRoot ".iris-data\dynamic_context.json"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profilePath) | Out-Null
    $profileMarker = '{"version":1,"enabled":false,"observation_count":7,"updated_ms":1234}'
    [System.IO.File]::WriteAllText($profilePath, $profileMarker, [System.Text.Encoding]::UTF8)

    & $installer -SourceZip $zipPath -Sha256Path $shaPath -InstallRoot $installRoot -StartMenuDir $startMenuDir -DesktopDir $desktopDir -NonInteractive
    if ($LASTEXITCODE -ne 0) {
        throw "Upgrade installer failed with exit code $LASTEXITCODE"
    }
    $preservedProfile = [System.IO.File]::ReadAllText($profilePath, [System.Text.Encoding]::UTF8)
    if ($preservedProfile -ne $profileMarker) {
        throw "Upgrade installer changed or removed the dynamic context profile."
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
