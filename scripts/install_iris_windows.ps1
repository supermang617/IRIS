param(
    [string]$InstallRoot = "",
    [string]$SourceZip = "",
    [string]$Sha256Path = "",
    [string]$StartMenuDir = "",
    [string]$DesktopDir = "",
    [switch]$RunSetup,
    [switch]$NonInteractive,
    [switch]$SetupNonInteractive,
    [switch]$SkipShortcuts
)

$ErrorActionPreference = "Stop"

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
    ) | Where-Object { $_ } | ForEach-Object { [System.IO.Path]::GetFullPath($_) }
    foreach ($allowed in $allowedRoots) {
        if ($resolved.StartsWith($allowed, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $resolved.TrimEnd("\")
        }
    }
    throw "InstallRoot must be inside the current user's profile or temp folder: $resolved"
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
        "manifest.json",
        "bin\iris-runtime.exe",
        "bin\iris-tauri.exe",
        "models\kokoro\kokoro-v1.0.onnx",
        "models\kokoro\voices-v1.0.bin",
        "models\whisper\ggml-tiny.en.bin"
        ".iris-runtime\hermes\.venv\Scripts\python.exe"
        ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
        ".iris-runtime\browser\browsers\chrome-149.0.7827.115\chrome.exe"
        ".iris-runtime\runtime-manifest.json"
    )) {
        Require-File -Path (Join-Path $Root $relative)
    }
}

function Copy-ReleaseFiles {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )
    New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
    foreach ($relative in @(
        "assets",
        "bin",
        "capabilities",
        "docs",
        "models",
        "plugins",
        "profiles",
        "tools"
        ".iris-runtime"
    )) {
        $source = Join-Path $SourceRoot $relative
        if (Test-Path -LiteralPath $source -PathType Container) {
            $destination = Join-Path $DestinationRoot $relative
            Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
        }
    }
    foreach ($relative in @(
        "Check Iris Preflight.bat",
        "Iris Preflight.ps1",
        "Iris Document OCR.ps1",
        "Iris Setup Wizard.bat",
        "Iris Setup Wizard.ps1",
        "LICENSE",
        "NOTICE.md",
        "README_RELEASE.md",
        "SECURITY.md",
        "Start Iris.bat",
        "Start Iris.ps1",
        "known-limitations.md",
        "manifest.json"
    )) {
        $source = Join-Path $SourceRoot $relative
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $DestinationRoot $relative) -Force
        }
    }
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
    "Iris Setup Wizard.bat",
    "Iris Setup Wizard.ps1",
    "LICENSE",
    "NOTICE.md",
    "README_RELEASE.md",
    "SECURITY.md",
    "Start Iris.bat",
    "Start Iris.ps1",
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

if (-not $InstallRoot) {
    $InstallRoot = Resolve-DefaultInstallRoot
}
$installRootResolved = Assert-ManagedInstallPath -Path $InstallRoot

$temporaryExtract = $null
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
    $sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
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

    Copy-ReleaseFiles -SourceRoot $sourceRoot -DestinationRoot $installRootResolved

    if (-not $StartMenuDir) {
        $StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Iris"
    }
    if (-not $DesktopDir) {
        $DesktopDir = [Environment]::GetFolderPath("Desktop")
    }
    $StartMenuDir = [System.IO.Path]::GetFullPath($StartMenuDir)
    $DesktopDir = [System.IO.Path]::GetFullPath($DesktopDir)

    Write-Uninstaller -TargetRoot $installRootResolved -MenuDir $StartMenuDir -DeskDir $DesktopDir

    if (-not $SkipShortcuts) {
        $powershell = (Get-Command powershell.exe).Source
        New-Shortcut -ShortcutPath (Join-Path $StartMenuDir "Iris.lnk") -TargetPath (Join-Path $installRootResolved "Start Iris.bat") -WorkingDirectory $installRootResolved
        New-Shortcut -ShortcutPath (Join-Path $StartMenuDir "Iris Setup Wizard.lnk") -TargetPath $powershell -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installRootResolved\Iris Setup Wizard.ps1`"" -WorkingDirectory $installRootResolved
        New-Shortcut -ShortcutPath (Join-Path $StartMenuDir "Uninstall Iris.lnk") -TargetPath $powershell -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$installRootResolved\Uninstall Iris.ps1`"" -WorkingDirectory $installRootResolved
        New-Shortcut -ShortcutPath (Join-Path $DesktopDir "Iris.lnk") -TargetPath (Join-Path $installRootResolved "Start Iris.bat") -WorkingDirectory $installRootResolved
    }

    $manifest = [ordered]@{
        installed_at = Get-Date -Format o
        install_root = $installRootResolved
        source_root = $sourceRoot
        source_zip = $SourceZip
        start_menu_dir = $StartMenuDir
        desktop_dir = $DesktopDir
        local_only_runtime = $true
        installer_dependency = "none"
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $installRootResolved "install-manifest.json") -Encoding utf8

    & (Join-Path $installRootResolved "Start Iris.ps1") --self-check
    if ($LASTEXITCODE -ne 0) {
        throw "Installed Iris self-check failed with exit code $LASTEXITCODE"
    }

    if ($RunSetup) {
        if ($NonInteractive.IsPresent -or $SetupNonInteractive.IsPresent) {
            & (Join-Path $installRootResolved "Iris Setup Wizard.ps1") -NonInteractive
        } else {
            & (Join-Path $installRootResolved "Iris Setup Wizard.ps1")
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Installed Iris setup wizard failed with exit code $LASTEXITCODE"
        }
    }

    Write-Host "Iris installed successfully."
    Write-Host "Install root: $installRootResolved"
    if (-not $SkipShortcuts) {
        Write-Host "Start Menu shortcuts: $StartMenuDir"
        Write-Host "Desktop shortcut: $(Join-Path $DesktopDir 'Iris.lnk')"
    }
    exit 0
} finally {
    if ($temporaryExtract) {
        Remove-Item -LiteralPath $temporaryExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}
