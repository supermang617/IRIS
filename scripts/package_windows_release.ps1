param(
    [switch]$UseExistingReleaseBinaries,
    [switch]$KeepPackagingWorkspace
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot
. (Join-Path $PSScriptRoot "iris_release_workspace.ps1")

$releaseRoot = Join-Path $repoRoot "release"
$stagingRoot = Join-Path $releaseRoot "staging"
$distRoot = Join-Path $releaseRoot "dist"
$packageRoot = Join-Path $stagingRoot "iris-windows"
$zipPath = Join-Path $distRoot "iris-windows.zip"
$shaPath = "$zipPath.sha256"
$installerPath = Join-Path $distRoot "install-iris-windows.ps1"
$installerShaPath = "$installerPath.sha256"
$beginnerBundleRoot = Join-Path $stagingRoot "iris-windows-installer"
$beginnerZipPath = Join-Path $distRoot "iris-windows-installer.zip"
$beginnerShaPath = "$beginnerZipPath.sha256"

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

function Copy-RequiredFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    Require-File -Path $Source
    $destinationDir = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Copy-RequiredDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    Require-Directory -Path $Source
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function New-IrisZipFromDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    Require-Directory -Path $SourceDirectory
    $destinationDirectory = Split-Path -Parent $DestinationPath
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    try {
        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    } catch {
        throw "Unable to load .NET ZIP support: $($_.Exception.Message)"
    }

    $temporaryPath = Join-Path $destinationDirectory ([System.IO.Path]::GetRandomFileName())
    try {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        $sourceRoot = [System.IO.Path]::GetFullPath($SourceDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force)
        Write-Host "Adding $($files.Count) files to $DestinationPath"
        $fileStream = [System.IO.File]::Open(
            $temporaryPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        $archive = [System.IO.Compression.ZipArchive]::new(
            $fileStream,
            [System.IO.Compression.ZipArchiveMode]::Create
        )
        try {
            for ($index = 0; $index -lt $files.Count; $index++) {
                $file = $files[$index]
                $completed = $index + 1
                if ($completed -eq 1 -or $completed -eq $files.Count -or $completed % 1000 -eq 0) {
                    Write-Host "  zipped $completed / $($files.Count)"
                }
                $relativePath = $file.FullName.Substring($sourceRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar).Replace('\', '/')
                $entry = $archive.CreateEntry($relativePath, [System.IO.Compression.CompressionLevel]::Fastest)
                $entry.LastWriteTime = [DateTimeOffset]$file.LastWriteTime
                $inputStream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                $entryStream = $entry.Open()
                try {
                    $inputStream.CopyTo($entryStream)
                } finally {
                    $entryStream.Dispose()
                    $inputStream.Dispose()
                }
            }
        } finally {
            $archive.Dispose()
            $fileStream.Dispose()
        }
        if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
            Remove-Item -LiteralPath $DestinationPath -Force
        }
        Move-Item -LiteralPath $temporaryPath -Destination $DestinationPath -Force
    } catch {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        throw
    }
}

Write-Host "Packaging Iris Windows portable release from $repoRoot"

& (Join-Path $repoRoot "scripts\test_ollama_model_lock.ps1")

$portableWhisperFlags = @{
    GGML_NATIVE = "OFF"
    GGML_SSE42 = "OFF"
    GGML_AVX = "OFF"
    GGML_AVX2 = "OFF"
    GGML_AVX_VNNI = "OFF"
    GGML_BMI2 = "OFF"
    GGML_AVX512 = "OFF"
    GGML_AVX512_VBMI = "OFF"
    GGML_AVX512_VNNI = "OFF"
    GGML_AVX512_BF16 = "OFF"
    GGML_FMA = "OFF"
    GGML_F16C = "OFF"
    GGML_AMX_TILE = "OFF"
    GGML_AMX_INT8 = "OFF"
    GGML_AMX_BF16 = "OFF"
}
foreach ($name in $portableWhisperFlags.Keys) {
    Set-Item -Path "Env:$name" -Value $portableWhisperFlags[$name]
}
Write-Host "Portable Whisper/GGML CPU flags enabled for release packaging."

Remove-IrisReleaseWorkspace -RepositoryRoot $repoRoot -Workspace staging
Remove-Item -LiteralPath $distRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $packageRoot, $distRoot | Out-Null

if ($UseExistingReleaseBinaries) {
    Write-Warning "Using existing target\\release executables. This mode is for packaging diagnostics only; production releases must build from the tagged source."
} else {
    Write-Host "Building release executables..."
    & cargo build --workspace --release --locked
    if ($LASTEXITCODE -ne 0) {
        throw "cargo build --workspace --release failed with exit code $LASTEXITCODE"
    }
}

$runtimeExe = Join-Path $repoRoot "target\release\iris-runtime.exe"
$tauriExe = Join-Path $repoRoot "target\release\iris-tauri.exe"
Require-File -Path $runtimeExe
Require-File -Path $tauriExe

Copy-RequiredFile -Source $runtimeExe -Destination (Join-Path $packageRoot "bin\iris-runtime.exe")
Copy-RequiredFile -Source $tauriExe -Destination (Join-Path $packageRoot "bin\iris-tauri.exe")

Copy-RequiredFile -Source (Join-Path $repoRoot "manifest.json") -Destination (Join-Path $packageRoot "manifest.json")
Copy-RequiredFile -Source (Join-Path $repoRoot "LICENSE") -Destination (Join-Path $packageRoot "LICENSE")
Copy-RequiredFile -Source (Join-Path $repoRoot "NOTICE.md") -Destination (Join-Path $packageRoot "NOTICE.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "SECURITY.md") -Destination (Join-Path $packageRoot "SECURITY.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "known-limitations.md") -Destination (Join-Path $packageRoot "known-limitations.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\download-and-run.md") -Destination (Join-Path $packageRoot "README_RELEASE.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\dynamic-system-context.md") -Destination (Join-Path $packageRoot "docs\dynamic-system-context.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\finish-checklist.md") -Destination (Join-Path $packageRoot "docs\finish-checklist.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\installer-preflight.md") -Destination (Join-Path $packageRoot "docs\installer-preflight.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\iris-architecture.md") -Destination (Join-Path $packageRoot "docs\iris-architecture.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\windows-installer.md") -Destination (Join-Path $packageRoot "docs\windows-installer.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\signed-installer-decision.md") -Destination (Join-Path $packageRoot "docs\signed-installer-decision.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\winget-release.md") -Destination (Join-Path $packageRoot "docs\winget-release.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\runtime-orchestration.md") -Destination (Join-Path $packageRoot "docs\runtime-orchestration.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\manual-test.md") -Destination (Join-Path $packageRoot "docs\manual-test.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\manual-end-user-test.md") -Destination (Join-Path $packageRoot "docs\manual-end-user-test.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "tools\kokoro_tts.py") -Destination (Join-Path $packageRoot "tools\kokoro_tts.py")
Copy-RequiredFile -Source (Join-Path $repoRoot "tools\iris_image_provider.py") -Destination (Join-Path $packageRoot "tools\iris_image_provider.py")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\iris_preflight_wizard.ps1") -Destination (Join-Path $packageRoot "Iris Preflight.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\iris_setup_wizard.ps1") -Destination (Join-Path $packageRoot "Iris Setup Wizard.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\iris_document_ocr.ps1") -Destination (Join-Path $packageRoot "Iris Document OCR.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\install_iris_windows.ps1") -Destination (Join-Path $packageRoot "Install Iris.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\initialize_iris_data_root.ps1") -Destination (Join-Path $packageRoot "Initialize Iris Data Root.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\update_iris_windows.ps1") -Destination (Join-Path $packageRoot "Update Iris.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\iris_ollama_model_lock.ps1") -Destination (Join-Path $packageRoot "scripts\iris_ollama_model_lock.ps1")

Copy-RequiredDirectory -Source (Join-Path $repoRoot "models") -Destination (Join-Path $packageRoot "models")
Copy-RequiredDirectory -Source (Join-Path $repoRoot "profiles") -Destination (Join-Path $packageRoot "profiles")
Copy-RequiredDirectory -Source (Join-Path $repoRoot "capabilities") -Destination (Join-Path $packageRoot "capabilities")
Copy-RequiredDirectory -Source (Join-Path $repoRoot "assets") -Destination (Join-Path $packageRoot "assets")
Copy-RequiredDirectory -Source (Join-Path $repoRoot "plugins") -Destination (Join-Path $packageRoot "plugins")

$hermesRuntime = Join-Path $repoRoot ".iris-runtime\hermes"
$voiceRuntime = Join-Path $repoRoot ".iris-runtime\voice"
$browserRuntime = Join-Path $repoRoot ".iris-runtime\browser"
Copy-RequiredDirectory `
    -Source (Join-Path $hermesRuntime ".venv\Lib\site-packages") `
    -Destination (Join-Path $packageRoot ".iris-runtime\hermes\.venv\Lib\site-packages")
Copy-RequiredDirectory `
    -Source (Join-Path $voiceRuntime "Lib\site-packages") `
    -Destination (Join-Path $packageRoot ".iris-runtime\voice\Lib\site-packages")
Copy-RequiredFile `
    -Source (Join-Path $voiceRuntime "runtime-lock.txt") `
    -Destination (Join-Path $packageRoot ".iris-runtime\voice\runtime-lock.txt")
Copy-RequiredDirectory -Source (Join-Path $browserRuntime "node_modules") -Destination (Join-Path $packageRoot ".iris-runtime\browser\node_modules")
Copy-RequiredFile -Source (Join-Path $browserRuntime "package.json") -Destination (Join-Path $packageRoot ".iris-runtime\browser\package.json")
Copy-RequiredFile -Source (Join-Path $browserRuntime "package-lock.json") -Destination (Join-Path $packageRoot ".iris-runtime\browser\package-lock.json")
$browserPrune = & (Join-Path $repoRoot "scripts\prune_windows_browser_runtime.ps1") `
    -BrowserRuntimeRoot (Join-Path $packageRoot ".iris-runtime\browser") `
    -PassThru

$packageRootResolved = [System.IO.Path]::GetFullPath($packageRoot).TrimEnd("\")
foreach ($cacheDirectory in @(Get-ChildItem -LiteralPath $packageRootResolved -Recurse -Force -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue)) {
    $cachePath = [System.IO.Path]::GetFullPath($cacheDirectory.FullName)
    if (-not $cachePath.StartsWith($packageRootResolved + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove packaged cache outside staging root: $cachePath"
    }
    Remove-Item -LiteralPath $cachePath -Recurse -Force
}
foreach ($bytecodeFile in @(Get-ChildItem -LiteralPath $packageRootResolved -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".pyc", ".pyo") })) {
    $bytecodePath = [System.IO.Path]::GetFullPath($bytecodeFile.FullName)
    if (-not $bytecodePath.StartsWith($packageRootResolved + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove packaged bytecode outside staging root: $bytecodePath"
    }
    Remove-Item -LiteralPath $bytecodePath -Force
}

$voiceProfileLock = Join-Path $packageRoot "profiles\iris_voice_python_3_13.lock.txt"
$voiceRuntimeLock = Join-Path $packageRoot ".iris-runtime\voice\runtime-lock.txt"
$voiceLockHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $voiceProfileLock).Hash.ToLowerInvariant()
$voiceRuntimeLockHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $voiceRuntimeLock).Hash.ToLowerInvariant()
if ($voiceRuntimeLockHash -ne $voiceLockHash) {
    throw "Iris voice runtime was provisioned from a different lock. Run scripts\provision_iris_voice_runtime.ps1 before packaging."
}
$voiceLockText = Get-Content -LiteralPath $voiceProfileLock -Raw
$voiceLockedPackages = @(
    Get-Content -LiteralPath $voiceProfileLock |
        Where-Object { $_ -match '^[a-z0-9][a-z0-9._-]*==[^ ]+ \\' }
)
if (
    $voiceLockedPackages.Count -ne 32 -or
    $voiceLockText -notmatch '(?m)^kokoro-onnx==0\.5\.0 \\' -or
    $voiceLockText -notmatch '(?m)^soundfile==0\.14\.0 \\'
) {
    throw "Iris voice runtime lock is incomplete."
}
$voiceLayerBytes = [int64]((Get-ChildItem -LiteralPath (Join-Path $packageRoot ".iris-runtime\voice\Lib\site-packages") -Recurse -Force -File |
        Measure-Object -Property Length -Sum).Sum)

$runtimeManifest = [ordered]@{
    hermes_agent = [ordered]@{
        version = "0.18.0"
        upstream_tag = "v2026.7.1"
        upstream_commit = "7c1a029553d87c43ecff8a3821336bc95872213b"
        wheel_sha256 = "bf75c02d59f7c464cd0d85026fb7ee2e6bb15f003beccab3442b572f1ae1fd37"
        dependency_lock = "profiles/hermes_agent_python_3_13.lock.txt"
        dependency_lock_sha256 = "0e2e636b49109143e4ddf6787f94bf24722cdbd491001436298515934f47be5f"
        dependency_count = 65
        security_overrides = [ordered]@{
            cryptography = "50.0.0"
            pillow = "12.3.0"
        }
        sigstore_entry = "2040635656"
        bundled_site_packages = $true
        bundled_interpreter = $false
        required_python = "3.13"
    }
    voice_python = [ordered]@{
        required_python = "3.13"
        platform = "win_amd64"
        bundled_site_packages = $true
        bundled_interpreter = $false
        lock_path = "profiles/iris_voice_python_3_13.lock.txt"
        lock_sha256 = $voiceLockHash
        package_count = 32
        installed_bytes = $voiceLayerBytes
        roots = @("kokoro-onnx==0.5.0", "soundfile==0.14.0")
        core_versions = [ordered]@{
            numpy = "2.5.1"
            onnxruntime = "1.28.0"
        }
        upgrade_owner = "AlejandroPinto.Iris"
    }
    agent_browser = [ordered]@{
        version = "0.33.2"
        platform = "windows-x64"
        modified_controller = $true
        upstream_pull_request = "https://github.com/vercel-labs/agent-browser/pull/1655"
        upstream_commit = "c21c9b741a1eb23218c2bc9d165dc9c0af718604"
        local_patch_sha256 = "b62c7599e3e185e92813f3e891b0e446da54ad1bdc7810f9c6e0bb5750e2a36f"
        provisioning_archive_sha256 = "4b7e61f0c106b679f9451f146bdd6a3c7ef33f2287a490605e40ca049240a04f"
        binary_sha256 = $browserPrune.WindowsBinarySha256
        pruned_non_windows_binaries = $browserPrune.RemovedCount
        pruned_bytes = $browserPrune.BytesRemoved
    }
    system_browser = [ordered]@{
        bundled = $false
        preferred = "Google Chrome"
        winget_package = "Google.Chrome"
        executable_override = "IRIS_BROWSER_EXECUTABLE_PATH"
        isolated_session = $true
        persistent_profile = $false
    }
    volatile_data_packaged = $false
}
$runtimeManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $packageRoot ".iris-runtime\runtime-manifest.json") -Encoding utf8

