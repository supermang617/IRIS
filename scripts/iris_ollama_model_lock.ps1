$ErrorActionPreference = "Stop"

function Assert-IrisOllamaLockExactProperties {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $actual = @($Value.PSObject.Properties.Name | Sort-Object)
    $expectedSorted = @($Expected | Sort-Object)
    if (($actual -join "`n") -cne ($expectedSorted -join "`n")) {
        throw "$Context properties differ from the locked schema. Expected: $($expectedSorted -join ', '); found: $($actual -join ', ')"
    }
}

function Get-IrisOllamaModelLock {
    param([Parameter(Mandatory = $true)][string]$Root)

    $lockPath = Join-Path ([System.IO.Path]::GetFullPath($Root)) "profiles\iris_ollama_model.lock.json"
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        throw "Iris Ollama model lock is missing: $lockPath"
    }
    $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
    Assert-IrisOllamaLockExactProperties `
        -Value $lock `
        -Expected @(
            "schema_version", "provider", "model_id", "manifest_digest",
            "model_layer_digest", "total_bytes", "family", "parameter_size",
            "quantization_level", "required_capabilities", "general_vision_verified"
        ) `
        -Context "Iris Ollama model lock"
    if ([int]$lock.schema_version -ne 1 -or [string]$lock.provider -cne "ollama_local") {
        throw "Unsupported Iris Ollama model lock schema or provider."
    }
    if ([string]$lock.manifest_digest -cnotmatch "^[a-f0-9]{64}$") {
        throw "Iris Ollama manifest digest must be a lowercase SHA256 digest."
    }
    if ([string]$lock.model_layer_digest -cnotmatch "^sha256:[a-f0-9]{64}$") {
        throw "Iris Ollama model-layer digest must be a sha256-prefixed lowercase digest."
    }
    $totalBytes = 0L
    if (-not [long]::TryParse([string]$lock.total_bytes, [ref]$totalBytes) -or $totalBytes -le 0) {
        throw "Iris Ollama total byte count must be a positive integer."
    }
    foreach ($field in @("model_id", "family", "parameter_size", "quantization_level")) {
        if ([string]::IsNullOrWhiteSpace([string]$lock.$field)) {
            throw "Iris Ollama model lock field '$field' must not be empty."
        }
    }
    $capabilities = @($lock.required_capabilities)
    if ($capabilities.Count -eq 0 -or @($capabilities | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        throw "Iris Ollama required capabilities must be a non-empty string list."
    }
    if (@($capabilities | Sort-Object -Unique).Count -ne $capabilities.Count) {
        throw "Iris Ollama required capabilities must not contain duplicates."
    }
    if ($lock.general_vision_verified -isnot [bool]) {
        throw "Iris Ollama general_vision_verified must be a Boolean."
    }

    $manifestPath = Join-Path ([System.IO.Path]::GetFullPath($Root)) "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Iris manifest is missing: $manifestPath"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.model_policy.provider -cne [string]$lock.provider -or
        [string]$manifest.model_policy.model_id -cne [string]$lock.model_id -or
        [string]$manifest.model_policy.architecture -cne [string]$lock.family -or
        [string]$manifest.model_policy.parameter_size -cne [string]$lock.parameter_size) {
        throw "manifest.json model policy differs from profiles/iris_ollama_model.lock.json."
    }
    return $lock
}

function Assert-IrisOllamaModelIdentityData {
    param(
        [Parameter(Mandatory = $true)]$Lock,
        [Parameter(Mandatory = $true)]$TagModel,
        [Parameter(Mandatory = $true)]$Show
    )

    if ([string]$TagModel.name -cne [string]$Lock.model_id -and
        [string]$TagModel.model -cne [string]$Lock.model_id) {
        throw "Ollama returned a different model identity than Iris requested."
    }
    if ([string]$TagModel.digest -cne [string]$Lock.manifest_digest) {
        throw "Configured Ollama model digest mismatch. Expected $($Lock.manifest_digest); found $($TagModel.digest). Run 'ollama pull $($Lock.model_id)' once to repair local corruption. If the mismatch remains, install an Iris release with a newly audited model lock; do not bypass this check."
    }
    if ([int64]$TagModel.size -ne [int64]$Lock.total_bytes) {
        throw "Configured Ollama model byte count mismatch. Expected $($Lock.total_bytes); found $($TagModel.size)."
    }
    foreach ($source in @(
            @{ Name = "/api/tags"; Details = $TagModel.details },
            @{ Name = "/api/show"; Details = $Show.details }
        )) {
        if ([string]$source.Details.family -cne [string]$Lock.family -or
            [string]$source.Details.parameter_size -cne [string]$Lock.parameter_size -or
            [string]$source.Details.quantization_level -cne [string]$Lock.quantization_level) {
            throw "Configured Ollama model metadata from $($source.Name) differs from the Iris lock."
        }
    }
    $actualCapabilities = @($Show.capabilities | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $missing = @($Lock.required_capabilities | Where-Object { $actualCapabilities -cnotcontains [string]$_ })
    if ($missing.Count -gt 0) {
        throw "Configured Ollama model is missing locked capabilities: $($missing -join ', ')."
    }
    return [pscustomobject]@{
        ModelId = [string]$Lock.model_id
        ManifestDigest = [string]$Lock.manifest_digest
        Family = [string]$Lock.family
        QuantizationLevel = [string]$Lock.quantization_level
        Capabilities = $actualCapabilities
        GeneralVisionVerified = [bool]$Lock.general_vision_verified
    }
}

function Get-IrisOllamaModelfileSource {
    param([Parameter(Mandatory = $true)]$Show)

    $modelfile = [string]$Show.modelfile
    if ([string]::IsNullOrWhiteSpace($modelfile)) {
        throw "Ollama /api/show did not report a Modelfile."
    }
    $source = $null
    $inMultilineValue = $false
    foreach ($rawLine in @($modelfile -split "`r?`n")) {
        $line = ([string]$rawLine).Trim()
        $isComment = (-not $inMultilineValue) -and $line.StartsWith("#", [StringComparison]::Ordinal)
        if (-not $inMultilineValue -and -not $isComment -and $line.Length -gt 0) {
            $directiveEnd = 0
            while ($directiveEnd -lt $line.Length -and -not [char]::IsWhiteSpace($line[$directiveEnd])) {
                $directiveEnd++
            }
            $directive = $line.Substring(0, $directiveEnd)
            if ($directive.Equals("FROM", [StringComparison]::OrdinalIgnoreCase)) {
                if ($null -ne $source) {
                    throw "Ollama /api/show returned more than one active FROM source."
                }
                $value = $line.Substring($directiveEnd).Trim()
                if ($value.StartsWith('"') -or $value.EndsWith('"')) {
                    if ($value.Length -lt 2 -or -not ($value.StartsWith('"') -and $value.EndsWith('"'))) {
                        throw "Ollama /api/show returned a malformed FROM source."
                    }
                    $value = $value.Substring(1, $value.Length - 2)
                }
                if ([string]::IsNullOrWhiteSpace($value) -or $value.Contains([char]0)) {
                    throw "Ollama /api/show returned an empty FROM source."
                }
                $source = $value
            }
        }
        if (-not $isComment -and (([regex]::Matches($line, '"""')).Count % 2) -eq 1) {
            $inMultilineValue = -not $inMultilineValue
        }
    }
    if ($inMultilineValue) {
        throw "Ollama /api/show returned an unterminated multiline value."
    }
    if ($null -eq $source) {
        throw "Ollama /api/show did not report an active FROM source."
    }
    return [string]$source
}

function Assert-IrisOllamaModelSource {
    param(
        [Parameter(Mandatory = $true)]$Lock,
        [Parameter(Mandatory = $true)]$Show,
        [Parameter(Mandatory = $true)][string]$ModelsRoot
    )

    if ([string]::IsNullOrWhiteSpace($ModelsRoot) -or -not [System.IO.Path]::IsPathRooted($ModelsRoot)) {
        throw "Iris verified Ollama model-store root must be an absolute path."
    }
    $source = Get-IrisOllamaModelfileSource -Show $Show
    if (-not [System.IO.Path]::IsPathRooted($source)) {
        throw "Ollama /api/show model source must be an absolute path."
    }
    $expectedLeaf = ([string]$Lock.model_layer_digest).Replace(":", "-")
    $expected = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $ModelsRoot "blobs") $expectedLeaf))
    $actual = [System.IO.Path]::GetFullPath($source)
    if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Ollama /api/show model source differs from Iris's verified model store."
    }
}

function Get-IrisOllamaModelManifestPath {
    param(
        [Parameter(Mandatory = $true)][string]$ModelsRoot,
        [Parameter(Mandatory = $true)][string]$ModelId
    )

    if ($ModelId -cnotmatch '^[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)?:[A-Za-z0-9._-]+$') {
        throw "Iris Ollama model identity is not a safe registry tag."
    }
    $parts = $ModelId.Split(":", 2)
    $nameParts = $parts[0].Split("/", 2)
    $namespace = if ($nameParts.Count -eq 2) { $nameParts[0] } else { "library" }
    $name = if ($nameParts.Count -eq 2) { $nameParts[1] } else { $nameParts[0] }
    return Join-Path ([System.IO.Path]::GetFullPath($ModelsRoot)) `
        (Join-Path "manifests\registry.ollama.ai" (Join-Path $namespace (Join-Path $name $parts[1])))
}

