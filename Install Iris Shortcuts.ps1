$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcher = Join-Path $repoRoot "Start Iris.vbs"
$icon = Join-Path $repoRoot "src-tauri\icons\icon.ico"

if (-not (Test-Path -LiteralPath $launcher)) {
    throw "Missing Iris launcher: $launcher"
}
if (-not (Test-Path -LiteralPath $icon)) {
    throw "Missing Iris icon: $icon"
}

$shell = New-Object -ComObject WScript.Shell

function New-IrisShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $launcher
    $shortcut.WorkingDirectory = $repoRoot
    $shortcut.IconLocation = "$icon,0"
    $shortcut.Description = "Start Project Iris"
    $shortcut.Save()
}

$targets = @(
    (Join-Path ([Environment]::GetFolderPath("Desktop")) "Iris.lnk"),
    (Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "Iris.lnk"),
    (Join-Path ([Environment]::GetFolderPath("Programs")) "Iris.lnk"),
    (Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Iris.lnk")
)

foreach ($target in $targets) {
    try {
        New-IrisShortcut -Path $target
    } catch {
        Write-Warning "Could not create shortcut at $target`: $($_.Exception.Message)"
    }
}

# Windows 11 may ignore programmatic taskbar pinning, but keeping the pinned
# shortcut folder updated makes Iris available to Explorer's taskbar surface.
$targets
