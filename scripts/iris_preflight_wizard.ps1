param(
    [string]$JsonPath = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ((Split-Path -Leaf $root) -ieq "scripts") {
    $root = (Resolve-Path -LiteralPath (Join-Path $root "..")).Path
}
Set-Location -LiteralPath $root

$modelId = "huihui_ai/gemma-4-abliterated:e2b"
$minimumRamGb = 16
$recommendedFreeDiskGb = 12
$reportRoot = if ($env:IRIS_DATA_ROOT) { [System.IO.Path]::GetFullPath($env:IRIS_DATA_ROOT) } else { $root }
$reportDir = Join-Path $reportRoot "diagnostics"
$reportPath = Join-Path $reportDir "preflight-report.txt"
$jsonReportPath = if ($JsonPath) { $JsonPath } else { Join-Path $reportDir "preflight-report.json" }
$fastLocalOnly = $env:IRIS_PREFLIGHT_FAST_LOCAL_ONLY -eq "1"
$results = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("PASS", "WARN", "FAIL")][string]$Status,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail,
        [Parameter(Mandatory = $true)][string]$Repair
    )
    $results.Add([pscustomobject]@{
        Status = $Status
        Name = $Name
        Detail = $Detail
        Repair = $Repair
    }) | Out-Null
}

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    return $null
}

function Test-File {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Test-Path -LiteralPath $Path -PathType Leaf
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-ProcessTree -ProcessId ([int]$child.ProcessId)
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Invoke-PreflightProbe {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [int]$TimeoutSeconds = 20
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $root
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    [void]$process.Start()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-ProcessTree -ProcessId $process.Id
        return [pscustomobject]@{
            ExitCode = 124
            Output = ""
            Error = "timed out after $TimeoutSeconds seconds"
        }
    }

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = $process.StandardOutput.ReadToEnd()
        Error = $process.StandardError.ReadToEnd()
    }
}

function Test-WebView2 {
    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients",
        "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients"
    )
    foreach ($rootKey in $roots) {
        if (-not (Test-Path $rootKey)) {
            continue
        }
        foreach ($key in Get-ChildItem $rootKey -ErrorAction SilentlyContinue) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if (($props.name -like "*WebView2*") -or $props.pv) {
                return $true
            }
        }
    }
    return $false
}

function Find-IrisBrowserExecutable {
    if (-not [string]::IsNullOrWhiteSpace($env:IRIS_BROWSER_EXECUTABLE_PATH)) {
        $configured = [System.IO.Path]::GetFullPath($env:IRIS_BROWSER_EXECUTABLE_PATH)
        if (Test-Path -LiteralPath $configured -PathType Leaf) {
            return [pscustomobject]@{
                Available = $true
                Path = $configured
                Detail = "Found the configured browser from IRIS_BROWSER_EXECUTABLE_PATH at $configured."
            }
        }
        return [pscustomobject]@{
            Available = $false
            Path = $configured
            Detail = "IRIS_BROWSER_EXECUTABLE_PATH points to a missing file: $configured."
        }
    }

    $candidates = @(
        @{ Root = ${env:ProgramFiles(x86)}; Relative = "Microsoft\Edge\Application\msedge.exe" },
        @{ Root = $env:ProgramFiles; Relative = "Microsoft\Edge\Application\msedge.exe" },
        @{ Root = $env:LOCALAPPDATA; Relative = "Microsoft\Edge\Application\msedge.exe" },
        @{ Root = $env:ProgramFiles; Relative = "Google\Chrome\Application\chrome.exe" },
        @{ Root = ${env:ProgramFiles(x86)}; Relative = "Google\Chrome\Application\chrome.exe" },
        @{ Root = $env:LOCALAPPDATA; Relative = "Google\Chrome\Application\chrome.exe" }
    )
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate.Root)) {
            continue
        }
        $path = Join-Path ([string]$candidate.Root) ([string]$candidate.Relative)
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return [pscustomobject]@{
                Available = $true
                Path = [System.IO.Path]::GetFullPath($path)
                Detail = "Found a supported system browser at $([System.IO.Path]::GetFullPath($path))."
            }
        }
    }

    return [pscustomobject]@{
        Available = $false
        Path = ""
        Detail = "Microsoft Edge or Google Chrome was not found in the supported Windows install locations."
    }
}