function Get-IrisOllamaModelStoreCachePath {
    if ([string]::IsNullOrWhiteSpace($env:IRIS_DATA_ROOT)) {
        return $null
    }
    return Join-Path ([System.IO.Path]::GetFullPath($env:IRIS_DATA_ROOT)) ".iris-data\cache\ollama-model-store-v1.json"
}

function Get-IrisOllamaModelLockDigest {
    param([Parameter(Mandatory = $true)]$Lock)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Lock | ConvertTo-Json -Depth 5 -Compress))
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Get-IrisOllamaModelStoreCache {
    $cachePath = Get-IrisOllamaModelStoreCachePath
    if ($null -eq $cachePath -or -not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        return $null
    }
    try {
        if ((Get-Item -LiteralPath $cachePath).Length -gt 65536) {
            return $null
        }
        $cache = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
        Assert-IrisOllamaLockExactProperties `
            -Value $cache `
            -Expected @("schema_version", "model_id", "models_root", "lock_digest", "manifest_digest", "verified_at_unix_ms", "descriptors") `
            -Context "Iris Ollama model-store cache"
        if ([int]$cache.schema_version -ne 1 -or [long]$cache.verified_at_unix_ms -le 0) {
            return $null
        }
        foreach ($descriptor in @($cache.descriptors)) {
            Assert-IrisOllamaLockExactProperties `
                -Value $descriptor `
                -Expected @("digest", "size", "last_write_time_utc_ticks", "creation_time_utc_ticks") `
                -Context "Iris Ollama model-store cache descriptor"
        }
        return $cache
    } catch {
        return $null
    }
}

