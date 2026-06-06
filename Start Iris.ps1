param(
    [switch]$SelfCheck
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repoRoot

$diagnosticsDir = Join-Path $repoRoot "diagnostics"
New-Item -ItemType Directory -Force -Path $diagnosticsDir | Out-Null
$logPath = Join-Path $diagnosticsDir "manual-launch.log"

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-OllamaReady {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -UseBasicParsing -TimeoutSec 2
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 500
    } catch {
        return $false
    }
}

function Start-OllamaForIris {
    param([Parameter(Mandatory = $true)][string]$LogPath)

    if (Test-OllamaReady) {
        "[$(Get-Date -Format o)] Ollama is already listening on 127.0.0.1:11434." | Out-File -FilePath $LogPath -Encoding utf8 -Append
        return
    }

    if (-not (Test-CommandAvailable -Name "ollama")) {
        throw "Ollama is not available on PATH. Run Iris Setup Wizard or install Ollama for Windows."
    }

    "[$(Get-Date -Format o)] Starting Ollama in the background." | Out-File -FilePath $LogPath -Encoding utf8 -Append
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden

    for ($attempt = 1; $attempt -le 20; $attempt++) {
        Start-Sleep -Milliseconds 500
        if (Test-OllamaReady) {
            "[$(Get-Date -Format o)] Ollama is ready after $attempt checks." | Out-File -FilePath $LogPath -Encoding utf8 -Append
            return
        }
    }

    throw "Ollama did not become ready on 127.0.0.1:11434 after launch."
}

if (-not $env:IRIS_HERMES_ENABLED) {
    $env:IRIS_HERMES_ENABLED = "true"
}
if (-not $env:IRIS_HERMES_SIDECAR_ENABLED) {
    $env:IRIS_HERMES_SIDECAR_ENABLED = "true"
}
if (-not $env:IRIS_HERMES_MEMORY_BROKER_ENABLED) {
    $env:IRIS_HERMES_MEMORY_BROKER_ENABLED = "true"
}
if (-not $env:IRIS_HERMES_ALLOW_SEARCH) {
    $env:IRIS_HERMES_ALLOW_SEARCH = "true"
}

try {
    $exePath = Join-Path $repoRoot "target\debug\iris-tauri.exe"
    $preflightScript = Join-Path $repoRoot "scripts\iris_preflight_wizard.ps1"
    $desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Iris.lnk"
    $shortcutInstaller = Join-Path $repoRoot "Install Iris Shortcuts.ps1"

    if ($SelfCheck) {
        "[$(Get-Date -Format o)] Running Iris launcher self-check." | Out-File -FilePath $logPath -Encoding utf8
        if (Test-Path -LiteralPath $preflightScript) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $preflightScript *>> $logPath
            $preflightExitCode = $LASTEXITCODE
            if ($preflightExitCode -ne 0) {
                throw "iris_preflight_wizard.ps1 failed with exit code $preflightExitCode"
            }
        } else {
            throw "Missing Iris preflight script: $preflightScript"
        }

        cmd.exe /c "cargo run -p xtask >> `"$logPath`" 2>&1"
        $xtaskExitCode = $LASTEXITCODE
        if ($xtaskExitCode -ne 0) {
            throw "cargo run -p xtask failed with exit code $xtaskExitCode"
        }

        cmd.exe /c "cargo run -p iris-runtime -- --self-check >> `"$logPath`" 2>&1"
        $runtimeExitCode = $LASTEXITCODE
        if ($runtimeExitCode -ne 0) {
            throw "cargo run -p iris-runtime -- --self-check failed with exit code $runtimeExitCode"
        }

        "[$(Get-Date -Format o)] Iris launcher self-check passed." | Out-File -FilePath $logPath -Encoding utf8 -Append
        Write-Host "Iris launcher self-check passed."
        Write-Host "Log: $logPath"
        return
    }

    if (($env:IRIS_REFRESH_SHORTCUTS -eq "1" -or -not (Test-Path -LiteralPath $desktopShortcut)) -and (Test-Path -LiteralPath $shortcutInstaller)) {
        "[$(Get-Date -Format o)] Refreshing Iris shortcuts." | Out-File -FilePath $logPath -Encoding utf8
        & $shortcutInstaller *>> $logPath
    }

    $shouldBuild = (-not (Test-Path -LiteralPath $exePath)) -or $env:IRIS_FORCE_BUILD -eq "1"

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

    Start-OllamaForIris -LogPath $logPath

    "[$(Get-Date -Format o)] Starting $exePath" | Out-File -FilePath $logPath -Encoding utf8 -Append
    Start-Process -FilePath $exePath -WorkingDirectory $repoRoot
} catch {
    "[$(Get-Date -Format o)] ERROR: $($_.Exception.Message)" | Out-File -FilePath $logPath -Encoding utf8 -Append
    throw
}