$startPs1 = @'
param(
    [switch]$SelfCheck
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeExe = Join-Path $root "bin\iris-runtime.exe"
$desktopExe = Join-Path $root "bin\iris-tauri.exe"
$dataRootInitializer = Join-Path $root "Initialize Iris Data Root.ps1"
$manifestPath = Join-Path $root "manifest.json"
$kokoroModel = Join-Path $root "models\kokoro\kokoro-v1.0.onnx"
$kokoroVoices = Join-Path $root "models\kokoro\voices-v1.0.bin"
$whisperModel = Join-Path $root "models\whisper\ggml-tiny.en.bin"
$hermesMetadata = Join-Path $root ".iris-runtime\hermes\.venv\Lib\site-packages\hermes_agent-0.18.0.dist-info\METADATA"
$voiceLock = Join-Path $root ".iris-runtime\voice\runtime-lock.txt"
$voiceKokoroMetadata = Join-Path $root ".iris-runtime\voice\Lib\site-packages\kokoro_onnx-0.5.0.dist-info\METADATA"
$voiceSoundfileMetadata = Join-Path $root ".iris-runtime\voice\Lib\site-packages\soundfile-0.14.0.dist-info\METADATA"
$voiceNumpyMetadata = Join-Path $root ".iris-runtime\voice\Lib\site-packages\numpy-2.5.1.dist-info\METADATA"
$voiceOnnxruntimeMetadata = Join-Path $root ".iris-runtime\voice\Lib\site-packages\onnxruntime-1.28.0.dist-info\METADATA"
$agentBrowser = Join-Path $root ".iris-runtime\browser\node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
$ollamaModelLockHelper = Join-Path $root "scripts\iris_ollama_model_lock.ps1"

function Require-File {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Iris release is missing required file: $Path"
    }
}

