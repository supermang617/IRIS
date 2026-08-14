param(
    [switch]$SelfCheck
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repoRoot

$ollamaModelLockHelper = Join-Path $repoRoot "scripts\iris_ollama_model_lock.ps1"
if (-not (Test-Path -LiteralPath $ollamaModelLockHelper -PathType Leaf)) {
    throw "Missing Iris Ollama model-lock verifier: $ollamaModelLockHelper"
}
. $ollamaModelLockHelper

$dataRootInitializer = Join-Path $repoRoot "scripts\initialize_iris_data_root.ps1"
if (-not (Test-Path -LiteralPath $dataRootInitializer -PathType Leaf)) {
    throw "Missing Iris data-root initializer: $dataRootInitializer"
}
$dataRoot = (& $dataRootInitializer -InstallRoot $repoRoot -PassThru | Select-Object -Last 1)
if (-not $dataRoot) {
    throw "Iris per-user data root initialization did not return a path."
}
$diagnosticsDir = Join-Path $dataRoot "diagnostics"
New-Item -ItemType Directory -Force -Path $diagnosticsDir | Out-Null
$logPath = Join-Path $diagnosticsDir "manual-launch.log"

$script:irisOllamaServerDefaultsInitialized = $false

function Set-IrisOllamaDefault {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value,
        [switch]$PersistForCurrentUser
    )
    $current = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        return
    }

    $persisted = @(
        [Environment]::GetEnvironmentVariable($Name, "User"),
        [Environment]::GetEnvironmentVariable($Name, "Machine")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if ($persisted) {
        Set-Item -Path "Env:$Name" -Value $persisted
        return
    }

    Set-Item -Path "Env:$Name" -Value $Value
    if ($PersistForCurrentUser) {
        $script:irisOllamaServerDefaultsInitialized = $true
        try {
            [Environment]::SetEnvironmentVariable($Name, $Value, "User")
            "[$(Get-Date -Format o)] Initialized CurrentUser $Name=$Value so the Ollama server can inherit Iris' measured memory default." |
                Out-File -FilePath $logPath -Encoding utf8 -Append
        } catch {
            "[$(Get-Date -Format o)] WARNING: Could not persist CurrentUser $Name; this launch still uses $Value. $($_.Exception.Message)" |
                Out-File -FilePath $logPath -Encoding utf8 -Append
        }
    }
}

Set-IrisOllamaDefault -Name "OLLAMA_FLASH_ATTENTION" -Value "1" -PersistForCurrentUser
Set-IrisOllamaDefault -Name "OLLAMA_KV_CACHE_TYPE" -Value "q8_0" -PersistForCurrentUser
Set-IrisOllamaDefault -Name "OLLAMA_NUM_PARALLEL" -Value "1"
Set-IrisOllamaDefault -Name "OLLAMA_MAX_LOADED_MODELS" -Value "1"

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

function Assert-IrisOllamaLoopbackOnly {
    try {
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort 11434 -ErrorAction Stop)
    } catch {
        throw "Iris reached Ollama but could not verify that it is loopback-only. Quit Ollama and restart Iris. $($_.Exception.Message)"
    }
    if ($listeners.Count -eq 0) {
        throw "Iris reached Ollama but found no verifiable listener on port 11434. Quit Ollama and restart Iris."
    }
    $broadListeners = @($listeners | Where-Object { $_.LocalAddress -notin @("127.0.0.1", "::1", "::ffff:127.0.0.1") })
    if ($broadListeners.Count -gt 0) {
        $addresses = ($broadListeners.LocalAddress | Sort-Object -Unique) -join ", "
        throw "Ollama is listening beyond this computer ($addresses). Quit the existing Ollama service and restart Iris so Iris can launch it on 127.0.0.1:11434. Iris will not use a network-exposed model service."
    }
}

function Get-IrisModelId {
    try {
        return [string](Get-IrisOllamaModelLock -Root $repoRoot).model_id
    } catch {
        return ""
    }
}

function Get-IrisNumCtx {
    $manifestPath = Join-Path $repoRoot "manifest.json"
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        return [int]$manifest.model_policy.num_ctx_ceiling
    } catch {
        return 8192
    }
}

function Use-IrisOllamaModelStore {
    param([Parameter(Mandatory = $true)][string]$LogPath)
    $modelLock = Get-IrisOllamaModelLock -Root $repoRoot
    $candidates = @("C:\.ollama")
    if (-not [string]::IsNullOrWhiteSpace($env:OLLAMA_MODELS)) {
        $candidates = @($env:OLLAMA_MODELS) + $candidates
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $candidates += Join-Path $env:USERPROFILE ".ollama\models"
    }
    $modelId = [string]$modelLock.model_id
    $verification = Find-IrisOllamaModelStore -Candidates $candidates -Lock $modelLock
    if ($null -eq $verification) {
        throw "Iris's digest-verified model is not installed. Run 'ollama pull $modelId' once to repair a missing or corrupt local model."
    }
    $env:OLLAMA_MODELS = [string]$verification.ModelsRoot
    Set-IrisOllamaModelStoreAttestation -Verification $verification -Lock $modelLock
    "[$(Get-Date -Format o)] Using digest-verified Ollama model store $($verification.ModelsRoot) for $modelId." | Out-File -FilePath $LogPath -Encoding utf8 -Append
}

