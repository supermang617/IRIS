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
$reportDir = Join-Path $root "diagnostics"
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

function Test-PythonPackage {
    param([Parameter(Mandatory = $true)][string]$Package)
    $python = Test-CommandAvailable -Name "python"
    if (-not $python) {
        return [pscustomobject]@{ Python = $null; Available = $false; Detail = "python was not found on PATH" }
    }
    $code = "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('$Package') else 1)"
    & python -c $code *> $null
    return [pscustomobject]@{
        Python = $python
        Available = ($LASTEXITCODE -eq 0)
        Detail = if ($LASTEXITCODE -eq 0) { "$Package is importable" } else { "$Package is not importable" }
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

$kokoroOnnx = Test-PythonPackage -Package "kokoro_onnx"
$soundfile = Test-PythonPackage -Package "soundfile"
if ($kokoroOnnx.Python) {
    Add-Check -Status "PASS" -Name "Python executable" -Detail "Found python at $($kokoroOnnx.Python)." -Repair "No action needed."
} else {
    Add-Check -Status "WARN" -Name "Python executable" -Detail $kokoroOnnx.Detail -Repair "Install Python if you want Kokoro speech output. Text and vision can still work without TTS."
}
foreach ($packageCheck in @(
        @{ Name = "Python package kokoro-onnx"; Result = $kokoroOnnx },
        @{ Name = "Python package soundfile"; Result = $soundfile }
    )) {
    if ($packageCheck.Result.Available) {
        Add-Check -Status "PASS" -Name $packageCheck.Name -Detail $packageCheck.Result.Detail -Repair "No action needed."
    } else {
        Add-Check -Status "WARN" -Name $packageCheck.Name -Detail $packageCheck.Result.Detail -Repair "Install this Python package if you want Kokoro speech output. This preflight will not install packages automatically."
    }
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