function Find-Python313 {
    $candidates = New-Object System.Collections.Generic.List[string]

    $uv = Get-Command uv -ErrorAction SilentlyContinue
    if ($uv) {
        try {
            $uvPython = (& $uv.Source python find 3.13 2>$null | Select-Object -First 1)
            if ($uvPython) {
                $candidates.Add([string]$uvPython) | Out-Null
            }
        } catch {
        }
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        try {
            $pyPython = (& $py.Source -3.13 -c "import sys; print(sys.executable)" 2>$null | Select-Object -First 1)
            if ($pyPython) {
                $candidates.Add([string]$pyPython) | Out-Null
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

    foreach ($base in @($env:APPDATA, $env:LOCALAPPDATA) | Where-Object { $_ }) {
        $uvRoot = Join-Path $base "uv\python"
        if (Test-Path -LiteralPath $uvRoot -PathType Container) {
            foreach ($candidate in @(Get-ChildItem -LiteralPath $uvRoot -Directory -Filter "cpython-3.13*" -ErrorAction SilentlyContinue)) {
                $candidates.Add((Join-Path $candidate.FullName "python.exe")) | Out-Null
            }
        }
    }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\Python\Python313\python.exe")) | Out-Null
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        try {
            $probe = Invoke-PreflightProbe `
                -FilePath ([System.IO.Path]::GetFullPath($candidate)) `
                -Arguments '-c "import sys; print(f''{sys.version_info.major}.{sys.version_info.minor}'')"' `
                -TimeoutSeconds 10
            if ($probe.ExitCode -eq 0 -and $probe.Output.Trim() -eq "3.13") {
                return [System.IO.Path]::GetFullPath($candidate)
            }
        } catch {
            continue
        }
    }
    return $null
}

function Test-IrisVoiceRuntime {
    param(
        [string]$PythonPath,
        [Parameter(Mandatory = $true)][string]$SitePackages,
        [Parameter(Mandatory = $true)][string]$LockPath,
        [Parameter(Mandatory = $true)][string]$RuntimeLockPath,
        [Parameter(Mandatory = $true)][string]$RuntimeManifestPath
    )

    if (-not $PythonPath) {
        return [pscustomobject]@{
            Available = $false
            Detail = "Exact Python 3.13 was not found, so the Iris-owned voice layer could not be audited."
        }
    }
    foreach ($required in @($SitePackages, $LockPath, $RuntimeLockPath)) {
        if (-not (Test-Path -LiteralPath $required)) {
            return [pscustomobject]@{
                Available = $false
                Detail = "The Iris-owned voice layer is incomplete; missing $required."
            }
        }
    }

    $lockHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $LockPath).Hash.ToLowerInvariant()
    $runtimeLockHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RuntimeLockPath).Hash.ToLowerInvariant()
    if ($lockHash -ne $runtimeLockHash) {
        return [pscustomobject]@{
            Available = $false
            Detail = "The packaged voice runtime lock does not match profiles\iris_voice_python_3_13.lock.txt."
        }
    }
    if (Test-Path -LiteralPath $RuntimeManifestPath -PathType Leaf) {
        try {
            $runtimeManifest = Get-Content -LiteralPath $RuntimeManifestPath -Raw | ConvertFrom-Json
            if (
                $runtimeManifest.voice_python.required_python -ne "3.13" -or
                $runtimeManifest.voice_python.platform -ne "win_amd64" -or
                $runtimeManifest.voice_python.bundled_site_packages -ne $true -or
                $runtimeManifest.voice_python.bundled_interpreter -ne $false -or
                $runtimeManifest.voice_python.lock_sha256 -ne $lockHash
            ) {
                return [pscustomobject]@{
                    Available = $false
                    Detail = "runtime-manifest.json does not match the Iris-owned voice lock and Python 3.13 contract."
                }
            }
        } catch {
            return [pscustomobject]@{
                Available = $false
                Detail = "Could not validate the packaged voice runtime manifest: $($_.Exception.Message)"
            }
        }
    }

    $siteEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($SitePackages)))
    $lockEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($LockPath)))
    $code = @"
import base64
import importlib.metadata as metadata
import pathlib
import re
import sys

site = pathlib.Path(base64.b64decode("$siteEncoded").decode()).resolve()
lock_path = pathlib.Path(base64.b64decode("$lockEncoded").decode()).resolve()
lock_text = lock_path.read_text(encoding="utf-8-sig")
normalize = lambda name: re.sub(r"[-_.]+", "-", name).lower()
expected = {
    normalize(match.group(1)): match.group(2)
    for match in re.finditer(r"^([a-z0-9][a-z0-9._-]*)==([^ \\\r\n]+) \\$", lock_text, re.MULTILINE)
}
actual = {
    normalize(dist.metadata["Name"]): dist.version
    for dist in metadata.distributions(path=[str(site)])
}
if actual != expected:
    raise SystemExit("bundled distribution set does not match the voice lock")
sys.path.insert(0, str(site))
import kokoro_onnx
import numpy
import onnxruntime
import soundfile
for module in (kokoro_onnx, numpy, onnxruntime, soundfile):
    module_path = pathlib.Path(module.__file__).resolve()
    if site not in module_path.parents:
        raise SystemExit(f"{module.__name__} escaped the Iris-owned voice layer: {module_path}")
print(
    "kokoro-onnx={}; soundfile={}; numpy={}; onnxruntime={}".format(
        actual["kokoro-onnx"],
        actual["soundfile"],
        actual["numpy"],
        actual["onnxruntime"],
    )
)
"@
    $codeEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($code))
    $probe = Invoke-PreflightProbe `
        -FilePath $PythonPath `
        -Arguments "-S -c `"import base64;exec(base64.b64decode('$codeEncoded'))`"" `
        -TimeoutSeconds 30

    return [pscustomobject]@{
        Available = ($probe.ExitCode -eq 0)
        Detail = if ($probe.ExitCode -eq 0) {
            "Hash-matched lock and isolated imports passed with $($probe.Output.Trim())."
        } else {
            "The bundled voice layer failed its isolated import/version audit: $($probe.Error.Trim())"
        }
    }
}

function Find-Tesseract {
    $command = Get-Command "tesseract" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    foreach ($candidate in @(
            "C:\Program Files\Tesseract-OCR\tesseract.exe",
            "C:\Program Files (x86)\Tesseract-OCR\tesseract.exe"
        )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

function Test-ConfiguredModelVisionCapability {
    param([Parameter(Mandatory = $true)][string]$ModelId)

    try {
        $showBody = @{ model = $ModelId } | ConvertTo-Json -Compress
        $show = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/show" -Method Post -ContentType "application/json" -Body $showBody -TimeoutSec 15
        $capabilities = @($show.capabilities) | Where-Object { $_ } | Select-Object -Unique
        if ($capabilities.Count -eq 0) {
            Add-Check -Status "WARN" -Name "Configured model vision capability" -Detail "$ModelId did not report capability metadata from Ollama /api/show." -Repair "Text/manual install can continue, but image-probe testing is blocked until the configured model reports vision capability."
            return
        }

        $capabilityText = ($capabilities -join ", ")
        if ($capabilities -contains "vision") {
            Add-Check -Status "PASS" -Name "Configured model vision capability" -Detail "$ModelId reports capabilities: $capabilityText." -Repair "No action needed."
        } else {
            Add-Check -Status "WARN" -Name "Configured model vision capability" -Detail "$ModelId reports capabilities: $capabilityText. Vision is not advertised." -Repair "Text/manual install can continue, but image-probe testing is blocked until the configured model reports vision capability."
        }
    } catch {
        Add-Check -Status "WARN" -Name "Configured model vision capability" -Detail "Could not query Ollama /api/show capability metadata: $($_.Exception.Message)" -Repair "Start Ollama and verify the configured model with `ollama show $ModelId` locally, then rerun this preflight."
    }
}

function Test-LoopbackOnlyManifest {
    $manifestPath = Join-Path $root "manifest.json"
    if (-not (Test-File -Path $manifestPath)) {
        Add-Check -Status "FAIL" -Name "Local-only manifest" -Detail "manifest.json is missing." -Repair "Re-extract iris-windows.zip or restore manifest.json from the release."
        return
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $externalDisabled = $manifest.ipc_policy.runtime_external_network -eq "disabled"
    $loopbackOnly = $manifest.ipc_policy.loopback_only -eq $true
    $hosts = @($manifest.ipc_policy.allowed_hosts)
    $hostOk = ($hosts -contains "127.0.0.1") -and ($hosts -contains "localhost")
    if ($externalDisabled -and $loopbackOnly -and $hostOk) {
        Add-Check -Status "PASS" -Name "Local-only manifest" -Detail "Runtime network is disabled and IPC is loopback-only." -Repair "No action needed."
    } else {
        Add-Check -Status "FAIL" -Name "Local-only manifest" -Detail "Manifest no longer matches the local-only loopback policy." -Repair "Use the official release manifest or inspect local changes before running Iris."
    }
}

if (-not $Quiet) {
    Write-Host "Iris preflight wizard"
    Write-Host "Root: $root"
    Write-Host ""
}

$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
if ($build -ge 10240) {
    Add-Check -Status "PASS" -Name "Windows version" -Detail "$($os.Caption), build $build." -Repair "No action needed."
} else {
    Add-Check -Status "FAIL" -Name "Windows version" -Detail "$($os.Caption), build $build." -Repair "Use Windows 10 or Windows 11."
}

$computer = Get-CimInstance Win32_ComputerSystem
$ramGb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 1)
if ($ramGb -ge $minimumRamGb) {
    Add-Check -Status "PASS" -Name "Memory/RAM" -Detail "$ramGb GB installed." -Repair "No action needed."
} else {
    Add-Check -Status "WARN" -Name "Memory/RAM" -Detail "$ramGb GB installed; $minimumRamGb GB or more is recommended." -Repair "Close heavy apps before running Iris, or use a machine with more RAM."
}

$driveName = ([System.IO.Path]::GetPathRoot($root).TrimEnd("\")).TrimEnd(":")
$drive = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
$freeDiskGb = if ($drive) { [math]::Round($drive.Free / 1GB, 1) } else { 0 }
if ($freeDiskGb -ge $recommendedFreeDiskGb) {
    Add-Check -Status "PASS" -Name "Disk space" -Detail "$freeDiskGb GB free on $($drive.Root)." -Repair "No action needed."
} else {
    Add-Check -Status "WARN" -Name "Disk space" -Detail "$freeDiskGb GB free; $recommendedFreeDiskGb GB or more is recommended for model/runtime headroom." -Repair "Free disk space before installing Ollama models or extracting future Iris releases."
}

if (Test-WebView2) {
    Add-Check -Status "PASS" -Name "WebView2 Runtime" -Detail "WebView2 appears to be installed." -Repair "No action needed."
} else {
    Add-Check -Status "FAIL" -Name "WebView2 Runtime" -Detail "WebView2 was not found in the usual registry locations." -Repair "Install Microsoft Edge WebView2 Runtime from Microsoft, then rerun this preflight."
}

$systemBrowser = Find-IrisBrowserExecutable
if ($systemBrowser.Available) {
    Add-Check -Status "PASS" -Name "System browser executable" -Detail $systemBrowser.Detail -Repair "No action needed."
} else {
    Add-Check -Status "FAIL" -Name "System browser executable" -Detail $systemBrowser.Detail -Repair "Install Microsoft Edge (WinGet package Microsoft.Edge), or set IRIS_BROWSER_EXECUTABLE_PATH to an absolute Edge/Chrome executable path, then restart Iris."
}

$ollamaPath = Test-CommandAvailable -Name "ollama"
if ($ollamaPath) {
    Add-Check -Status "PASS" -Name "Ollama executable" -Detail "Found ollama at $ollamaPath." -Repair "No action needed."
    if ($fastLocalOnly) {
        Add-Check -Status "WARN" -Name "Configured Ollama model" -Detail "Deferred live Ollama model check during noninteractive install to keep setup responsive." -Repair "Open Iris after installation; the bounded launcher self-check verifies Ollama/model readiness and reports a clear error if it is unavailable."
    } else {
        $ollamaList = Invoke-PreflightProbe -FilePath $ollamaPath -Arguments "list" -TimeoutSeconds 20
        $tags = @($ollamaList.Output, $ollamaList.Error) -join "`n"
        if ($ollamaList.ExitCode -eq 0) {
            if ($tags.Contains($modelId)) {
                Add-Check -Status "PASS" -Name "Configured Ollama model" -Detail "$modelId is available locally." -Repair "No action needed."
                Test-ConfiguredModelVisionCapability -ModelId $modelId
            } else {
                Add-Check -Status "FAIL" -Name "Configured Ollama model" -Detail "$modelId is not listed by the current Ollama service." -Repair "Install or point Ollama at the existing local model store for $modelId, then rerun this preflight. This script will not pull models automatically."
            }
        } else {
            Add-Check -Status "FAIL" -Name "Ollama service" -Detail "ollama list failed or timed out: $tags" -Repair "Start Ollama, then rerun this preflight."
        }
    }
} else {
    $status = if ($fastLocalOnly) { "WARN" } else { "FAIL" }
    $repair = if ($fastLocalOnly) {
        "Install Ollama for Windows before manual text or vision testing. Release smoke diagnostics only verify that this prerequisite is reported clearly."
    } else {
        "Install Ollama for Windows, then rerun this preflight. This script will not install it automatically."
    }
    Add-Check -Status $status -Name "Ollama executable" -Detail "ollama was not found on PATH." -Repair $repair
}

$tesseractPath = Find-Tesseract
if ($tesseractPath) {
    $version = (& $tesseractPath --version 2>&1 | Select-Object -First 1)
    Add-Check -Status "PASS" -Name "Tesseract document OCR" -Detail "Found $version at $tesseractPath." -Repair "No action needed."
} else {
    Add-Check -Status "WARN" -Name "Tesseract document OCR" -Detail "Tesseract was not found on PATH or in the default install folder." -Repair "Install Tesseract OCR locally if you want document-image OCR. Iris will not use cloud OCR."
}

$kokoroModel = Join-Path $root "models\kokoro\kokoro-v1.0.onnx"
$kokoroVoices = Join-Path $root "models\kokoro\voices-v1.0.bin"
$whisperModel = Join-Path $root "models\whisper\ggml-tiny.en.bin"
foreach ($asset in @(
        @{ Name = "Kokoro ONNX model"; Path = $kokoroModel },
        @{ Name = "Kokoro voices"; Path = $kokoroVoices },
        @{ Name = "Whisper ASR model"; Path = $whisperModel }
    )) {
    if (Test-File -Path $asset.Path) {
        $sizeMb = [math]::Round((Get-Item -LiteralPath $asset.Path).Length / 1MB, 1)
        Add-Check -Status "PASS" -Name $asset.Name -Detail "$($asset.Path) ($sizeMb MB)." -Repair "No action needed."
    } else {
        Add-Check -Status "FAIL" -Name $asset.Name -Detail "$($asset.Path) is missing." -Repair "Re-extract the full Iris release ZIP. Do not move files out of the models folder."
    }
}

$hermesSitePackages = Join-Path $root ".iris-runtime\hermes\.venv\Lib\site-packages"
foreach ($packageMetadata in @(
        @{ Name = "Hermes Agent pinned package"; Path = (Join-Path $hermesSitePackages "hermes_agent-0.18.0.dist-info\METADATA") },
        @{ Name = "Agent Client Protocol pinned package"; Path = (Join-Path $hermesSitePackages "agent_client_protocol-0.9.0.dist-info\METADATA") }
    )) {
    if (Test-File -Path $packageMetadata.Path) {
        Add-Check -Status "PASS" -Name $packageMetadata.Name -Detail "Found packaged metadata at $($packageMetadata.Path)." -Repair "No action needed."
    } else {
        Add-Check -Status "FAIL" -Name $packageMetadata.Name -Detail "$($packageMetadata.Path) is missing." -Repair "Re-extract the full Iris release; do not install an unpinned replacement package."
    }
}

$python313 = Find-Python313
if ($python313) {
    Add-Check -Status "PASS" -Name "Python executable" -Detail "Found exact Python 3.13 at $python313 for the Iris-owned Hermes and voice package layers." -Repair "No action needed."
} else {
    Add-Check -Status "FAIL" -Name "Python executable" -Detail "Exact Python 3.13 was not found." -Repair "Install Python 3.13 (WinGet package Python.Python.3.13), then rerun this preflight. Iris supplies its own pinned Hermes, image-provider, and voice package layers."
}

$voiceRuntime = Test-IrisVoiceRuntime `
    -PythonPath $python313 `
    -SitePackages (Join-Path $root ".iris-runtime\voice\Lib\site-packages") `
    -LockPath (Join-Path $root "profiles\iris_voice_python_3_13.lock.txt") `
    -RuntimeLockPath (Join-Path $root ".iris-runtime\voice\runtime-lock.txt") `
    -RuntimeManifestPath (Join-Path $root ".iris-runtime\runtime-manifest.json")
if ($voiceRuntime.Available) {
    Add-Check -Status "PASS" -Name "Iris-owned voice Python layer" -Detail $voiceRuntime.Detail -Repair "No action needed."
} else {
    Add-Check -Status "FAIL" -Name "Iris-owned voice Python layer" -Detail $voiceRuntime.Detail -Repair "Re-extract or upgrade the complete Iris release. Do not repair this managed layer with global pip."
}

$zipPath = Join-Path $root "release\dist\iris-windows.zip"
$shaPath = "$zipPath.sha256"
if ((Test-File -Path $zipPath) -and (Test-File -Path $shaPath)) {
    $expected = ((Get-Content -LiteralPath $shaPath -Raw).Trim() -split "\s+")[0]
    $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected.ToLowerInvariant() -eq $actual) {
        Add-Check -Status "PASS" -Name "Release ZIP integrity" -Detail "release\dist\iris-windows.zip matches its SHA256." -Repair "No action needed."
    } else {
        Add-Check -Status "FAIL" -Name "Release ZIP integrity" -Detail "Expected $expected but got $actual." -Repair "Rebuild the release ZIP or redownload both release files."
    }
} elseif (Test-File -Path (Join-Path $root "README_RELEASE.md")) {
    Add-Check -Status "PASS" -Name "Release ZIP integrity" -Detail "Running from an extracted release; source ZIP is not expected inside the folder." -Repair "Keep iris-windows.zip.sha256 next to the downloaded ZIP if you want to verify the original download."
} else {
    Add-Check -Status "WARN" -Name "Release ZIP integrity" -Detail "No release ZIP/SHA pair found under release\dist." -Repair "Run scripts\package_windows_release.ps1 from a developer checkout, or verify the downloaded ZIP before extracting it."
}

Test-LoopbackOnlyManifest

$failCount = @($results | Where-Object Status -eq "FAIL").Count
$warnCount = @($results | Where-Object Status -eq "WARN").Count
$passCount = @($results | Where-Object Status -eq "PASS").Count

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$generated = Get-Date -Format o
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Iris preflight report") | Out-Null
$lines.Add("Root: $root") | Out-Null
$lines.Add("Generated: $generated") | Out-Null
$lines.Add("Summary: PASS=$passCount WARN=$warnCount FAIL=$failCount") | Out-Null
$lines.Add("") | Out-Null
foreach ($result in $results) {
    $line = "[$($result.Status)] $($result.Name): $($result.Detail)"
    if (-not $Quiet) {
        Write-Host $line
    }
    $lines.Add($line) | Out-Null
    $lines.Add("  Next: $($result.Repair)") | Out-Null
}
$lines.Add("") | Out-Null
$lines.Add("This preflight is read-only. It does not install, download, pull models, change services, edit PATH, or modify cloud-sync storage.") | Out-Null
Set-Content -LiteralPath $reportPath -Value $lines -Encoding utf8

$jsonChecks = @($results | ForEach-Object {
    [ordered]@{
        Status = $_.Status
        Name = $_.Name
        Detail = $_.Detail
        Repair = $_.Repair
    }
})
$jsonPayload = [ordered]@{
    root = $root
    generated = $generated
    model_id = $modelId
    summary = [ordered]@{
        "pass" = $passCount
        "warn" = $warnCount
        "fail" = $failCount
    }
    checks = $jsonChecks
}
$jsonPayload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonReportPath -Encoding utf8

if (-not $Quiet) {
    Write-Host ""
    Write-Host "Report: $reportPath"
    Write-Host "JSON: $jsonReportPath"
    Write-Host "Summary: PASS=$passCount WARN=$warnCount FAIL=$failCount"
}
if ($failCount -gt 0) {
    exit 1
}
exit 0