function Save-IrisOllamaModelStoreCache {
    param(
        [Parameter(Mandatory = $true)]$Verification,
        [Parameter(Mandatory = $true)]$Lock
    )

    $cachePath = Get-IrisOllamaModelStoreCachePath
    if ($null -eq $cachePath) {
        return
    }
    $cache = [ordered]@{
        schema_version = 1
        model_id = [string]$Lock.model_id
        models_root = [string]$Verification.ModelsRoot
        lock_digest = Get-IrisOllamaModelLockDigest -Lock $Lock
        manifest_digest = [string]$Verification.ManifestDigest
        verified_at_unix_ms = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        descriptors = @($Verification.Descriptors)
    }
    $cacheDirectory = Split-Path -Parent $cachePath
    $temporaryPath = Join-Path $cacheDirectory ([System.IO.Path]::GetRandomFileName())
    try {
        New-Item -ItemType Directory -Force -Path $cacheDirectory | Out-Null
        $json = $cache | ConvertTo-Json -Depth 5 -Compress
        [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
            [System.IO.File]::Replace($temporaryPath, $cachePath, $null)
        } else {
            [System.IO.File]::Move($temporaryPath, $cachePath)
        }
    } catch {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-IrisOllamaModelStoreVerification {
    param(
        [Parameter(Mandatory = $true)][string]$ModelsRoot,
        [Parameter(Mandatory = $true)]$Lock
    )

    try {
        $manifestPath = Get-IrisOllamaModelManifestPath `
            -ModelsRoot $ModelsRoot `
            -ModelId ([string]$Lock.model_id)
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            return $null
        }
        $actualDigest = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualDigest -cne [string]$Lock.manifest_digest) {
            return $null
        }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $descriptors = @($manifest.config) + @($manifest.layers)
        if ($null -eq $manifest.config -or @($manifest.layers).Count -eq 0) {
            return $null
        }
        $cache = Get-IrisOllamaModelStoreCache
        $cacheValid = $null -ne $cache -and
            [string]$cache.model_id -ceq [string]$Lock.model_id -and
            [string]$cache.models_root -ceq [System.IO.Path]::GetFullPath($ModelsRoot) -and
            [string]$cache.lock_digest -ceq (Get-IrisOllamaModelLockDigest -Lock $Lock) -and
            [string]$cache.manifest_digest -ceq $actualDigest -and
            @($cache.descriptors).Count -eq $descriptors.Count
        $totalBytes = 0L
        $lockedModelLayers = 0
        $verifiedDescriptors = @()
        for ($index = 0; $index -lt $descriptors.Count; $index++) {
            $descriptor = $descriptors[$index]
            $digest = [string]$descriptor.digest
            $size = 0L
            if ($digest -cnotmatch '^sha256:[a-f0-9]{64}$' -or
                -not [long]::TryParse([string]$descriptor.size, [ref]$size) -or
                $size -lt 0 -or
                $totalBytes -gt ([long]::MaxValue - $size)) {
                return $null
            }
            $totalBytes += $size
            if ([string]$descriptor.mediaType -ceq 'application/vnd.ollama.image.model' -and
                $digest -ceq [string]$Lock.model_layer_digest) {
                $lockedModelLayers += 1
            }
            $blobPath = Join-Path ([System.IO.Path]::GetFullPath($ModelsRoot)) `
                (Join-Path 'blobs' ($digest.Replace(':', '-')))
            if (-not (Test-Path -LiteralPath $blobPath -PathType Leaf)) {
                return $null
            }
            $before = Get-Item -LiteralPath $blobPath
            if ($before.Length -ne $size) {
                return $null
            }
            if ($cacheValid) {
                $cachedDescriptor = @($cache.descriptors)[$index]
                $cacheValid = [string]$cachedDescriptor.digest -ceq $digest -and
                    [long]$cachedDescriptor.size -eq $size -and
                    [long]$cachedDescriptor.last_write_time_utc_ticks -eq $before.LastWriteTimeUtc.Ticks -and
                    [long]$cachedDescriptor.creation_time_utc_ticks -eq $before.CreationTimeUtc.Ticks
            }
            $verifiedDescriptors += [pscustomobject][ordered]@{
                digest = $digest
                size = [long]$size
                last_write_time_utc_ticks = [long]$before.LastWriteTimeUtc.Ticks
                creation_time_utc_ticks = [long]$before.CreationTimeUtc.Ticks
            }
        }
        if ($lockedModelLayers -ne 1 -or $totalBytes -ne [long]$Lock.total_bytes) {
            return $null
        }
        $verification = [pscustomobject][ordered]@{
            ModelsRoot = [System.IO.Path]::GetFullPath($ModelsRoot)
            ManifestDigest = $actualDigest
            Descriptors = @($verifiedDescriptors)
            CacheHit = [bool]$cacheValid
        }
        if ($cacheValid) {
            return $verification
        }
        for ($index = 0; $index -lt $descriptors.Count; $index++) {
            $digest = [string]$descriptors[$index].digest
            $blobPath = Join-Path ([System.IO.Path]::GetFullPath($ModelsRoot)) `
                (Join-Path 'blobs' ($digest.Replace(':', '-')))
            $blobDigest = (Get-FileHash -LiteralPath $blobPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $after = Get-Item -LiteralPath $blobPath
            $evidence = $verifiedDescriptors[$index]
            if ($blobDigest -cne $digest.Substring(7) -or
                $after.Length -ne [long]$evidence.size -or
                $after.LastWriteTimeUtc.Ticks -ne [long]$evidence.last_write_time_utc_ticks -or
                $after.CreationTimeUtc.Ticks -ne [long]$evidence.creation_time_utc_ticks) {
                return $null
            }
        }
        Save-IrisOllamaModelStoreCache -Verification $verification -Lock $Lock
        return $verification
    } catch {
        return $null
    }
}

function Test-IrisOllamaModelStore {
    param(
        [Parameter(Mandatory = $true)][string]$ModelsRoot,
        [Parameter(Mandatory = $true)]$Lock
    )

    return $null -ne (Get-IrisOllamaModelStoreVerification -ModelsRoot $ModelsRoot -Lock $Lock)
}

function Find-IrisOllamaModelStore {
    param(
        [Parameter(Mandatory = $true)][string[]]$Candidates,
        [Parameter(Mandatory = $true)]$Lock
    )

    $candidatePaths = @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
            try { [System.IO.Path]::GetFullPath([string]$_) } catch { }
        })
    $cache = Get-IrisOllamaModelStoreCache
    $orderedCandidates = @()
    if ($null -ne $cache) {
        $cachedRoot = [System.IO.Path]::GetFullPath([string]$cache.models_root)
        if (@($candidatePaths | Where-Object { $_ -ieq $cachedRoot }).Count -gt 0) {
            $orderedCandidates += $cachedRoot
        }
    }
    $orderedCandidates += $candidatePaths
    $seen = @{}
    foreach ($candidate in $orderedCandidates) {
        try {
            $fullPath = [System.IO.Path]::GetFullPath([string]$candidate)
        } catch {
            continue
        }
        $key = $fullPath.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }
        $seen[$key] = $true
        $verification = Get-IrisOllamaModelStoreVerification -ModelsRoot $fullPath -Lock $Lock
        if ($null -ne $verification) {
            return $verification
        }
    }
    return $null
}