Require-File -Path $runtimeExe
Require-File -Path $desktopExe
Require-File -Path $dataRootInitializer
Require-File -Path $manifestPath
Require-File -Path $kokoroModel
Require-File -Path $kokoroVoices
Require-File -Path $whisperModel
Require-File -Path $hermesMetadata
Require-File -Path $voiceLock
Require-File -Path $voiceKokoroMetadata
Require-File -Path $voiceSoundfileMetadata
Require-File -Path $voiceNumpyMetadata
Require-File -Path $voiceOnnxruntimeMetadata
Require-File -Path $agentBrowser
Require-File -Path $ollamaModelLockHelper

. $ollamaModelLockHelper

& $dataRootInitializer -InstallRoot $root

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
            Write-Host "Initialized CurrentUser $Name=$Value so the Ollama server can inherit Iris' measured memory default."
        } catch {
            Write-Warning "Could not persist CurrentUser $Name; this launch still uses $Value. $($_.Exception.Message)"
        }
    }
}

Set-IrisOllamaDefault -Name "OLLAMA_FLASH_ATTENTION" -Value "1" -PersistForCurrentUser
Set-IrisOllamaDefault -Name "OLLAMA_KV_CACHE_TYPE" -Value "q8_0" -PersistForCurrentUser
Set-IrisOllamaDefault -Name "OLLAMA_NUM_PARALLEL" -Value "1"
Set-IrisOllamaDefault -Name "OLLAMA_MAX_LOADED_MODELS" -Value "2"

