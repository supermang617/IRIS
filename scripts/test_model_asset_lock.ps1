param(
    [string]$LockPath = "",
    [string]$ModelRoot = "",
    [string]$BootstrapZipPath = "",
    [switch]$RequireAssets
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
if (-not $LockPath) {
    $LockPath = Join-Path $repoRoot "profiles\iris_model_assets.lock.json"
}
if (-not $ModelRoot) {
    $ModelRoot = $repoRoot
}

function Assert-ExactProperties {
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

function Assert-LowerSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($Value -cnotmatch "^[a-f0-9]{64}$") {
        throw "$Context must be a lowercase SHA256 digest."
    }
}

function Assert-PositiveSize {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $size = 0L
    if (-not [long]::TryParse([string]$Value, [ref]$size) -or $size -le 0) {
        throw "$Context must be a positive integer byte count."
    }
    return $size
}

function Get-RelativeAssetPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if (
        [System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains("\") -or
        @($RelativePath.Split("/")) -contains ".."
    ) {
        throw "Unsafe locked model path: $RelativePath"
    }
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $relativeNative = $RelativePath.Replace("/", [System.IO.Path]::DirectorySeparatorChar)
    $assetFull = [System.IO.Path]::GetFullPath((Join-Path $rootFull $relativeNative))
    if (-not $assetFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Locked model path escaped its root: $RelativePath"
    }
    return $assetFull
}

if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
    throw "Model asset lock is missing: $LockPath"
}
$lock = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json
Assert-ExactProperties -Value $lock -Expected @("schema_version", "bootstrap", "models") -Context "Model lock"
if ([int]$lock.schema_version -ne 1) {
    throw "Unsupported model asset lock schema: $($lock.schema_version)"
}

Assert-ExactProperties `
    -Value $lock.bootstrap `
    -Expected @("repository", "tag", "release_commit", "legacy_only", "asset") `
    -Context "Bootstrap"
if (
    [string]$lock.bootstrap.repository -ne "supermang617/IRIS" -or
    [string]$lock.bootstrap.tag -ne "v1" -or
    [string]$lock.bootstrap.release_commit -cnotmatch "^[a-f0-9]{40}$" -or
    $lock.bootstrap.legacy_only -ne $true
) {
    throw "The bootstrap must identify the exact legacy IRIS v1 release and commit."
}

Assert-ExactProperties -Value $lock.bootstrap.asset -Expected @("name", "size", "sha256") -Context "Bootstrap asset"
if ([string]$lock.bootstrap.asset.name -ne "iris-windows.zip") {
    throw "The legacy bootstrap asset must be iris-windows.zip."
}
$bootstrapSize = Assert-PositiveSize -Value $lock.bootstrap.asset.size -Context "Bootstrap asset size"
$bootstrapSha256 = [string]$lock.bootstrap.asset.sha256
Assert-LowerSha256 -Value $bootstrapSha256 -Context "Bootstrap asset hash"

$expectedModels = [ordered]@{
    "models/kokoro/kokoro-v1.0.onnx" = "text_to_speech_model"
    "models/kokoro/voices-v1.0.bin" = "text_to_speech_voices"
    "models/whisper/ggml-tiny.en.bin" = "speech_to_text_model"
}
$models = @($lock.models)
if ($models.Count -ne $expectedModels.Count) {
    throw "Model asset lock must contain exactly $($expectedModels.Count) model files."
}

$lockedModels = @{}
foreach ($model in $models) {
    Assert-ExactProperties -Value $model -Expected @("path", "size", "sha256", "role") -Context "Model asset"
    $path = [string]$model.path
    if (-not $expectedModels.Contains($path)) {
        throw "Unexpected model asset path: $path"
    }
    if ($lockedModels.ContainsKey($path)) {
        throw "Duplicate model asset path: $path"
    }
    if ([string]$model.role -ne $expectedModels[$path]) {
        throw "Unexpected role for $path`: $($model.role)"
    }
    $size = Assert-PositiveSize -Value $model.size -Context "$path size"
    $sha256 = [string]$model.sha256
    Assert-LowerSha256 -Value $sha256 -Context "$path hash"
    $lockedModels[$path] = [pscustomobject]@{
        Path = $path
        Size = $size
        Sha256 = $sha256
    }
}

