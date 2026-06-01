$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repoRoot

$diagnosticsDir = Join-Path $repoRoot "diagnostics"
New-Item -ItemType Directory -Force -Path $diagnosticsDir | Out-Null
$logPath = Join-Path $diagnosticsDir "manual-launch.log"

try {
    $shortcutInstaller = Join-Path $repoRoot "Install Iris Shortcuts.ps1"
    if (Test-Path -LiteralPath $shortcutInstaller) {
        & $shortcutInstaller *>> $logPath
    }

    "[$(Get-Date -Format o)] Building standalone Iris debug shell." | Out-File -FilePath $logPath -Encoding utf8
    cmd.exe /c "cargo build -p iris-tauri >> `"$logPath`" 2>&1"
    $buildExitCode = $LASTEXITCODE
    if ($buildExitCode -ne 0) {
        throw "cargo build -p iris-tauri failed with exit code $buildExitCode"
    }

    $exePath = Join-Path $repoRoot "target\debug\iris-tauri.exe"
    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "Missing Iris executable: $exePath"
    }

    "[$(Get-Date -Format o)] Starting $exePath" | Out-File -FilePath $logPath -Encoding utf8 -Append
    Start-Process -FilePath $exePath -WorkingDirectory $repoRoot
} catch {
    "[$(Get-Date -Format o)] ERROR: $($_.Exception.Message)" | Out-File -FilePath $logPath -Encoding utf8 -Append
    throw
}
