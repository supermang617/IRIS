param(
    [string]$JsonPath = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

if (-not ("Iris.Runtime.BoundedCaptureStream" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Iris.Runtime {
    public sealed class BoundedCaptureStream : Stream {
        private readonly byte[] buffer;
        private readonly object sync = new object();
        private int length;
        private long totalBytes;

        public BoundedCaptureStream(int capacity) {
            if (capacity < 1) throw new ArgumentOutOfRangeException("capacity");
            buffer = new byte[capacity];
        }
        public string Text {
            get {
                lock (sync) {
                    string value = Encoding.UTF8.GetString(buffer, 0, length);
                    return totalBytes > buffer.Length
                        ? value + Environment.NewLine + "[process output truncated by Iris]"
                        : value;
                }
            }
        }
        public override bool CanRead { get { return false; } }
        public override bool CanSeek { get { return false; } }
        public override bool CanWrite { get { return true; } }
        public override long Length { get { lock (sync) { return length; } } }
        public override long Position {
            get { return Length; }
            set { throw new NotSupportedException(); }
        }
        public override void Flush() { }
        public override Task FlushAsync(CancellationToken cancellationToken) {
            return Task.CompletedTask;
        }
        public override void Write(byte[] source, int offset, int count) {
            lock (sync) {
                totalBytes += count;
                int retained = Math.Min(count, buffer.Length - length);
                if (retained > 0) {
                    Buffer.BlockCopy(source, offset, buffer, length, retained);
                    length += retained;
                }
            }
        }
        public override Task WriteAsync(
            byte[] source,
            int offset,
            int count,
            CancellationToken cancellationToken
        ) {
            if (cancellationToken.IsCancellationRequested) {
                return Task.FromCanceled(cancellationToken);
            }
            Write(source, offset, count);
            return Task.CompletedTask;
        }
        public override int Read(byte[] target, int offset, int count) {
            throw new NotSupportedException();
        }
        public override long Seek(long offset, SeekOrigin origin) {
            throw new NotSupportedException();
        }
        public override void SetLength(long value) {
            throw new NotSupportedException();
        }
    }
}
'@
}

function Start-BoundedProcessCapture {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [int]$MaximumBytesPerStream = (128 * 1024)
    )

    $stdoutSink = New-Object Iris.Runtime.BoundedCaptureStream($MaximumBytesPerStream)
    $stderrSink = New-Object Iris.Runtime.BoundedCaptureStream($MaximumBytesPerStream)
    return [pscustomobject]@{
        Process = $Process
        StdoutSink = $stdoutSink
        StderrSink = $stderrSink
        StdoutTask = $Process.StandardOutput.BaseStream.CopyToAsync($stdoutSink)
        StderrTask = $Process.StandardError.BaseStream.CopyToAsync($stderrSink)
    }
}

function Complete-BoundedProcessCapture {
    param(
        [Parameter(Mandatory = $true)]$Capture,
        [int]$TimeoutMilliseconds = 5000
    )

    $tasks = [System.Threading.Tasks.Task[]]@($Capture.StdoutTask, $Capture.StderrTask)
    $completedInTime = $false
    try {
        $completedInTime = [System.Threading.Tasks.Task]::WaitAll($tasks, $TimeoutMilliseconds)
    } catch {
        $completedInTime = $false
    }
    if (-not $completedInTime) {
        $Capture.Process.StandardOutput.BaseStream.Dispose()
        $Capture.Process.StandardError.BaseStream.Dispose()
        try {
            [void][System.Threading.Tasks.Task]::WaitAll($tasks, 1000)
        } catch {
        }
    }
    $streamsCompleted = @(
        $tasks | Where-Object { -not $_.IsCompleted -or $_.IsFaulted -or $_.IsCanceled }
    ).Count -eq 0
    return [pscustomobject]@{
        Output = $Capture.StdoutSink.Text
        Error = $Capture.StderrSink.Text
        StreamsCompleted = $streamsCompleted
    }
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ((Split-Path -Leaf $root) -ieq "scripts") {
    $root = (Resolve-Path -LiteralPath (Join-Path $root "..")).Path
}
Set-Location -LiteralPath $root

$ollamaModelLockHelper = Join-Path $root "scripts\iris_ollama_model_lock.ps1"
if (-not (Test-Path -LiteralPath $ollamaModelLockHelper -PathType Leaf)) {
    throw "Missing Iris Ollama model-lock verifier: $ollamaModelLockHelper"
}
. $ollamaModelLockHelper
$ollamaModelLock = Get-IrisOllamaModelLock -Root $root
$modelId = [string]$ollamaModelLock.model_id
$ollamaVisionModelLock = Get-IrisOllamaModelLock -Root $root -Role Vision
$visionModelId = [string]$ollamaVisionModelLock.model_id
$minimumRamGb = 16
$recommendedFreeDiskGb = 16
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

    try {
        [void]$process.Start()
        $capture = Start-BoundedProcessCapture -Process $process
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            Stop-ProcessTree -ProcessId $process.Id
            [void]$process.WaitForExit(5000)
        } else {
            $process.WaitForExit()
        }
        $captured = Complete-BoundedProcessCapture -Capture $capture
        $output = $captured.Output
        $errorOutput = $captured.Error
        if (-not $captured.StreamsCompleted) {
            $errorOutput = @($errorOutput, "process output streams did not close within 5 seconds") -join "`n"
        }
        if ($timedOut) {
            return [pscustomobject]@{
                ExitCode = 124
                Output = $output
                Error = @($errorOutput, "timed out after $TimeoutSeconds seconds") -join "`n"
            }
        }
        return [pscustomobject]@{
            ExitCode = if ($captured.StreamsCompleted) { $process.ExitCode } else { 125 }
            Output = $output
            Error = $errorOutput
        }
    } finally {
        $process.Dispose()
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
        @{ Root = $env:ProgramFiles; Relative = "Google\Chrome\Application\chrome.exe" },
        @{ Root = ${env:ProgramFiles(x86)}; Relative = "Google\Chrome\Application\chrome.exe" },
        @{ Root = $env:LOCALAPPDATA; Relative = "Google\Chrome\Application\chrome.exe" },
        @{ Root = $root; Relative = ".iris-runtime\browser\browsers\chrome-149.0.7827.115\chrome.exe" }
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
        Detail = "Google Chrome was not found in the supported Windows install locations."
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

function Test-ConfiguredModelIdentity {
    try {
        $identity = Assert-IrisOllamaModelIdentity -Root $root -TimeoutSeconds 15 -Role Primary
        Add-Check -Status "PASS" -Name "Configured Ollama model identity" -Detail "$($identity.ModelId) matches locked digest $($identity.ManifestDigest), family $($identity.Family), quantization $($identity.QuantizationLevel), and required capabilities." -Repair "No action needed."
        $visionIdentity = Assert-IrisOllamaModelIdentity -Root $root -TimeoutSeconds 15 -Role Vision
        Add-Check -Status "PASS" -Name "Configured Ollama vision model identity" -Detail "$($visionIdentity.ModelId) matches locked digest $($visionIdentity.ManifestDigest), family $($visionIdentity.Family), quantization $($visionIdentity.QuantizationLevel), and release-verified general vision policy." -Repair "No action needed."
        Add-Check -Status "PASS" -Name "General vision policy" -Detail "Camera, image, and broad screen inference use Iris's exact release-verified local visual model; text, tools, and Hermes remain on the primary companion model." -Repair "No action needed."
    } catch {
        Add-Check -Status "FAIL" -Name "Configured Ollama model identity" -Detail $_.Exception.Message -Repair "Run `ollama pull $modelId` and `ollama pull $visionModelId` once to repair missing or corrupt local models, verify Ollama is using the intended model store, then rerun this preflight. Iris will not infer with mismatched model metadata."
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
    Add-Check -Status "FAIL" -Name "System browser executable" -Detail $systemBrowser.Detail -Repair "Install Google Chrome (WinGet package Google.Chrome), or set IRIS_BROWSER_EXECUTABLE_PATH to an absolute compatible Chrome/Chromium executable path, then restart Iris."
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
            if ($tags.Contains($modelId) -and $tags.Contains($visionModelId)) {
                Add-Check -Status "PASS" -Name "Configured Ollama model" -Detail "$modelId and $visionModelId are available locally." -Repair "No action needed."
                Test-ConfiguredModelIdentity
            } else {
                Add-Check -Status "FAIL" -Name "Configured Ollama model" -Detail "One or both required models are not listed by the current Ollama service: $modelId, $visionModelId." -Repair "Install or point Ollama at the existing local model store for both exact models, then rerun this preflight. This script will not pull models automatically."
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
    vision_model_id = $visionModelId
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
