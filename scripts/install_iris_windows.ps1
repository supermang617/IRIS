param(
    [string]$InstallRoot = "",
    [string]$SourceZip = "",
    [string]$Sha256Path = "",
    [string]$StartMenuDir = "",
    [string]$DesktopDir = "",
    [switch]$RunSetup,
    [switch]$NonInteractive,
    [switch]$SetupNonInteractive,
    [switch]$LaunchAfterInstall,
    [switch]$SkipShortcuts,
    [switch]$SkipSelfCheck,
    [int]$SelfCheckTimeoutSeconds = 240
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
        [int]$MaximumBytesPerStream = (512 * 1024)
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

if ($PSVersionTable.PSEdition -eq "Desktop") {
    # A Windows PowerShell child started from PowerShell 7 can inherit PS7-only
    # module roots ahead of the inbox Windows modules, which breaks autoloading.
    # Keep this installer on the Windows PowerShell module set it was built for.
    $windowsModuleRoots = @(
        (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "WindowsPowerShell\Modules"),
        (Join-Path $env:ProgramFiles "WindowsPowerShell\Modules"),
        (Join-Path $PSHOME "Modules")
    ) | Select-Object -Unique
    $env:PSModulePath = $windowsModuleRoots -join [System.IO.Path]::PathSeparator
    Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
    Import-Module Microsoft.PowerShell.Archive -ErrorAction Stop
}

function Resolve-DefaultInstallRoot {
    if ($env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA "Programs\Iris")
    }
    return (Join-Path $env:USERPROFILE "Iris")
}

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