Set-Location -LiteralPath $root

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
        return [string](Get-IrisOllamaModelLock -Root $root).model_id
    } catch {
        return ""
    }
}

function Get-IrisVisionModelId {
    try {
        return [string](Get-IrisOllamaModelLock -Root $root -Role Vision).model_id
    } catch {
        return ""
    }
}

function Get-IrisNumCtx {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        return [int]$manifest.model_policy.num_ctx_ceiling
    } catch {
        return 8192
    }
}

function Use-IrisOllamaModelStore {
    $modelLocks = @(
        (Get-IrisOllamaModelLock -Root $root -Role Primary),
        (Get-IrisOllamaModelLock -Root $root -Role Vision)
    )
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:OLLAMA_MODELS)) {
        $candidates += $env:OLLAMA_MODELS
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $candidates += Join-Path $env:USERPROFILE ".ollama\models"
    }
    $candidates += "C:\.ollama"
    $verifiedRoot = $null
    foreach ($modelLock in $modelLocks) {
        $modelId = [string]$modelLock.model_id
        $verification = Find-IrisOllamaModelStore -Candidates $candidates -Lock $modelLock
        if ($null -eq $verification) {
            throw "Iris's digest-verified model is not installed. Run 'ollama pull $modelId' once to repair a missing or corrupt local model."
        }
        if ($null -ne $verifiedRoot -and [string]$verification.ModelsRoot -ine [string]$verifiedRoot) {
            throw "Iris's primary and vision models must be installed in the same verified Ollama model store."
        }
        $verifiedRoot = [string]$verification.ModelsRoot
        Set-IrisOllamaModelStoreAttestation -Verification $verification -Lock $modelLock
    }
    $env:OLLAMA_MODELS = $verifiedRoot
}

