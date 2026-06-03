$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repoRoot

$diagnosticsDir = Join-Path $repoRoot "diagnostics"
New-Item -ItemType Directory -Force -Path $diagnosticsDir | Out-Null
$logPath = Join-Path $diagnosticsDir "manual-launch.log"

try {
    $exePath = Join-Path $repoRoot "target\debug\iris-tauri.exe"
    $desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Iris.lnk"
    $shortcutInstaller = Join-Path $repoRoot "Install Iris Shortcuts.ps1"
    if (($env:IRIS_REFRESH_SHORTCUTS -eq "1" -or -not (Test-Path -LiteralPath $desktopShortcut)) -and (Test-Path -LiteralPath $shortcutInstaller)) {
        "[$(Get-Date -Format o)] Refreshing Iris shortcuts." | Out-File -FilePath $logPath -Encoding utf8
        & $shortcutInstaller *>> $logPath
    }

    $shouldBuild = -not (Test-Path -LiteralPath $exePath)
    if (-not $shouldBuild -and $env:IRIS_FORCE_BUILD -ne "1") {
        $exeTime = (Get-Item -LiteralPath $exePath).LastWriteTimeUtc
        $sourcePaths = @(
            (Join-Path $repoRoot "Cargo.toml"),
            (Join-Path $repoRoot "Cargo.lock"),
            (Join-Path $repoRoot "app"),
            (Join-Path $repoRoot "crates"),
            (Join-Path $repoRoot "src-tauri")
        )
        foreach ($sourcePath in $sourcePaths) {
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                continue
            }
            $newerSource = Get-ChildItem -LiteralPath $sourcePath -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch "\\target\\|\\node_modules\\" -and $_.LastWriteTimeUtc -gt $exeTime } |
                Select-Object -First 1
            if ($newerSource) {
                $shouldBuild = $true
                break
            }
        }
    } elseif ($env:IRIS_FORCE_BUILD -eq "1") {
        $shouldBuild = $true
    }

    if ($shouldBuild) {
        "[$(Get-Date -Format o)] Building standalone Iris debug shell." | Out-File -FilePath $logPath -Encoding utf8 -Append
        cmd.exe /c "cargo build -p iris-tauri >> `"$logPath`" 2>&1"
        $buildExitCode = $LASTEXITCODE
        if ($buildExitCode -ne 0) {
            throw "cargo build -p iris-tauri failed with exit code $buildExitCode"
        }
    } else {
        "[$(Get-Date -Format o)] Using existing Iris debug shell." | Out-File -FilePath $logPath -Encoding utf8
    }

    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "Missing Iris executable: $exePath"
    }

    "[$(Get-Date -Format o)] Starting $exePath" | Out-File -FilePath $logPath -Encoding utf8 -Append
    Start-Process -FilePath $exePath -WorkingDirectory $repoRoot
} catch {
    "[$(Get-Date -Format o)] ERROR: $($_.Exception.Message)" | Out-File -FilePath $logPath -Encoding utf8 -Append
    throw
}