function Assert-ManagedInstallPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    $allowedRoots = @(
        $env:LOCALAPPDATA,
        $env:APPDATA,
        $env:USERPROFILE,
        ([System.IO.Path]::GetTempPath())
    ) |
        Where-Object { $_ } |
        ForEach-Object { [System.IO.Path]::GetFullPath($_).TrimEnd("\") } |
        Select-Object -Unique
    foreach ($allowed in $allowedRoots) {
        if ($resolved -ieq $allowed) {
            throw "InstallRoot must be a dedicated child directory inside the current user's profile or temp folder: $resolved"
        }
    }
    $containingRoot = $allowedRoots |
        Where-Object { $resolved.StartsWith($_ + "\", [System.StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object Length -Descending |
        Select-Object -First 1
    if ($containingRoot) {
        # Lexical containment alone is not enough on Windows: an existing
        # junction or symbolic-link component can redirect recursive install,
        # rollback, or cleanup operations outside the per-user boundary.
        # Refuse such paths before creating transaction data or touching an
        # existing installation.
        $relative = $resolved.Substring($containingRoot.Length).TrimStart("\")
        $components = @($containingRoot) + @($relative -split '\\' | Where-Object { $_ })
        $current = $null
        foreach ($component in $components) {
            $current = if ($null -eq $current) { $component } else { Join-Path $current $component }
            $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
            if ($null -ne $item -and
                (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
                throw "InstallRoot must be a dedicated child directory without junction or symbolic-link components inside the current user's profile or temp folder: $resolved (reparse point: $current)"
            }
        }
        return $resolved.TrimEnd("\")
    }
    throw "InstallRoot must be a dedicated child directory inside the current user's profile or temp folder: $resolved"
}

function Read-ExpectedHash {
    param([Parameter(Mandatory = $true)][string]$Path)
    Require-File -Path $Path
    return ((Get-Content -LiteralPath $Path -Raw).Trim() -split "\s+")[0].ToLowerInvariant()
}

function Test-ReleaseRoot {
    param([Parameter(Mandatory = $true)][string]$Root)
    foreach ($relative in @(
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
        "models\whisper\ggml-tiny.en.bin"
        ".iris-runtime\hermes\.venv\Lib\site-packages\hermes_agent-0.18.0.dist-info\METADATA"
        ".iris-runtime\voice\Lib\site-packages\kokoro_onnx-0.5.0.dist-info\METADATA"
        ".iris-runtime\voice\Lib\site-packages\soundfile-0.14.0.dist-info\METADATA"
        ".iris-runtime\voice\Lib\site-packages\numpy-2.5.1.dist-info\METADATA"
        ".iris-runtime\voice\Lib\site-packages\onnxruntime-1.28.0.dist-info\METADATA"
        ".iris-runtime\voice\runtime-lock.txt"
        "profiles\iris_voice_python_3_13.lock.txt"
        ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
        ".iris-runtime\runtime-manifest.json"
    )) {
        Require-File -Path (Join-Path $Root $relative)
    }
}

function Remove-ReleaseTransactionData {
    param([Parameter(Mandatory = $true)]$Transaction)

    $cleanupFailures = New-Object System.Collections.Generic.List[string]
    foreach ($transactionPath in @($Transaction.StagingRoot, $Transaction.BackupRoot)) {
        if (-not (Test-Path -LiteralPath $transactionPath)) {
            continue
        }
        try {
            Remove-Item -LiteralPath $transactionPath -Recurse -Force -ErrorAction Stop
        } catch {
            $cleanupFailures.Add("$transactionPath`: $($_.Exception.Message)") | Out-Null
        }
    }
    if ($cleanupFailures.Count -gt 0) {
        throw "Iris transaction cleanup was incomplete ($($cleanupFailures -join '; ')). Remove these transaction paths to recover disk space."
    }
}

function Register-TransactionalFile {
    param(
        [Parameter(Mandatory = $true)]$Transaction,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $resolved = [System.IO.Path]::GetFullPath($Path)
    foreach ($entry in $Transaction.ExternalFiles) {
        if ($entry.Path -ieq $resolved) {
            return
        }
    }
    if (Test-Path -LiteralPath $resolved -PathType Container) {
        throw "Installer transaction expected a file but found a directory: $resolved"
    }

    $backupPath = Join-Path $Transaction.BackupRoot ("external-files\{0}" -f $Transaction.ExternalFiles.Count)
    $existed = Test-Path -LiteralPath $resolved -PathType Leaf
    if ($existed) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
        Copy-Item -LiteralPath $resolved -Destination $backupPath -Force
    }
    $Transaction.ExternalFiles.Add([pscustomobject]@{
        Path = $resolved
        BackupPath = $backupPath
        Existed = $existed
    }) | Out-Null
}

function Undo-ReleaseFilesTransaction {
    param([Parameter(Mandatory = $true)]$Transaction)

    if ($Transaction.Committed) {
        throw "Cannot roll back an Iris release transaction after it has been committed."
    }
    $rollbackFailures = New-Object System.Collections.Generic.List[string]

    for ($index = $Transaction.ExternalFiles.Count - 1; $index -ge 0; $index--) {
        $entry = $Transaction.ExternalFiles[$index]
        try {
            if (Test-Path -LiteralPath $entry.Path) {
                Remove-Item -LiteralPath $entry.Path -Recurse -Force -ErrorAction Stop
            }
            if ($entry.Existed) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $entry.Path) | Out-Null
                Move-Item -LiteralPath $entry.BackupPath -Destination $entry.Path -Force
            }
        } catch {
            $rollbackFailures.Add("restore $($entry.Path)`: $($_.Exception.Message)") | Out-Null
        }
    }

    for ($index = $Transaction.Installed.Count - 1; $index -ge 0; $index--) {
        $destination = Join-Path $Transaction.DestinationRoot $Transaction.Installed[$index]
        try {
            if (Test-Path -LiteralPath $destination) {
                Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction Stop
            }
        } catch {
            $rollbackFailures.Add("remove $destination`: $($_.Exception.Message)") | Out-Null
        }
    }
    for ($index = $Transaction.BackedUp.Count - 1; $index -ge 0; $index--) {
        $relative = $Transaction.BackedUp[$index]
        $destination = Join-Path $Transaction.DestinationRoot $relative
        $backup = Join-Path $Transaction.BackupRoot $relative
        try {
            if (Test-Path -LiteralPath $destination) {
                Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction Stop
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
            Move-Item -LiteralPath $backup -Destination $destination -Force
        } catch {
            $rollbackFailures.Add("restore $destination`: $($_.Exception.Message)") | Out-Null
        }
    }

    if ($rollbackFailures.Count -gt 0) {
        throw "Iris install rollback was incomplete ($($rollbackFailures -join '; ')). Recoverable backup remains at $($Transaction.BackupRoot)."
    }
    Remove-ReleaseTransactionData -Transaction $Transaction
}

function Complete-ReleaseFilesTransaction {
    param([Parameter(Mandatory = $true)]$Transaction)

    # Once every mandatory install step has passed, the new payload is the
    # durable version. Never attempt to restore a partially deleted backup if
    # the subsequent cleanup itself encounters a filesystem error.
    $Transaction.Committed = $true
    Remove-ReleaseTransactionData -Transaction $Transaction
}

function Copy-ReleaseFiles {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )
    $managedDirectories = @(
        "assets",
        "bin",
        "capabilities",
        "docs",
        "models",
        "plugins",
        "profiles",
        "tools"
        ".iris-runtime"
    )
    $managedFiles = @(
        "Check Iris Preflight.bat",
        "Iris Preflight.ps1",
        "Iris Document OCR.ps1",
        "Initialize Iris Data Root.ps1",
        "Iris Setup Wizard.bat",
        "Iris Setup Wizard.ps1",
        "LICENSE",
        "NOTICE.md",
        "README_RELEASE.md",
        "SECURITY.md",
        "Start Iris.bat",
        "Start Iris.ps1",
        "Update Iris.bat",
        "Update Iris.ps1",
        "known-limitations.md",
        "manifest.json"
    )

    $destinationParent = Split-Path -Parent $DestinationRoot
    if (-not $destinationParent) {
        throw "DestinationRoot must include a parent directory: $DestinationRoot"
    }
    New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
    $transactionId = [System.Guid]::NewGuid().ToString("N")
    $destinationName = Split-Path -Leaf $DestinationRoot
    $transaction = [pscustomobject]@{
        DestinationRoot = $DestinationRoot
        StagingRoot = Join-Path $destinationParent "$destinationName.iris-staging-$transactionId"
        BackupRoot = Join-Path $destinationParent "$destinationName.iris-backup-$transactionId"
        BackedUp = New-Object System.Collections.Generic.List[string]
        Installed = New-Object System.Collections.Generic.List[string]
        ExternalFiles = New-Object System.Collections.Generic.List[object]
        Committed = $false
    }

    try {
        New-Item -ItemType Directory -Path $transaction.StagingRoot, $transaction.BackupRoot | Out-Null
        foreach ($relative in $managedDirectories) {
            $source = Join-Path $SourceRoot $relative
            if (-not (Test-Path -LiteralPath $source -PathType Container)) {
                continue
            }
            $staged = Join-Path $transaction.StagingRoot $relative
            New-Item -ItemType Directory -Force -Path $staged | Out-Null
            foreach ($child in @(Get-ChildItem -LiteralPath $source -Force)) {
                Copy-Item -LiteralPath $child.FullName -Destination $staged -Recurse -Force
            }
        }
        foreach ($relative in $managedFiles) {
            $source = Join-Path $SourceRoot $relative
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                continue
            }
            $staged = Join-Path $transaction.StagingRoot $relative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $staged) | Out-Null
            Copy-Item -LiteralPath $source -Destination $staged -Force
        }

        # Finish every potentially fallible payload copy before replacing any
        # part of an existing installation.
        Test-ReleaseRoot -Root $transaction.StagingRoot
        New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null

        foreach ($relative in @($managedDirectories) + @($managedFiles)) {
            $staged = Join-Path $transaction.StagingRoot $relative
            if (-not (Test-Path -LiteralPath $staged)) {
                continue
            }
            $destination = Join-Path $DestinationRoot $relative
            $backup = Join-Path $transaction.BackupRoot $relative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination), (Split-Path -Parent $backup) | Out-Null
            if (Test-Path -LiteralPath $destination) {
                Move-Item -LiteralPath $destination -Destination $backup
                $transaction.BackedUp.Add($relative) | Out-Null
            }
            Move-Item -LiteralPath $staged -Destination $destination
            $transaction.Installed.Add($relative) | Out-Null
        }
    } catch {
        $replacementFailure = $_
        try {
            Undo-ReleaseFilesTransaction -Transaction $transaction
        } catch {
            throw "Iris managed-file replacement failed and rollback was incomplete. Original error: $($replacementFailure.Exception.Message) Rollback error: $($_.Exception.Message)"
        }
        throw $replacementFailure
    }

    return $transaction
}

function New-Shortcut {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [string]$Arguments = ""
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ShortcutPath) | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.IconLocation = Join-Path $WorkingDirectory "bin\iris-tauri.exe"
    $shortcut.Save()
}

