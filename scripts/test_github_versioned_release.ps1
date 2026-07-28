param(
    [string]$Repo = "supermang617/IRIS",
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$ExpectedCommit = "",
    [switch]$RequireSignedMsix,
    [switch]$RequireWingetBundle,
    [switch]$DownloadPayloads
)

$ErrorActionPreference = "Stop"

if ($Tag -notmatch "^v(?<version>[0-9]+\.[0-9]+\.[0-9]+)$") {
    throw "Versioned release verification requires an immutable semantic tag such as v1.0.1."
}
$packageVersion = $Matches.version

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$Name is required to verify the GitHub release."
    }
    return $command.Source
}

function Read-HashFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $text = (Get-Content -LiteralPath $Path -Raw).Trim()
    if ($text -notmatch "^[a-fA-F0-9]{64}\s+\S+$") {
        throw "Invalid SHA256 file format: $Path"
    }
    $parts = $text -split "\s+", 2
    [pscustomobject]@{
        Hash = $parts[0].ToLowerInvariant()
        FileName = $parts[1]
    }
}

$gh = Require-Command -Name "gh"
$git = Require-Command -Name "git"
$expectedAssets = New-Object System.Collections.Generic.List[string]
foreach ($name in @(
        "install-iris-windows.ps1",
        "install-iris-windows.ps1.sha256",
        "iris-windows-installer.zip",
        "iris-windows-installer.zip.sha256",
        "iris-windows.zip",
        "iris-windows.zip.sha256"
    )) {
    $expectedAssets.Add($name)
}
if ($RequireSignedMsix) {
    foreach ($name in @(
            "iris-windows.msix",
            "iris-windows.msix.sha256",
            "iris-msix-signing.cer",
            "iris-msix-signing.cer.sha256"
        )) {
        $expectedAssets.Add($name)
    }
}
if ($RequireWingetBundle) {
    $expectedAssets.Add("iris-winget-manifests.zip")
    $expectedAssets.Add("iris-winget-manifests.zip.sha256")
}

$releaseJson = & $gh release view $Tag --repo $Repo --json tagName,targetCommitish,isDraft,isPrerelease,url,assets
if ($LASTEXITCODE -ne 0) {
    throw "GitHub release $Repo/$Tag was not readable."
}
$release = $releaseJson | ConvertFrom-Json
if ($release.tagName -ne $Tag -or $release.isDraft -or $release.isPrerelease) {
    throw "$Tag must be a normal public release with the exact requested tag."
}

$remoteRef = & $git ls-remote "https://github.com/$Repo.git" "refs/tags/$Tag" "refs/tags/$Tag^{}"
if ($LASTEXITCODE -ne 0 -or -not $remoteRef) {
    throw "Could not resolve remote release tag $Tag."
}
$remoteCommit = ""
foreach ($line in @($remoteRef)) {
    $parts = $line -split "\s+"
    if ($parts.Count -lt 2) {
        continue
    }
    if ($parts[1] -eq "refs/tags/$Tag^{}" -or -not $remoteCommit) {
        $remoteCommit = $parts[0].ToLowerInvariant()
    }
}
if ($ExpectedCommit -and $remoteCommit -ne $ExpectedCommit.Trim().ToLowerInvariant()) {
    throw "$Tag commit mismatch. Expected $ExpectedCommit but got $remoteCommit."
}

$actualNames = @($release.assets | ForEach-Object name | Sort-Object)
$expectedNames = @($expectedAssets | Sort-Object)
if ($actualNames.Count -ne $expectedNames.Count -or
    (Compare-Object -ReferenceObject $expectedNames -DifferenceObject $actualNames)) {
    throw "$Tag assets mismatch. Expected: $($expectedNames -join ', '). Actual: $($actualNames -join ', ')."
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-github-release-" + [System.Guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    & $gh release download $Tag --repo $Repo --pattern "*.sha256" --dir $testRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Could not download release SHA256 files."
    }

    $payloadNames = @(
        "install-iris-windows.ps1",
        "iris-windows-installer.zip",
        "iris-windows.zip"
    )
    if ($RequireSignedMsix) {
        $payloadNames += @("iris-windows.msix", "iris-msix-signing.cer")
    }
    if ($RequireWingetBundle) {
        $payloadNames += "iris-winget-manifests.zip"
    }

    foreach ($payload in $payloadNames) {
        $sha = Read-HashFile -Path (Join-Path $testRoot "$payload.sha256")
        if ($sha.FileName -ne $payload) {
            throw "$payload.sha256 names '$($sha.FileName)' instead of '$payload'."
        }
        if ($DownloadPayloads -or $payload -in @("iris-windows.msix", "iris-winget-manifests.zip")) {
            & $gh release download $Tag --repo $Repo --pattern $payload --dir $testRoot --clobber
            if ($LASTEXITCODE -ne 0) {
                throw "Could not download release asset: $payload"
            }
            $actual = (Get-FileHash -LiteralPath (Join-Path $testRoot $payload) -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $sha.Hash) {
                throw "$payload SHA256 mismatch. Expected $($sha.Hash) but got $actual."
            }
        }
    }

    if ($RequireSignedMsix) {
        $msix = Join-Path $testRoot "iris-windows.msix"
        $signature = Get-AuthenticodeSignature -LiteralPath $msix
        if (-not $signature.SignerCertificate -or $signature.Status -ne "Valid") {
            throw "Published MSIX does not have a valid trusted signature: $($signature.Status)"
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($msix)
        try {
            $entry = $archive.GetEntry("AppxManifest.xml")
            if (-not $entry) {
                throw "Published MSIX is missing AppxManifest.xml."
            }
            $reader = New-Object System.IO.StreamReader($entry.Open())
            try {
                [xml]$manifest = $reader.ReadToEnd()
            } finally {
                $reader.Dispose()
            }
            if ([string]$manifest.Package.Identity.Version -ne "$packageVersion.0") {
                throw "Published MSIX version does not match $Tag."
            }
        } finally {
            $archive.Dispose()
        }
    }

    if ($RequireWingetBundle) {
        $manifestExtract = Join-Path $testRoot "winget"
        Expand-Archive -LiteralPath (Join-Path $testRoot "iris-winget-manifests.zip") -DestinationPath $manifestExtract -Force
        $manifestRoot = Join-Path $manifestExtract "a\AlejandroPinto\Iris\$packageVersion"
        & winget.exe validate --manifest $manifestRoot --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            throw "Published WinGet manifest bundle failed validation."
        }
    }

    Write-Host "GitHub Iris versioned release verification passed."
    Write-Host "Release: $($release.url)"
    Write-Host "Commit: $remoteCommit"
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [System.IO.Path]::GetFullPath($testRoot)
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove release test directory outside temp: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
