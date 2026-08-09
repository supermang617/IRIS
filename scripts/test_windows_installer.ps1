param([switch]$TransactionOnly)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot

$zipPath = Join-Path $repoRoot "release\dist\iris-windows.zip"
$shaPath = "$zipPath.sha256"
$installer = Join-Path $repoRoot "scripts\install_iris_windows.ps1"

$requiredInputs = @($installer)
if (-not $TransactionOnly) {
    $requiredInputs += @($zipPath, $shaPath)
}
foreach ($path in $requiredInputs) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required installer test input: $path"
    }
}

function New-SyntheticInstallerArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][int]$SelfCheckExitCode,
        [int]$SelfCheckOutputBytes = 0
    )

    $sourceRoot = Join-Path $Root "$Version-source"
    $zipPath = Join-Path $Root "$Version.zip"
    New-Item -ItemType Directory -Force -Path $sourceRoot | Out-Null
    $requiredFiles = @(
        "Start Iris.ps1",
        "Start Iris.bat",
        "Iris Setup Wizard.ps1",
        "Iris Preflight.ps1",
        "Iris Document OCR.ps1",
        "Initialize Iris Data Root.ps1",
        "Update Iris.ps1",
        "manifest.json",
        "bin\iris-runtime.exe",
        "bin\iris-tauri.exe",
        "models\kokoro\kokoro-v1.0.onnx",
        "models\kokoro\voices-v1.0.bin",
        "models\whisper\ggml-tiny.en.bin",
        ".iris-runtime\hermes\.venv\Lib\site-packages\hermes_agent-0.18.0.dist-info\METADATA",
        ".iris-runtime\voice\Lib\site-packages\kokoro_onnx-0.5.0.dist-info\METADATA",
        ".iris-runtime\voice\Lib\site-packages\soundfile-0.14.0.dist-info\METADATA",
        ".iris-runtime\voice\Lib\site-packages\numpy-2.5.1.dist-info\METADATA",
        ".iris-runtime\voice\Lib\site-packages\onnxruntime-1.28.0.dist-info\METADATA",
        ".iris-runtime\voice\runtime-lock.txt",
        "profiles\iris_voice_python_3_13.lock.txt",
        ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe",
        ".iris-runtime\runtime-manifest.json",
        "assets\synthetic-version.txt"
    )
    foreach ($relative in $requiredFiles) {
        $path = Join-Path $sourceRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        [System.IO.File]::WriteAllText($path, "$Version`n", [System.Text.Encoding]::UTF8)
    }

    $launcher = @"
param([switch]`$SelfCheck)
if (`$SelfCheck) {
    if ($SelfCheckOutputBytes -gt 0) {
        [Console]::Out.Write("O" * $SelfCheckOutputBytes)
        [Console]::Error.Write("E" * $SelfCheckOutputBytes)
    }
    Write-Host "synthetic Iris $Version self-check"
    exit $SelfCheckExitCode
}
exit 0
"@
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "Start Iris.ps1"), $launcher, [System.Text.Encoding]::UTF8)
    $initializer = @'