function Write-Uninstaller {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$MenuDir,
        [Parameter(Mandatory = $true)][string]$DeskDir
    )
    $script = @"
param([switch]`$Quiet)
`$ErrorActionPreference = "Stop"
`$root = Split-Path -Parent `$MyInvocation.MyCommand.Path
foreach (`$shortcut in @(
    (Join-Path "$MenuDir" "Iris.lnk"),
    (Join-Path "$MenuDir" "Iris Setup Wizard.lnk"),
    (Join-Path "$MenuDir" "Update Iris.lnk"),
    (Join-Path "$MenuDir" "Uninstall Iris.lnk"),
    (Join-Path "$DeskDir" "Iris.lnk")
)) {
    Remove-Item -LiteralPath `$shortcut -Force -ErrorAction SilentlyContinue
}
foreach (`$relative in @("assets","bin","capabilities","docs","models","plugins","profiles","tools",".iris-runtime")) {
    Remove-Item -LiteralPath (Join-Path `$root `$relative) -Recurse -Force -ErrorAction SilentlyContinue
}
foreach (`$relative in @(
    "Check Iris Preflight.bat",
    "Iris Preflight.ps1",
    "Iris Document OCR.ps1",
    "Initialize Iris Data Root.ps1",
    "Iris Setup Wizard.bat",
    "Iris Setup Wizard.ps1",
    "LICENSE",
    "NOTICE.md",
    "README_RELEASE.md",
    "SECURITY.md",
    "Start Iris.bat",
    "Start Iris.ps1",
    "Update Iris.bat",
    "Update Iris.ps1",
    "known-limitations.md",
    "manifest.json",
    "install-manifest.json"
)) {
    Remove-Item -LiteralPath (Join-Path `$root `$relative) -Force -ErrorAction SilentlyContinue
}
if (-not `$Quiet) {
    Write-Host "Iris shortcuts and managed files were removed from `$root."
    Write-Host "Diagnostics or user-created files may remain and can be deleted manually."
}
"@
    Set-Content -LiteralPath (Join-Path $TargetRoot "Uninstall Iris.ps1") -Value $script -Encoding utf8
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-ProcessTree -ProcessId ([int]$child.ProcessId)
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Invoke-InstalledSelfCheck {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    if ($TimeoutSeconds -lt 30) {
        throw "SelfCheckTimeoutSeconds must be at least 30 seconds."
    }

    $launcher = Join-Path $InstallRoot "Start Iris.ps1"
    $powershell = (Get-Command powershell.exe).Source
    $selfCheckRoot = if ($env:IRIS_DATA_ROOT) { [System.IO.Path]::GetFullPath($env:IRIS_DATA_ROOT) } else { $InstallRoot }
    $outputPath = Join-Path $selfCheckRoot "diagnostics\installer-self-check.log"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath) | Out-Null

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powershell
    $startInfo.WorkingDirectory = $InstallRoot
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`" -SelfCheck"
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
            # Complete asynchronous stream delivery after the process handle is signaled.
            $process.WaitForExit()
        }
        $captured = Complete-BoundedProcessCapture -Capture $capture
        $output = $captured.Output
        $errorOutput = $captured.Error
        if (-not $captured.StreamsCompleted) {
            $errorOutput = @($errorOutput, "process output streams did not close within 5 seconds") -join "`n"
        }
        Set-Content -LiteralPath $outputPath -Value @($output, $errorOutput) -Encoding utf8
        if ($timedOut) {
            throw "Installed Iris self-check timed out after $TimeoutSeconds seconds. Log: $outputPath"
        }
        if (-not $captured.StreamsCompleted) {
            throw "Installed Iris self-check output streams did not close. Log: $outputPath"
        }
        if ($process.ExitCode -ne 0) {
            throw "Installed Iris self-check failed with exit code $($process.ExitCode). Log: $outputPath"
        }
    } finally {
        $process.Dispose()
    }
}

