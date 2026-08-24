param([switch]$Live)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "iris_ollama_model_lock.ps1")

function Get-TestSha256Hex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

$lock = Get-IrisOllamaModelLock -Root $repoRoot
$tagModel = [pscustomobject]@{
    name = $lock.model_id
    digest = $lock.manifest_digest
    size = $lock.total_bytes
    details = [pscustomobject]@{
        family = $lock.family
        parameter_size = $lock.parameter_size
        quantization_level = $lock.quantization_level
    }
}
$show = [pscustomobject]@{
    details = $tagModel.details
    capabilities = @($lock.required_capabilities)
}
$verified = Assert-IrisOllamaModelIdentityData -Lock $lock -TagModel $tagModel -Show $show
if ($verified.ModelId -cne [string]$lock.model_id -or $verified.GeneralVisionVerified) {
    throw "The verified model identity or general-vision policy is incorrect."
}

$visionLock = Get-IrisOllamaModelLock -Root $repoRoot -Role Vision
if ([string]$visionLock.model_id -cne "qwen3.5:4b" -or
    [string]$visionLock.manifest_digest -cne "2a654d98e6fba55d452b7043684e9b57a947e393bbffa62485a7aac05ee4eefd" -or
    [string]$visionLock.model_layer_digest -cne "sha256:81fb60c7daa80fc1123380b98970b320ae233409f0f71a72ed7b9b0d62f40490" -or
    [int64]$visionLock.total_bytes -ne 3389983735 -or
    -not [bool]$visionLock.general_vision_verified) {
    throw "The embedded visual model lock differs from the audited Qwen profile."
}
$visionTagModel = [pscustomobject]@{
    name = $visionLock.model_id
    digest = $visionLock.manifest_digest
    size = $visionLock.total_bytes
    details = [pscustomobject]@{
        family = $visionLock.family
        parameter_size = $visionLock.parameter_size
        quantization_level = $visionLock.quantization_level
    }
}
$visionShow = [pscustomobject]@{
    details = $visionTagModel.details
    capabilities = @($visionLock.required_capabilities)
}
$visionVerified = Assert-IrisOllamaModelIdentityData -Lock $visionLock -TagModel $visionTagModel -Show $visionShow
if (-not $visionVerified.GeneralVisionVerified) {
    throw "The Qwen visual lock must remain release-verified for general vision."
}

$badDigest = $tagModel.PSObject.Copy()
$badDigest.digest = "0" * 64
try {
    Assert-IrisOllamaModelIdentityData -Lock $lock -TagModel $badDigest -Show $show | Out-Null
    throw "Digest mismatch fixture unexpectedly passed."
} catch {
    if (-not $_.Exception.Message.Contains("digest mismatch")) { throw }
}