param(
    [string]$InstallRoot,
    [switch]$PersistForCurrentUser,
    [switch]$PassThru
)
$ErrorActionPreference = "Stop"
$resolved = if ($env:IRIS_DATA_ROOT) {
    [System.IO.Path]::GetFullPath($env:IRIS_DATA_ROOT)
} else {
    Join-Path ([System.IO.Path]::GetFullPath($InstallRoot)) ".iris-user-data"
}
New-Item -ItemType Directory -Force -Path $resolved | Out-Null
$statePath = Join-Path $resolved "user-state.txt"
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    [System.IO.File]::WriteAllText($statePath, "created-by-first-install", [System.Text.Encoding]::UTF8)
}
if ($PassThru) {
    Write-Output $resolved
}
'@
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "Initialize Iris Data Root.ps1"), $initializer, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "Iris Setup Wizard.ps1"), "exit 0`n", [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "manifest.json"), "{`"version`":`"$Version`"}`n", [System.Text.Encoding]::UTF8)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $sourceRoot,
        $zipPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )
    $shaPath = "$zipPath.sha256"
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText($shaPath, "$hash  $([System.IO.Path]::GetFileName($zipPath))`n", [System.Text.Encoding]::ASCII)
    return [pscustomobject]@{ ZipPath = $zipPath; ShaPath = $shaPath }
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
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$ExpectFailure
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
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()
    try {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-ProcessTree -ProcessId $process.Id
            [void]$process.WaitForExit(5000)
            throw "$Name timed out after $TimeoutSeconds seconds."
        }
        $process.WaitForExit()
        $output = @(
            $outputTask.GetAwaiter().GetResult(),
            $errorTask.GetAwaiter().GetResult()
        ) -join "`n"
        if ($ExpectFailure) {
            if ($process.ExitCode -eq 0) {
                throw "$Name unexpectedly succeeded: $output"
            }
            return $output
        }
        if ($process.ExitCode -ne 0) {
            throw "$Name failed with exit code $($process.ExitCode): $output"
        }
        return $output
    } finally {
        $process.Dispose()
        foreach ($leftover in @(Get-Process "ollama", "ollama app", "llama-server", "iris-tauri", "iris-runtime" -ErrorAction SilentlyContinue)) {
            if ($beforeProcesses -notcontains $leftover.Id) {
                Stop-Process -Id $leftover.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Test-PostCopyValidationRollback {
    $transactionTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-installer-transaction-" + [System.Guid]::NewGuid().ToString("N"))
    $installRoot = Join-Path $transactionTestRoot "Install"
    $startMenuDir = Join-Path $transactionTestRoot "StartMenu"
    $desktopDir = Join-Path $transactionTestRoot "Desktop"
    $dataRoot = Join-Path $transactionTestRoot "Data"
    $previousDataRoot = $env:IRIS_DATA_ROOT
    New-Item -ItemType Directory -Force -Path $transactionTestRoot, $desktopDir | Out-Null
    $env:IRIS_DATA_ROOT = $dataRoot

    try {
        $oldVersion = New-SyntheticInstallerArchive -Root $transactionTestRoot -Version "synthetic-v1" -SelfCheckExitCode 0
        $failingVersion = New-SyntheticInstallerArchive `
            -Root $transactionTestRoot `
            -Version "synthetic-v2" `
            -SelfCheckExitCode 37 `
            -SelfCheckOutputBytes (1024 * 1024)
        $powershell = (Get-Command powershell.exe).Source

        Invoke-SmokeCommand `
            -FilePath $powershell `
            -WorkingDirectory $repoRoot `
            -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installer`" -SourceZip `"$($oldVersion.ZipPath)`" -Sha256Path `"$($oldVersion.ShaPath)`" -InstallRoot `"$installRoot`" -StartMenuDir `"$startMenuDir`" -DesktopDir `"$desktopDir`" -NonInteractive -SelfCheckTimeoutSeconds 30" `
            -TimeoutSeconds 60 `
            -Name "synthetic v1 installer" | Out-Null

        $statePath = Join-Path $dataRoot "user-state.txt"
        $stateMarker = "user-owned-state-that-must-survive"
        [System.IO.File]::WriteAllText($statePath, $stateMarker, [System.Text.Encoding]::UTF8)
        $legacyStatePath = Join-Path $installRoot ".iris-data\legacy-state.txt"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacyStatePath) | Out-Null
        [System.IO.File]::WriteAllText($legacyStatePath, "legacy-state-must-survive", [System.Text.Encoding]::UTF8)

        $oldManifestPath = Join-Path $installRoot "install-manifest.json"
        $oldUninstallerPath = Join-Path $installRoot "Uninstall Iris.ps1"
        $oldManifest = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($oldManifestPath))
        $oldUninstaller = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($oldUninstallerPath))
        $oldLauncherHash = (Get-FileHash -LiteralPath (Join-Path $installRoot "Start Iris.ps1") -Algorithm SHA256).Hash
        $oldShortcutPath = Join-Path $startMenuDir "Iris.lnk"
        $shortcutShell = New-Object -ComObject WScript.Shell
        $oldShortcut = $shortcutShell.CreateShortcut($oldShortcutPath)
        $oldShortcut.Arguments = "--synthetic-v1-state"
        $oldShortcut.Save()

        $failureOutput = Invoke-SmokeCommand `
            -FilePath $powershell `
            -WorkingDirectory $repoRoot `
            -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installer`" -SourceZip `"$($failingVersion.ZipPath)`" -Sha256Path `"$($failingVersion.ShaPath)`" -InstallRoot `"$installRoot`" -StartMenuDir `"$startMenuDir`" -DesktopDir `"$desktopDir`" -NonInteractive -SelfCheckTimeoutSeconds 30" `
            -TimeoutSeconds 60 `
            -Name "synthetic v2 self-check failure rollback" `
            -ExpectFailure
        if (-not $failureOutput.Contains("self-check failed with exit code 37")) {
            throw "Synthetic v2 did not fail at the intended final installed self-check: $failureOutput"
        }
        $selfCheckLog = Join-Path $dataRoot "diagnostics\installer-self-check.log"
        if (-not (Test-Path -LiteralPath $selfCheckLog -PathType Leaf) -or
            (Get-Item -LiteralPath $selfCheckLog).Length -gt (1025 * 1024) -or
            -not (Get-Content -LiteralPath $selfCheckLog -Raw).Contains("process output truncated by Iris")) {
            throw "Installer self-check output capture was not bounded and marked as truncated."
        }

        if ((Get-Content -LiteralPath (Join-Path $installRoot "assets\synthetic-version.txt") -Raw).Trim() -ne "synthetic-v1") {
            throw "Self-check failure did not restore the old managed payload."
        }
        if ((Get-FileHash -LiteralPath (Join-Path $installRoot "Start Iris.ps1") -Algorithm SHA256).Hash -ne $oldLauncherHash) {
            throw "Self-check failure did not restore the old launcher."
        }
        if ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($oldManifestPath)) -ne $oldManifest) {
            throw "Self-check failure did not restore the old install manifest."
        }
        if ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($oldUninstallerPath)) -ne $oldUninstaller) {
            throw "Self-check failure did not restore the old uninstaller."
        }
        $restoredShortcut = $shortcutShell.CreateShortcut($oldShortcutPath)
        if ($restoredShortcut.Arguments -ne "--synthetic-v1-state") {
            throw "Self-check failure did not restore the old shortcut state."
        }
        if ([System.IO.File]::ReadAllText($statePath, [System.Text.Encoding]::UTF8) -ne $stateMarker -or
            [System.IO.File]::ReadAllText($legacyStatePath, [System.Text.Encoding]::UTF8) -ne "legacy-state-must-survive") {
            throw "Self-check failure changed pre-existing Iris user state."
        }
        if (@(Get-ChildItem -LiteralPath $transactionTestRoot -Force | Where-Object Name -Match '^Install\.iris-(staging|backup)-').Count -ne 0) {
            throw "Self-check rollback left transaction staging or backup data behind."
        }
    } finally {
        if ($null -eq $previousDataRoot) {
            Remove-Item Env:\IRIS_DATA_ROOT -ErrorAction SilentlyContinue
        } else {
            $env:IRIS_DATA_ROOT = $previousDataRoot
        }
        Remove-Item -LiteralPath $transactionTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-PostCopyValidationRollback
Write-Host "Windows installer post-copy rollback test passed."
if ($TransactionOnly) {
    exit 0
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
    throw "Installer test requires an exact Python 3.13 interpreter."
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-installer-smoke-" + [System.Guid]::NewGuid().ToString("N"))
$installRoot = Join-Path $testRoot "Install"
$startMenuDir = Join-Path $testRoot "StartMenu"
$desktopDir = Join-Path $testRoot "Desktop"
$dataRoot = Join-Path $testRoot "Data"
$previousDataRoot = $env:IRIS_DATA_ROOT
$env:IRIS_DATA_ROOT = $dataRoot
New-Item -ItemType Directory -Force -Path $testRoot, $desktopDir | Out-Null

try {
    $powershell = (Get-Command powershell.exe).Source
    Invoke-SmokeCommand `
        -FilePath $powershell `
        -WorkingDirectory $repoRoot `
        -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installer`" -SourceZip `"$zipPath`" -Sha256Path `"$shaPath`" -InstallRoot `"$installRoot`" -StartMenuDir `"$startMenuDir`" -DesktopDir `"$desktopDir`" -NonInteractive -SkipSelfCheck" `
        -TimeoutSeconds 600 `
        -Name "fresh installer smoke" | Out-Null

    foreach ($relative in @(
        "Start Iris.bat",
        "Iris Document OCR.ps1",
        "Initialize Iris Data Root.ps1",
        "Iris Setup Wizard.ps1",
        "Update Iris.ps1",
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
        ".iris-runtime\hermes\.venv\Lib\site-packages\hermes_agent-0.18.0.dist-info\METADATA"
        ".iris-runtime\hermes\.venv\Lib\site-packages\agent_client_protocol-0.9.0.dist-info\METADATA"
        ".iris-runtime\voice\Lib\site-packages\kokoro_onnx-0.5.0.dist-info\METADATA"
        ".iris-runtime\voice\Lib\site-packages\soundfile-0.14.0.dist-info\METADATA"
        ".iris-runtime\voice\Lib\site-packages\numpy-2.5.1.dist-info\METADATA"
        ".iris-runtime\voice\Lib\site-packages\onnxruntime-1.28.0.dist-info\METADATA"
        ".iris-runtime\voice\runtime-lock.txt"
        "profiles\iris_voice_python_3_13.lock.txt"
        ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
        ".iris-runtime\runtime-manifest.json"
    )) {
        $path = Join-Path $installRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Installed file missing: $path"
        }
    }
    $runtimeManifest = Get-Content -LiteralPath (Join-Path $installRoot ".iris-runtime\runtime-manifest.json") -Raw | ConvertFrom-Json
    $agentBrowserHash = (Get-FileHash -LiteralPath (Join-Path $installRoot ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe") -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($runtimeManifest.hermes_agent.version -ne "0.18.0" -or
        $runtimeManifest.hermes_agent.wheel_sha256 -ne "bf75c02d59f7c464cd0d85026fb7ee2e6bb15f003beccab3442b572f1ae1fd37" -or
        $runtimeManifest.hermes_agent.required_python -ne "3.13" -or
        $runtimeManifest.hermes_agent.bundled_interpreter -ne $false -or
        $agentBrowserHash -ne $runtimeManifest.agent_browser.binary_sha256 -or
        $runtimeManifest.system_browser.bundled -ne $false -or
        $runtimeManifest.system_browser.preferred -ne "Google Chrome" -or
        $runtimeManifest.system_browser.winget_package -ne "Google.Chrome" -or
        $runtimeManifest.system_browser.isolated_session -ne $true -or
        $runtimeManifest.system_browser.persistent_profile -ne $false) {
        throw "Installed Agentic runtime version/hash verification failed."
    }
    $voiceProfileLock = Join-Path $installRoot "profiles\iris_voice_python_3_13.lock.txt"
    $voiceRuntimeLock = Join-Path $installRoot ".iris-runtime\voice\runtime-lock.txt"
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
        throw "Installed voice runtime version/hash verification failed."
    }
    if (Test-Path -LiteralPath (Join-Path $installRoot ".iris-runtime\browser\browsers")) {
        throw "Installed payload duplicates a browser instead of using the isolated system Chrome runtime."
    }
    $installManifest = Get-Content -LiteralPath (Join-Path $installRoot "install-manifest.json") -Raw | ConvertFrom-Json
    if ([System.IO.Path]::GetFullPath([string]$installManifest.data_root) -ine [System.IO.Path]::GetFullPath($dataRoot)) {
        throw "Installer did not record the isolated per-user data root."
    }
    if ($null -ne $installManifest.source_root -or
        [System.IO.Path]::GetFullPath([string]$installManifest.source_zip) -ine [System.IO.Path]::GetFullPath($zipPath)) {
        throw "ZIP install manifest retained an ephemeral extraction path or the wrong source ZIP."
    }
    foreach ($unusedVenvPath in @(
        ".iris-runtime\hermes\.venv\Scripts",
        ".iris-runtime\hermes\.venv\locales",
        ".iris-runtime\hermes\.venv\pyvenv.cfg",
        ".iris-runtime\hermes\.venv\.gitignore",
        ".iris-runtime\hermes\.venv\.lock",
        ".iris-runtime\hermes\.venv\CACHEDIR.TAG"
    )) {
        if (Test-Path -LiteralPath (Join-Path $installRoot $unusedVenvPath)) {
            throw "Installed payload contains unused bundled-interpreter content: $unusedVenvPath"
        }
    }
    $hermesPython = Find-TestPython313
    $previousPythonPathForProbe = $env:PYTHONPATH
    $sitePackages = Join-Path $installRoot ".iris-runtime\hermes\.venv\Lib\site-packages"
    $env:PYTHONPATH = if ($previousPythonPathForProbe) { "$sitePackages;$previousPythonPathForProbe" } else { $sitePackages }
    try {
        $hermesVersions = Invoke-SmokeCommand `
            -FilePath $hermesPython `
            -WorkingDirectory $installRoot `
            -Arguments '-c "import hermes_cli, acp, importlib.metadata as m; print(m.version(''hermes-agent'')); print(m.version(''agent-client-protocol''))"' `
            -TimeoutSeconds 30 `
            -Name "installed Hermes package probe"
    } finally {
        if ($null -eq $previousPythonPathForProbe) {
            Remove-Item Env:\PYTHONPATH -ErrorAction SilentlyContinue
        } else {
            $env:PYTHONPATH = $previousPythonPathForProbe
        }
    }
    if ($hermesVersions.Trim().Replace("`r`n", "`n") -ne "0.18.0`n0.9.0") {
        throw "Installed Hermes Python is not locally runnable with the pinned packages: $hermesVersions"
    }

    $voiceSitePackages = Join-Path $installRoot ".iris-runtime\voice\Lib\site-packages"
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
    $voiceVersions = Invoke-SmokeCommand `
        -FilePath $hermesPython `
        -WorkingDirectory $installRoot `
        -Arguments "-S -c `"import base64;exec(base64.b64decode('$voiceProbeEncoded'))`"" `
        -TimeoutSeconds 30 `
        -Name "installed Iris-owned voice package probe"
    if ($voiceVersions.Trim() -ne "0.5.0 0.14.0 2.5.1 1.28.0") {
        throw "Installed voice Python layer is not locally runnable with only the locked packages: $voiceVersions"
    }

    foreach ($shortcut in @(
        (Join-Path $startMenuDir "Iris.lnk"),
        (Join-Path $startMenuDir "Iris Setup Wizard.lnk"),
        (Join-Path $startMenuDir "Update Iris.lnk"),
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

    $profilePath = Join-Path $dataRoot ".iris-data\dynamic_context.json"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profilePath) | Out-Null
    $profileMarker = '{"version":1,"enabled":false,"observation_count":7,"updated_ms":1234}'
    [System.IO.File]::WriteAllText($profilePath, $profileMarker, [System.Text.Encoding]::UTF8)
    $legacyPath = Join-Path $installRoot ".iris-data\legacy-memory.json"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacyPath) | Out-Null
    Set-Content -LiteralPath $legacyPath -Value "legacy-memory" -Encoding ascii

    # Hold a later managed directory open so replacement fails after earlier
    # directories have been swapped. The installer must restore the exact old
    # managed tree instead of leaving a partial upgrade behind.
    $rollbackMarker = Join-Path $installRoot "assets\transaction-rollback-marker.txt"
    Set-Content -LiteralPath $rollbackMarker -Value "preserve-on-rollback" -Encoding ascii
    $lockedModel = Join-Path $installRoot "models\whisper\ggml-tiny.en.bin"
    $lockStream = [System.IO.File]::Open(
        $lockedModel,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::None
    )
    try {
        Invoke-SmokeCommand `
            -FilePath $powershell `
            -WorkingDirectory $repoRoot `
            -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installer`" -SourceZip `"$zipPath`" -Sha256Path `"$shaPath`" -InstallRoot `"$installRoot`" -StartMenuDir `"$startMenuDir`" -DesktopDir `"$desktopDir`" -NonInteractive -SkipSelfCheck" `
            -TimeoutSeconds 600 `
            -Name "transaction rollback installer smoke" `
            -ExpectFailure | Out-Null
    } finally {
        $lockStream.Dispose()
    }
    if ((Get-Content -LiteralPath $rollbackMarker -Raw).Trim() -ne "preserve-on-rollback") {
        throw "Failed installer upgrade did not restore the original managed tree."
    }
    if (@(Get-ChildItem -LiteralPath $testRoot -Force | Where-Object Name -Match '^Install\.iris-(staging|backup)-').Count -ne 0) {
        throw "Failed installer upgrade left transaction staging or backup data behind."
    }

    Invoke-SmokeCommand `
        -FilePath $powershell `
        -WorkingDirectory $repoRoot `
        -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installer`" -SourceZip `"$zipPath`" -Sha256Path `"$shaPath`" -InstallRoot `"$installRoot`" -StartMenuDir `"$startMenuDir`" -DesktopDir `"$desktopDir`" -NonInteractive -SkipSelfCheck" `
        -TimeoutSeconds 600 `
        -Name "upgrade installer smoke" | Out-Null
    $preservedProfile = [System.IO.File]::ReadAllText($profilePath, [System.Text.Encoding]::UTF8)
    if ($preservedProfile -ne $profileMarker) {
        throw "Upgrade installer changed or removed the dynamic context profile."
    }
    $migratedLegacyPath = Join-Path $dataRoot ".iris-data\legacy-memory.json"
    if ((Get-Content -LiteralPath $migratedLegacyPath -Raw).Trim() -ne "legacy-memory") {
        throw "Upgrade installer did not migrate legacy install-root Iris data."
    }
    if (-not (Test-Path -LiteralPath $legacyPath -PathType Leaf)) {
        throw "Upgrade installer deleted legacy data after migration."
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
        (Join-Path $startMenuDir "Update Iris.lnk"),
        (Join-Path $startMenuDir "Uninstall Iris.lnk"),
        (Join-Path $desktopDir "Iris.lnk")
    )) {
        if (Test-Path -LiteralPath $shortcut) {
            throw "Shortcut remained after uninstall: $shortcut"
        }
    }
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        throw "Uninstaller removed preserved per-user Iris data."
    }

    Write-Host "Windows installer smoke test passed."
} finally {
    if ($null -eq $previousDataRoot) {
        Remove-Item Env:\IRIS_DATA_ROOT -ErrorAction SilentlyContinue
    } else {
        $env:IRIS_DATA_ROOT = $previousDataRoot
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