if (-not $InstallRoot) {
    $InstallRoot = Resolve-DefaultInstallRoot
}
$installRootResolved = Assert-ManagedInstallPath -Path $InstallRoot

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $SourceZip) {
    $siblingSourceZip = Join-Path $scriptRoot "iris-windows.zip"
    $siblingSha256Path = Join-Path $scriptRoot "iris-windows.zip.sha256"
    if ((Test-Path -LiteralPath $siblingSourceZip -PathType Leaf) -and (Test-Path -LiteralPath $siblingSha256Path -PathType Leaf)) {
        $SourceZip = $siblingSourceZip
        if (-not $Sha256Path) {
            $Sha256Path = $siblingSha256Path
        }
    }
}
if (-not $SourceZip -and (Split-Path -Leaf $scriptRoot) -ieq "scripts") {
    $sourceDistRoot = Join-Path $scriptRoot "..\release\dist"
    $distSourceZip = Join-Path $sourceDistRoot "iris-windows.zip"
    $distSha256Path = Join-Path $sourceDistRoot "iris-windows.zip.sha256"
    if ((Test-Path -LiteralPath $distSourceZip -PathType Leaf) -and
        (Test-Path -LiteralPath $distSha256Path -PathType Leaf)) {
        $SourceZip = $distSourceZip
        if (-not $Sha256Path) {
            $Sha256Path = $distSha256Path
        }
    }
}