function Test-OllamaModelAvailable {
    $modelIds = @((Get-IrisModelId), (Get-IrisVisionModelId)) | Where-Object { $_ }
    if ($modelIds.Count -ne 2) {
        return $false
    }
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -UseBasicParsing -TimeoutSec 2
        $tags = $response.Content | ConvertFrom-Json
        foreach ($modelId in $modelIds) {
            if (-not [bool](@($tags.models) | Where-Object { $_.name -eq $modelId -or $_.model -eq $modelId } | Select-Object -First 1)) {
                return $false
            }
        }
        return $true
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
    $env:OLLAMA_CONTEXT_LENGTH = [string](Get-IrisNumCtx)
    $env:OLLAMA_HOST = "127.0.0.1:11434"
}

function Start-OllamaForIris {
    Use-IrisOllamaModelStore
    Use-IrisOllamaRuntimeSettings

    if (Test-OllamaReady) {
        Assert-IrisOllamaLoopbackOnly
        try {
            Assert-IrisOllamaModelIdentity -Root $root -ModelsRoot $env:OLLAMA_MODELS -TimeoutSeconds 15 -Role Primary | Out-Null
            Assert-IrisOllamaModelIdentity -Root $root -ModelsRoot $env:OLLAMA_MODELS -TimeoutSeconds 15 -Role Vision | Out-Null
        } catch {
            throw "Iris refuses to use an Ollama model that differs from its immutable model lock. $($_.Exception.Message)"
        }
        if ($script:irisOllamaServerDefaultsInitialized) {
            Write-Host "Ollama is already listening. Iris will not terminate the shared server; newly initialized CurrentUser memory defaults apply the next time Ollama starts."
        } elseif ((Test-OllamaModelAvailable) -and (Test-OllamaRuntimeCompatible)) {
            return
        } else {
            Write-Host "Ollama is already listening. Iris will use the shared server without terminating it; self-check will report a missing model or incompatible runtime."
        }
        return
    }
    if (-not (Test-CommandAvailable -Name "ollama")) {
        throw "Ollama is not available on PATH. Run Iris Setup Wizard or install Ollama for Windows."
    }
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if (Test-OllamaReady) {
            Assert-IrisOllamaLoopbackOnly
            Assert-IrisOllamaModelIdentity -Root $root -ModelsRoot $env:OLLAMA_MODELS -TimeoutSeconds 15 -Role Primary | Out-Null
            Assert-IrisOllamaModelIdentity -Root $root -ModelsRoot $env:OLLAMA_MODELS -TimeoutSeconds 15 -Role Vision | Out-Null
            return
        }
    }
    throw "Ollama did not become ready on 127.0.0.1:11434 within 60 seconds after launch."
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

