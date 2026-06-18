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

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-ProcessTree -ProcessId ([int]$child.ProcessId)
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Invoke-SmokeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $beforeProcesses = @(Get-Process "ollama", "ollama app", "llama-server", "iris-tauri", "iris-runtime" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    [void]$process.Start()
    try {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-ProcessTree -ProcessId $process.Id
            throw "$Name timed out after $TimeoutSeconds seconds."
        }

        $output = @($process.StandardOutput.ReadToEnd(), $process.StandardError.ReadToEnd()) -join "`n"
        if ($process.ExitCode -ne 0) {
            throw "$Name failed with exit code $($process.ExitCode): $output"
        }
        return $output
    } finally {
        foreach ($leftover in @(Get-Process "ollama", "ollama app", "llama-server", "iris-tauri", "iris-runtime" -ErrorAction SilentlyContinue)) {
            if ($beforeProcesses -notcontains $leftover.Id) {
                Stop-Process -Id $leftover.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-installer-smoke-" + [System.Guid]::NewGuid().ToString("N"))
$installRoot = Join-Path $testRoot "Install"
$startMenuDir = Join-Path $testRoot "StartMenu"
$desktopDir = Join-Path $testRoot "Desktop"
New-Item -ItemType Directory -Force -Path $testRoot, $desktopDir | Out-Null

try {
    $powershell = (Get-Command powershell.exe).Source
    Invoke-SmokeCommand `
        -FilePath $powershell `
        -WorkingDirectory $repoRoot `
        -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installer`" -SourceZip `"$zipPath`" -Sha256Path `"$shaPath`" -InstallRoot `"$installRoot`" -StartMenuDir `"$startMenuDir`" -DesktopDir `"$desktopDir`" -NonInteractive -SkipSelfCheck" `
        -TimeoutSeconds 180 `
        -Name "fresh installer smoke" | Out-Null

    foreach ($relative in @(
        "Start Iris.bat",
        "Iris Document OCR.ps1",
        "Iris Setup Wizard.ps1",
        "Uninstall Iris.ps1",
        "install-manifest.json",
        "bin\iris-runtime.exe",
        "models\kokoro\kokoro-v1.0.onnx",
        "models\whisper\ggml-tiny.en.bin",
        "tools\iris_image_provider.py",
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
    $hermesPython = Join-Path $installRoot ".iris-runtime\hermes\.venv\Scripts\python.exe"
    $hermesVersions = Invoke-SmokeCommand `
        -FilePath $hermesPython `
        -WorkingDirectory $installRoot `
        -Arguments '-c "import importlib.metadata as m; print(m.version(''hermes-agent'')); print(m.version(''agent-client-protocol''))"' `
        -TimeoutSeconds 30 `
        -Name "installed Hermes Python probe"
    if ($hermesVersions.Trim().Replace("`r`n", "`n") -ne "0.16.0`n0.9.0") {
        throw "Installed Hermes Python is not locally runnable with the pinned packages: $hermesVersions"
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

    Invoke-SmokeCommand `
        -FilePath $powershell `
        -WorkingDirectory $repoRoot `
        -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installer`" -SourceZip `"$zipPath`" -Sha256Path `"$shaPath`" -InstallRoot `"$installRoot`" -StartMenuDir `"$startMenuDir`" -DesktopDir `"$desktopDir`" -NonInteractive -SkipSelfCheck" `
        -TimeoutSeconds 180 `
        -Name "upgrade installer smoke" | Out-Null
    $preservedProfile = [System.IO.File]::ReadAllText($profilePath, [System.Text.Encoding]::UTF8)
    if ($preservedProfile -ne $profileMarker) {
        throw "Upgrade installer changed or removed the dynamic context profile."
    }

    Invoke-SmokeCommand `
        -FilePath $powershell `
        -WorkingDirectory $installRoot `
        -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installRoot\Uninstall Iris.ps1`" -Quiet" `
        -TimeoutSeconds 60 `
        -Name "uninstaller smoke" | Out-Null
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