$temporaryExtract = $null
$releaseTransaction = $null
if ($SourceZip) {
    Require-File -Path $SourceZip
    if (-not $Sha256Path) {
        $Sha256Path = "$SourceZip.sha256"
    }
    $expectedHash = Read-ExpectedHash -Path $Sha256Path
    $actualHash = (Get-FileHash -LiteralPath $SourceZip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "SHA256 mismatch for $SourceZip. Expected $expectedHash but got $actualHash."
    }
    $temporaryExtract = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-install-source-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $temporaryExtract | Out-Null
    Expand-Archive -LiteralPath $SourceZip -DestinationPath $temporaryExtract -Force
    $sourceRoot = $temporaryExtract
} else {
    $sourceRoot = $scriptRoot
    if ((Split-Path -Leaf $sourceRoot) -ieq "scripts") {
        $sourceRoot = (Resolve-Path -LiteralPath (Join-Path $sourceRoot "..\release\staging\iris-windows")).Path
    }
}

try {
    $sourceRoot = (Resolve-Path -LiteralPath $sourceRoot).Path
    Test-ReleaseRoot -Root $sourceRoot

    Write-Host "Installing Iris"
    Write-Host "Source: $sourceRoot"
    Write-Host "Target: $installRootResolved"

    $releaseTransaction = Copy-ReleaseFiles -SourceRoot $sourceRoot -DestinationRoot $installRootResolved
    $dataRootInitializer = Join-Path $installRootResolved "Initialize Iris Data Root.ps1"
    $defaultInstallRootResolved = [System.IO.Path]::GetFullPath((Resolve-DefaultInstallRoot)).TrimEnd("\")
    if ($installRootResolved -ieq $defaultInstallRootResolved) {
        $dataRoot = (& $dataRootInitializer -InstallRoot $installRootResolved -PersistForCurrentUser -PassThru | Select-Object -Last 1)
    } else {
        $dataRoot = (& $dataRootInitializer -InstallRoot $installRootResolved -PassThru | Select-Object -Last 1)
    }
    if (-not $dataRoot) {
        throw "Iris per-user data root initialization did not return a path."
    }
    if (-not $StartMenuDir) {
        $StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Iris"
    }
    if (-not $DesktopDir) {
        $DesktopDir = [Environment]::GetFolderPath("Desktop")
    }
    $StartMenuDir = [System.IO.Path]::GetFullPath($StartMenuDir)
    $DesktopDir = [System.IO.Path]::GetFullPath($DesktopDir)

    Register-TransactionalFile -Transaction $releaseTransaction -Path (Join-Path $installRootResolved "Uninstall Iris.ps1")
    Write-Uninstaller -TargetRoot $installRootResolved -MenuDir $StartMenuDir -DeskDir $DesktopDir

    if (-not $SkipShortcuts) {
        $powershell = (Get-Command powershell.exe).Source
        Register-TransactionalFile -Transaction $releaseTransaction -Path (Join-Path $StartMenuDir "Iris.lnk")
        New-Shortcut -ShortcutPath (Join-Path $StartMenuDir "Iris.lnk") -TargetPath (Join-Path $installRootResolved "bin\iris-tauri.exe") -WorkingDirectory $installRootResolved
        Register-TransactionalFile -Transaction $releaseTransaction -Path (Join-Path $StartMenuDir "Iris Setup Wizard.lnk")
        New-Shortcut -ShortcutPath (Join-Path $StartMenuDir "Iris Setup Wizard.lnk") -TargetPath $powershell -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installRootResolved\Iris Setup Wizard.ps1`"" -WorkingDirectory $installRootResolved
        Register-TransactionalFile -Transaction $releaseTransaction -Path (Join-Path $StartMenuDir "Update Iris.lnk")
        New-Shortcut -ShortcutPath (Join-Path $StartMenuDir "Update Iris.lnk") -TargetPath $powershell -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installRootResolved\Update Iris.ps1`"" -WorkingDirectory $installRootResolved
        Register-TransactionalFile -Transaction $releaseTransaction -Path (Join-Path $StartMenuDir "Uninstall Iris.lnk")
        New-Shortcut -ShortcutPath (Join-Path $StartMenuDir "Uninstall Iris.lnk") -TargetPath $powershell -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installRootResolved\Uninstall Iris.ps1`"" -WorkingDirectory $installRootResolved
        Register-TransactionalFile -Transaction $releaseTransaction -Path (Join-Path $DesktopDir "Iris.lnk")
        New-Shortcut -ShortcutPath (Join-Path $DesktopDir "Iris.lnk") -TargetPath (Join-Path $installRootResolved "bin\iris-tauri.exe") -WorkingDirectory $installRootResolved
    }

    $recordedSourceRoot = if ($temporaryExtract) { $null } else { $sourceRoot }
    $recordedSourceZip = if ($SourceZip) { [System.IO.Path]::GetFullPath($SourceZip) } else { $null }
    $manifest = [ordered]@{
        installed_at = Get-Date -Format o
        install_root = $installRootResolved
        source_root = $recordedSourceRoot
        source_zip = $recordedSourceZip
        start_menu_dir = $StartMenuDir
        desktop_dir = $DesktopDir
        data_root = $dataRoot
        local_only_runtime = $true
        installer_dependency = "none"
    }
    $installManifestPath = Join-Path $installRootResolved "install-manifest.json"
    Register-TransactionalFile -Transaction $releaseTransaction -Path $installManifestPath
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $installManifestPath -Encoding utf8

    if ($RunSetup) {
        if ($NonInteractive.IsPresent -or $SetupNonInteractive.IsPresent) {
            $previousFastPreflight = $env:IRIS_PREFLIGHT_FAST_LOCAL_ONLY
            $env:IRIS_PREFLIGHT_FAST_LOCAL_ONLY = "1"
            try {
                & (Join-Path $installRootResolved "Iris Setup Wizard.ps1") -NonInteractive
            } finally {
                if ($null -eq $previousFastPreflight) {
                    Remove-Item Env:\IRIS_PREFLIGHT_FAST_LOCAL_ONLY -ErrorAction SilentlyContinue
                } else {
                    $env:IRIS_PREFLIGHT_FAST_LOCAL_ONLY = $previousFastPreflight
                }
            }
        } else {
            & (Join-Path $installRootResolved "Iris Setup Wizard.ps1")
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Installed Iris setup wizard failed with exit code $LASTEXITCODE"
        }
    }

    if (-not $SkipSelfCheck) {
        Invoke-InstalledSelfCheck -InstallRoot $installRootResolved -TimeoutSeconds $SelfCheckTimeoutSeconds
    }

    # Retain the previous managed payload and generated install files until
    # setup and the final installed self-check have both passed.
    Complete-ReleaseFilesTransaction -Transaction $releaseTransaction
    $releaseTransaction = $null

    Write-Host "Iris installed successfully."
    Write-Host "Install root: $installRootResolved"
    if (-not $SkipShortcuts) {
        Write-Host "Start Menu shortcuts: $StartMenuDir"
        Write-Host "Desktop shortcut: $(Join-Path $DesktopDir 'Iris.lnk')"
    }
    if ($LaunchAfterInstall) {
        Start-Process -FilePath (Join-Path $installRootResolved "bin\iris-tauri.exe") -WorkingDirectory $installRootResolved
    }
    exit 0
} catch {
    $installFailure = $_
    if ($null -ne $releaseTransaction -and -not $releaseTransaction.Committed) {
        try {
            Undo-ReleaseFilesTransaction -Transaction $releaseTransaction
            $releaseTransaction = $null
        } catch {
            throw "Iris installation failed and the previous installation could not be restored completely. Original error: $($installFailure.Exception.Message) Rollback error: $($_.Exception.Message)"
        }
    }
    throw $installFailure
} finally {
    if ($temporaryExtract) {
        Remove-Item -LiteralPath $temporaryExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}