$badShow = $show.PSObject.Copy()
$badShow.capabilities = @($lock.required_capabilities | Where-Object { $_ -ne "vision" })
try {
    Assert-IrisOllamaModelIdentityData -Lock $lock -TagModel $tagModel -Show $badShow | Out-Null
    throw "Capability mismatch fixture unexpectedly passed."
} catch {
    if (-not $_.Exception.Message.Contains("missing locked capabilities")) { throw }
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-model-store-test-" + [guid]::NewGuid().ToString("N"))
$storeRoot = Join-Path $fixtureRoot "wrong-first"
$secondStoreRoot = Join-Path $fixtureRoot "correct-second"
$previousDataRoot = $env:IRIS_DATA_ROOT
$env:IRIS_DATA_ROOT = Join-Path $fixtureRoot "iris-data"
try {
    $fixtureLock = $lock.PSObject.Copy()
    $configBytes = [System.Text.Encoding]::UTF8.GetBytes("config")
    $modelBytes = [System.Text.Encoding]::UTF8.GetBytes("locked model")
    $configDigest = "sha256:" + (Get-TestSha256Hex -Bytes $configBytes)
    $modelDigest = "sha256:" + (Get-TestSha256Hex -Bytes $modelBytes)
    $fixtureManifest = [ordered]@{
        config = [ordered]@{
            mediaType = "application/vnd.docker.container.image.v1+json"
            digest = $configDigest
            size = $configBytes.Length
        }
        layers = @([ordered]@{
            mediaType = "application/vnd.ollama.image.model"
            digest = $modelDigest
            size = $modelBytes.Length
        })
    } | ConvertTo-Json -Depth 5 -Compress
    $fixtureLock.model_layer_digest = $modelDigest
    $fixtureLock.total_bytes = [long]($configBytes.Length + $modelBytes.Length)
    foreach ($candidateRoot in @($storeRoot, $secondStoreRoot)) {
        $candidateManifest = Get-IrisOllamaModelManifestPath -ModelsRoot $candidateRoot -ModelId ([string]$fixtureLock.model_id)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $candidateManifest) | Out-Null
        [System.IO.File]::WriteAllText($candidateManifest, $fixtureManifest, [System.Text.UTF8Encoding]::new($false))
        $candidateBlobRoot = Join-Path $candidateRoot "blobs"
        New-Item -ItemType Directory -Force -Path $candidateBlobRoot | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $candidateBlobRoot $configDigest.Replace(":", "-")), $configBytes)
        [System.IO.File]::WriteAllBytes((Join-Path $candidateBlobRoot $modelDigest.Replace(":", "-")), $modelBytes)
    }
    $fixturePath = Get-IrisOllamaModelManifestPath -ModelsRoot $storeRoot -ModelId ([string]$fixtureLock.model_id)
    $fixtureLock.manifest_digest = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $modelBlob = Join-Path (Join-Path $storeRoot "blobs") $modelDigest.Replace(":", "-")
    $coldVerification = Get-IrisOllamaModelStoreVerification -ModelsRoot $storeRoot -Lock $fixtureLock
    if ($null -eq $coldVerification -or $coldVerification.CacheHit) {
        throw "Exact Ollama model-store manifest fixture was rejected."
    }
    $warmVerification = Get-IrisOllamaModelStoreVerification -ModelsRoot $storeRoot -Lock $fixtureLock
    if ($null -eq $warmVerification -or -not $warmVerification.CacheHit) {
        throw "Unchanged exact model store did not use its compact verification cache."
    }
    $preferredSelection = Find-IrisOllamaModelStore -Candidates @($secondStoreRoot, $storeRoot) -Lock $fixtureLock
    if ($null -eq $preferredSelection -or
        [System.IO.Path]::GetFullPath([string]$preferredSelection.ModelsRoot) -cne [System.IO.Path]::GetFullPath($secondStoreRoot)) {
        throw "Persistent model-store cache unexpectedly outranked the preferred exact candidate."
    }
    [byte[]]$sameSizeCorruption = $modelBytes.Clone()
    $sameSizeCorruption[0] = $sameSizeCorruption[0] -bxor 1
    [System.IO.File]::WriteAllBytes($modelBlob, $sameSizeCorruption)
    [System.IO.File]::SetLastWriteTimeUtc($modelBlob, [DateTime]::UtcNow.AddSeconds(2))
    if (Test-IrisOllamaModelStore -ModelsRoot $storeRoot -Lock $fixtureLock) {
        throw "Same-size corruption unexpectedly passed through a stale verification cache."
    }
    [System.IO.File]::WriteAllBytes($modelBlob, $modelBytes)
    Get-IrisOllamaModelStoreVerification -ModelsRoot $storeRoot -Lock $fixtureLock | Out-Null
    Remove-Item -LiteralPath (Get-IrisOllamaModelStoreCachePath) -Force
    [System.IO.File]::WriteAllBytes($modelBlob, $sameSizeCorruption)
    if (Test-IrisOllamaModelStore -ModelsRoot $storeRoot -Lock $fixtureLock) {
        throw "Same-size corrupt Ollama model blob unexpectedly passed."
    }
    $selected = Find-IrisOllamaModelStore -Candidates @($storeRoot, $secondStoreRoot) -Lock $fixtureLock
    if ($null -eq $selected -or
        [System.IO.Path]::GetFullPath([string]$selected.ModelsRoot) -cne [System.IO.Path]::GetFullPath($secondStoreRoot)) {
        throw "Model-store selection did not skip a same-size corrupt first store for the exact second store."
    }
    $selectedModelBlob = Join-Path (Join-Path $secondStoreRoot "blobs") $modelDigest.Replace(":", "-")
    $sourceShow = [pscustomobject]@{
        modelfile = @"
# Modelfile generated by ollama show
# FROM $($fixtureLock.model_id)

FROM $selectedModelBlob
LICENSE """
FROM inside license text
"""
"@
    }
    Assert-IrisOllamaModelSource -Lock $fixtureLock -Show $sourceShow -ModelsRoot $secondStoreRoot
    $wrongRootShow = [pscustomobject]@{
        modelfile = "FROM " + (Join-Path (Join-Path (Join-Path $fixtureRoot "different-store") "blobs") $modelDigest.Replace(":", "-"))
    }
    try {
        Assert-IrisOllamaModelSource -Lock $fixtureLock -Show $wrongRootShow -ModelsRoot $secondStoreRoot
        throw "A model source under a different store unexpectedly passed."
    } catch {
        if (-not $_.Exception.Message.Contains("differs from Iris")) { throw }
    }
    $ambiguousShow = [pscustomobject]@{
        modelfile = "FROM $selectedModelBlob`nFROM $selectedModelBlob"
    }
    try {
        Assert-IrisOllamaModelSource -Lock $fixtureLock -Show $ambiguousShow -ModelsRoot $secondStoreRoot
        throw "Multiple active Modelfile FROM sources unexpectedly passed."
    } catch {
        if (-not $_.Exception.Message.Contains("more than one active FROM")) { throw }
    }
    $missingSourceShow = [pscustomobject]@{ modelfile = "# FROM commented-only" }
    try {
        Assert-IrisOllamaModelSource -Lock $fixtureLock -Show $missingSourceShow -ModelsRoot $secondStoreRoot
        throw "A Modelfile without an active FROM source unexpectedly passed."
    } catch {
        if (-not $_.Exception.Message.Contains("did not report an active FROM")) { throw }
    }
    $previousAttestation = $env:IRIS_OLLAMA_MODEL_STORE_ATTESTATION_V1
    try {
        Set-IrisOllamaModelStoreAttestation -Verification $selected -Lock $fixtureLock
        $attestation = $env:IRIS_OLLAMA_MODEL_STORE_ATTESTATION_V1 | ConvertFrom-Json
        if ([string]$attestation.models_root -cne [System.IO.Path]::GetFullPath($secondStoreRoot) -or
            @($attestation.descriptors).Count -ne 2) {
            throw "Model-store child-process attestation was not exact."
        }
    } finally {
        if ($null -eq $previousAttestation) {
            Remove-Item Env:IRIS_OLLAMA_MODEL_STORE_ATTESTATION_V1 -ErrorAction SilentlyContinue
        } else {
            $env:IRIS_OLLAMA_MODEL_STORE_ATTESTATION_V1 = $previousAttestation
        }
    }
    $secondModelBlob = Join-Path (Join-Path $secondStoreRoot "blobs") $modelDigest.Replace(":", "-")
    Remove-Item -LiteralPath $secondModelBlob -Force
    if (Test-IrisOllamaModelStore -ModelsRoot $secondStoreRoot -Lock $fixtureLock) {
        throw "Incomplete Ollama model-store fixture unexpectedly passed."
    }
    [System.IO.File]::WriteAllBytes($secondModelBlob, $modelBytes)
    $secondFixturePath = Get-IrisOllamaModelManifestPath -ModelsRoot $secondStoreRoot -ModelId ([string]$fixtureLock.model_id)
    [System.IO.File]::AppendAllText($secondFixturePath, "drift", [System.Text.Encoding]::UTF8)
    if (Test-IrisOllamaModelStore -ModelsRoot $secondStoreRoot -Lock $fixtureLock) {
        throw "Repointed Ollama model-store manifest fixture unexpectedly passed."
    }
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
    if ($null -eq $previousDataRoot) {
        Remove-Item Env:IRIS_DATA_ROOT -ErrorAction SilentlyContinue
    } else {
        $env:IRIS_DATA_ROOT = $previousDataRoot
    }
}

if ($Live) {
    $liveIdentity = Assert-IrisOllamaModelIdentity -Root $repoRoot -Role Primary
    $liveVisionIdentity = Assert-IrisOllamaModelIdentity -Root $repoRoot -Role Vision
    Write-Host "Live Ollama identity verified: $($liveIdentity.ModelId)@$($liveIdentity.ManifestDigest)"
    Write-Host "Live Ollama vision identity verified: $($liveVisionIdentity.ModelId)@$($liveVisionIdentity.ManifestDigest)"
}

Write-Host "Iris Ollama model lock tests passed."