if ($BootstrapZipPath) {
    if (-not (Test-Path -LiteralPath $BootstrapZipPath -PathType Leaf)) {
        throw "Legacy bootstrap ZIP is missing: $BootstrapZipPath"
    }
    $zipItem = Get-Item -LiteralPath $BootstrapZipPath
    if ([long]$zipItem.Length -ne $bootstrapSize) {
        throw "Legacy bootstrap ZIP size mismatch: expected $bootstrapSize, found $($zipItem.Length)"
    }
    $zipSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipItem.FullName).Hash.ToLowerInvariant()
    if ($zipSha256 -ne $bootstrapSha256) {
        throw "Legacy bootstrap ZIP hash mismatch: expected $bootstrapSha256, found $zipSha256"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipItem.FullName)
    try {
        $zipModelEntries = @{}
        foreach ($entry in $zip.Entries) {
            $entryPath = $entry.FullName.Replace("\", "/")
            if (
                $entryPath.StartsWith("/") -or
                $entryPath -match "^[A-Za-z]:" -or
                @($entryPath.Split("/")) -contains ".."
            ) {
                throw "Legacy bootstrap ZIP contains an unsafe entry: $($entry.FullName)"
            }
            if ($entry.Length -eq 0 -and $entryPath.EndsWith("/")) {
                continue
            }
            if ($entryPath.StartsWith("models/", [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not $lockedModels.ContainsKey($entryPath)) {
                    throw "Legacy bootstrap ZIP contains an unexpected model file: $entryPath"
                }
                if ($zipModelEntries.ContainsKey($entryPath)) {
                    throw "Legacy bootstrap ZIP contains a duplicate model file: $entryPath"
                }
                $zipModelEntries[$entryPath] = $entry
            }
        }
        foreach ($path in $lockedModels.Keys) {
            if (-not $zipModelEntries.ContainsKey($path)) {
                throw "Legacy bootstrap ZIP is missing locked model file: $path"
            }
            $expected = $lockedModels[$path]
            $entry = $zipModelEntries[$path]
            if ([long]$entry.Length -ne $expected.Size) {
                throw "$path size mismatch inside legacy bootstrap ZIP."
            }
            $stream = $entry.Open()
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $actualHash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
            } finally {
                $sha.Dispose()
                $stream.Dispose()
            }
            if ($actualHash -ne $expected.Sha256) {
                throw "$path hash mismatch inside legacy bootstrap ZIP."
            }
        }
    } finally {
        $zip.Dispose()
    }
}

$modelRootFull = [System.IO.Path]::GetFullPath($ModelRoot)
$modelsDirectory = Join-Path $modelRootFull "models"
$presentCount = 0
foreach ($path in $lockedModels.Keys) {
    $candidate = Get-RelativeAssetPath -Root $modelRootFull -RelativePath $path
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $presentCount++
    }
}
if ($RequireAssets -or $presentCount -gt 0 -or (Test-Path -LiteralPath $modelsDirectory)) {
    if ($presentCount -ne $lockedModels.Count) {
        throw "Model root contains a partial locked model set: $modelRootFull"
    }
    $actualPaths = @(
        Get-ChildItem -LiteralPath $modelsDirectory -Recurse -File |
            ForEach-Object {
                $_.FullName.Substring($modelRootFull.TrimEnd("\").Length + 1).Replace("\", "/")
            }
    )
    if (
        $actualPaths.Count -ne $lockedModels.Count -or
        @($actualPaths | Where-Object { -not $lockedModels.ContainsKey($_) }).Count -gt 0
    ) {
        throw "Model root must contain only the exact locked model files."
    }
    foreach ($path in $lockedModels.Keys) {
        $expected = $lockedModels[$path]
        $candidate = Get-RelativeAssetPath -Root $modelRootFull -RelativePath $path
        $item = Get-Item -LiteralPath $candidate
        if ([long]$item.Length -ne $expected.Size) {
            throw "$path size mismatch: expected $($expected.Size), found $($item.Length)"
        }
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidate).Hash.ToLowerInvariant()
        if ($actualHash -ne $expected.Sha256) {
            throw "$path hash mismatch: expected $($expected.Sha256), found $actualHash"
        }
    }
}

Write-Output "Model asset lock is valid ($($lockedModels.Count) exact files; legacy bootstrap $bootstrapSha256)."