function Invoke-IrisSelfCheck {
    $output = @()
    $exitCode = 0
    try {
        $output = & $runtimeExe --self-check 2>&1
        $exitCode = $LASTEXITCODE
    } catch {
        $output = @($output; ($_ | Out-String))
        $exitCode = 1
    }
    if ($output.Count -gt 0) {
        $output | ForEach-Object { Write-Host $_ }
    }
    if ($exitCode -eq 0) {
        return 0
    }

    Write-Host "Iris self-check failed with exit code $exitCode. The launcher will not terminate a shared Ollama server."
    return $exitCode
}

if ($SelfCheck -or $env:IRIS_SELF_CHECK -eq "1" -or $args -contains "--self-check") {
    Start-OllamaForIris
    $selfCheckExitCode = Invoke-IrisSelfCheck
    exit $selfCheckExitCode
}

Start-OllamaForIris
if (Test-IrisAlreadyRunning -ExecutablePath $desktopExe) {
    exit 0
}
Start-Process -FilePath $desktopExe -WorkingDirectory $root
'@

$startBat = @'
@echo off
setlocal
set "IRIS_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%IRIS_ROOT%Start Iris.ps1" %*
exit /b %ERRORLEVEL%
'@

$preflightBat = @'
@echo off
setlocal
set "IRIS_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%IRIS_ROOT%Iris Preflight.ps1" %*
exit /b %ERRORLEVEL%
'@

$setupBat = @'
@echo off
setlocal
set "IRIS_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%IRIS_ROOT%Iris Setup Wizard.ps1" %*
exit /b %ERRORLEVEL%
'@

$installBat = @'
@echo off
setlocal
set "IRIS_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%IRIS_ROOT%Install Iris.ps1" -RunSetup %*
exit /b %ERRORLEVEL%
'@

$updateBat = @'
@echo off
setlocal
set "IRIS_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%IRIS_ROOT%Update Iris.ps1" %*
exit /b %ERRORLEVEL%
'@