function Test-OllamaModelAvailable {
    $modelId = Get-IrisModelId
    if (-not $modelId) {
        return $true
    }
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -UseBasicParsing -TimeoutSec 2
        $tags = $response.Content | ConvertFrom-Json
        return [bool](@($tags.models) | Where-Object { $_.name -eq $modelId } | Select-Object -First 1)
    } catch {
        return $false
    }
}

function Test-OllamaRuntimeCompatible {
    $modelId = Get-IrisModelId
    $requiredContext = Get-IrisNumCtx
    if (-not $modelId -or $requiredContext -le 0) {
        return $false
    }
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/ps" -UseBasicParsing -TimeoutSec 2
        $status = $response.Content | ConvertFrom-Json
        $model = @($status.models) | Where-Object { $_.name -eq $modelId -or $_.model -eq $modelId } | Select-Object -First 1
        return $null -ne $model -and [int64]$model.context_length -ge $requiredContext
    } catch {
        return $false
    }
}

function Use-IrisOllamaRuntimeSettings {
    param([Parameter(Mandatory = $true)][string]$LogPath)
    $requiredContext = Get-IrisNumCtx
    $env:OLLAMA_CONTEXT_LENGTH = [string]$requiredContext
    $env:OLLAMA_HOST = "127.0.0.1:11434"
    "[$(Get-Date -Format o)] Ollama context length set to $requiredContext from manifest.json." | Out-File -FilePath $LogPath -Encoding utf8 -Append
    "[$(Get-Date -Format o)] Ollama host forced to loopback at 127.0.0.1:11434 for this Iris-owned launch." | Out-File -FilePath $LogPath -Encoding utf8 -Append
}

function Start-OllamaForIris {
    param([Parameter(Mandatory = $true)][string]$LogPath)

    Use-IrisOllamaModelStore -LogPath $LogPath
    Use-IrisOllamaRuntimeSettings -LogPath $LogPath

    if (Test-OllamaReady) {
        Assert-IrisOllamaLoopbackOnly
        try {
            Assert-IrisOllamaModelIdentity -Root $repoRoot -ModelsRoot $env:OLLAMA_MODELS -TimeoutSeconds 15 | Out-Null
        } catch {
            throw "Iris refuses to use an Ollama model that differs from its immutable model lock. $($_.Exception.Message)"
        }
        if ($script:irisOllamaServerDefaultsInitialized) {
            "[$(Get-Date -Format o)] Ollama is already listening. Iris will not terminate the shared server; newly initialized CurrentUser memory defaults apply the next time Ollama starts." |
                Out-File -FilePath $LogPath -Encoding utf8 -Append
        } elseif ((Test-OllamaModelAvailable) -and (Test-OllamaRuntimeCompatible)) {
            "[$(Get-Date -Format o)] Ollama is already listening with the Iris model and required context." | Out-File -FilePath $LogPath -Encoding utf8 -Append
        } else {
            "[$(Get-Date -Format o)] Ollama is already listening. Iris will use the shared server without terminating it; self-check will report a missing model or incompatible runtime." |
                Out-File -FilePath $LogPath -Encoding utf8 -Append
        }
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
            Assert-IrisOllamaLoopbackOnly
            Assert-IrisOllamaModelIdentity -Root $repoRoot -ModelsRoot $env:OLLAMA_MODELS -TimeoutSeconds 15 | Out-Null
            "[$(Get-Date -Format o)] Ollama is ready after $attempt checks." | Out-File -FilePath $LogPath -Encoding utf8 -Append
            return
        }
    }

    throw "Ollama did not become ready on 127.0.0.1:11434 after launch."
}

function Test-IrisAlreadyRunning {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)
    $resolved = [System.IO.Path]::GetFullPath($ExecutablePath)
    foreach ($process in @(Get-Process iris-tauri -ErrorAction SilentlyContinue)) {
        try {
            if ([System.IO.Path]::GetFullPath($process.Path) -ieq $resolved) {
                return $true
            }
        } catch {
            continue
        }
    }
    return $false
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

    if ($SelfCheck -or $args -contains "--self-check") {
        "[$(Get-Date -Format o)] Running Iris launcher self-check." | Out-File -FilePath $logPath -Encoding utf8
        Start-OllamaForIris -LogPath $logPath

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

    if (Test-IrisAlreadyRunning -ExecutablePath $exePath) {
        "[$(Get-Date -Format o)] Iris is already running from $exePath." | Out-File -FilePath $logPath -Encoding utf8 -Append
        return
    }

    "[$(Get-Date -Format o)] Starting $exePath" | Out-File -FilePath $logPath -Encoding utf8 -Append
    Start-Process -FilePath $exePath -WorkingDirectory $repoRoot
} catch {
    "[$(Get-Date -Format o)] ERROR: $($_.Exception.Message)" | Out-File -FilePath $logPath -Encoding utf8 -Append
    throw
}