function Set-IrisOllamaModelStoreAttestation {
    param(
        [Parameter(Mandatory = $true)]$Verification,
        [Parameter(Mandatory = $true)]$Lock
    )

    $attestation = [ordered]@{
        schema_version = 1
        model_id = [string]$Lock.model_id
        models_root = [string]$Verification.ModelsRoot
        lock_digest = Get-IrisOllamaModelLockDigest -Lock $Lock
        manifest_digest = [string]$Verification.ManifestDigest
        verified_at_unix_ms = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        descriptors = @($Verification.Descriptors)
    }
    $env:IRIS_OLLAMA_MODEL_STORE_ATTESTATION_V1 = $attestation | ConvertTo-Json -Depth 5 -Compress
}

function Assert-IrisOllamaModelIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$ModelsRoot = "",
        [int]$TimeoutSeconds = 15
    )

    $lock = Get-IrisOllamaModelLock -Root $Root
    if ([string]::IsNullOrWhiteSpace($ModelsRoot)) {
        $candidates = @("C:\.ollama")
        if (-not [string]::IsNullOrWhiteSpace($env:OLLAMA_MODELS)) {
            $candidates = @($env:OLLAMA_MODELS) + $candidates
        }
        if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
            $candidates += Join-Path $env:USERPROFILE ".ollama\models"
        }
        $verification = Find-IrisOllamaModelStore -Candidates $candidates -Lock $lock
    } else {
        $verification = Get-IrisOllamaModelStoreVerification -ModelsRoot $ModelsRoot -Lock $lock
    }
    if ($null -eq $verification) {
        throw "Iris's digest-verified Ollama model store is unavailable or changed."
    }
    $verifiedModelsRoot = [string]$verification.ModelsRoot
    $tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec $TimeoutSeconds
    $tagModel = @($tags.models | Where-Object {
            [string]$_.name -ceq [string]$lock.model_id -or [string]$_.model -ceq [string]$lock.model_id
        }) | Select-Object -First 1
    if ($null -eq $tagModel) {
        throw "Configured Ollama model is not installed: $($lock.model_id). Run 'ollama pull $($lock.model_id)'."
    }
    $showBody = @{ model = [string]$lock.model_id } | ConvertTo-Json -Compress
    $show = Invoke-RestMethod `
        -Uri "http://127.0.0.1:11434/api/show" `
        -Method Post `
        -ContentType "application/json" `
        -Body $showBody `
        -TimeoutSec $TimeoutSeconds
    $identity = Assert-IrisOllamaModelIdentityData -Lock $lock -TagModel $tagModel -Show $show
    Assert-IrisOllamaModelSource -Lock $lock -Show $show -ModelsRoot $verifiedModelsRoot
    return $identity
}