Set-Content -LiteralPath (Join-Path $packageRoot "Start Iris.ps1") -Value $startPs1 -Encoding utf8
Set-Content -LiteralPath (Join-Path $packageRoot "Start Iris.bat") -Value $startBat -Encoding ascii
Set-Content -LiteralPath (Join-Path $packageRoot "Check Iris Preflight.bat") -Value $preflightBat -Encoding ascii
Set-Content -LiteralPath (Join-Path $packageRoot "Iris Setup Wizard.bat") -Value $setupBat -Encoding ascii
Set-Content -LiteralPath (Join-Path $packageRoot "Install Iris.bat") -Value $installBat -Encoding ascii
Set-Content -LiteralPath (Join-Path $packageRoot "Update Iris.bat") -Value $updateBat -Encoding ascii

Write-Host "Creating $zipPath"
New-IrisZipFromDirectory -SourceDirectory $packageRoot -DestinationPath $zipPath

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $shaPath -Value "$hash  iris-windows.zip" -Encoding ascii
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\install_iris_windows.ps1") -Destination $installerPath
$installerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $installerShaPath -Value "$installerHash  install-iris-windows.ps1" -Encoding ascii

$beginnerBat = @'
@echo off
setlocal
title Install Iris
set "IRIS_INSTALLER_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%IRIS_INSTALLER_ROOT%install-iris-windows.ps1" -SourceZip "%IRIS_INSTALLER_ROOT%iris-windows.zip" -Sha256Path "%IRIS_INSTALLER_ROOT%iris-windows.zip.sha256" -RunSetup -LaunchAfterInstall %*
if errorlevel 1 (
  echo.
  echo Iris installation did not complete. Review the error above, then run Install Iris.bat again.
  pause
  exit /b 1
)
exit /b 0
'@

$beginnerReadme = @'
IRIS WINDOWS INSTALLER

1. Keep all files in this folder together.
2. Double-click "Install Iris.bat".
3. Approve only the setup repairs you want Iris to perform.
4. The installer verifies the packaged SHA256 before copying files.
5. When installation succeeds, Iris opens and Desktop/Start Menu shortcuts are available.

Iris installs for the current Windows user under:
%LOCALAPPDATA%\Programs\Iris

The setup wizard may offer approved local prerequisites such as WebView2,
Ollama, the configured Gemma model, exact Python 3.13 plus Iris-owned voice packages, or Tesseract OCR.
It does not add a cloud model API or silently enable Agentic mode.
'@

New-Item -ItemType Directory -Force -Path $beginnerBundleRoot | Out-Null
Copy-RequiredFile -Source $zipPath -Destination (Join-Path $beginnerBundleRoot "iris-windows.zip")
Copy-RequiredFile -Source $shaPath -Destination (Join-Path $beginnerBundleRoot "iris-windows.zip.sha256")
Copy-RequiredFile -Source $installerPath -Destination (Join-Path $beginnerBundleRoot "install-iris-windows.ps1")
Set-Content -LiteralPath (Join-Path $beginnerBundleRoot "Install Iris.bat") -Value $beginnerBat -Encoding ascii
Set-Content -LiteralPath (Join-Path $beginnerBundleRoot "README.txt") -Value $beginnerReadme -Encoding ascii
New-IrisZipFromDirectory -SourceDirectory $beginnerBundleRoot -DestinationPath $beginnerZipPath
$beginnerHash = (Get-FileHash -LiteralPath $beginnerZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $beginnerShaPath -Value "$beginnerHash  iris-windows-installer.zip" -Encoding ascii

if ($KeepPackagingWorkspace) {
    Write-Warning "Keeping generated release staging workspace for diagnostics: $stagingRoot"
} else {
    Remove-IrisReleaseWorkspace -RepositoryRoot $repoRoot -Workspace "staging"
}

Write-Host "Iris Windows ZIP: $zipPath"
Write-Host "Iris Windows SHA256: $shaPath"
Write-Host "SHA256: $hash"
Write-Host "Iris Windows installer wrapper: $installerPath"
Write-Host "Iris Windows installer wrapper SHA256: $installerShaPath"
Write-Host "Installer SHA256: $installerHash"
Write-Host "Iris beginner installer bundle: $beginnerZipPath"
Write-Host "Iris beginner installer SHA256: $beginnerShaPath"
Write-Host "Beginner installer SHA256: $beginnerHash"
