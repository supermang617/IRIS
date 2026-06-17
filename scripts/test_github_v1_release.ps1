param(
    [string]$Repo = "supermang617/IRIS",
    [string]$Tag = "v1",
    [string]$ExpectedCommit = "",
    [switch]$DownloadPayloads
)

$ErrorActionPreference = "Stop"

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
Require-Command -Name "git" | Out-Null

$requiredAssets = @(
    "install-iris-windows.ps1",
    "install-iris-windows.ps1.sha256",
    "iris-windows-installer.zip",
    "iris-windows-installer.zip.sha256",
    "iris-windows.zip",
    "iris-windows.zip.sha256"
)

$releaseJson = & $gh release view $Tag --repo $Repo --json tagName,targetCommitish,isDraft,isPrerelease,url,assets
if ($LASTEXITCODE -ne 0) {
    throw "GitHub release $Repo/$Tag was not readable."
}
$release = $releaseJson | ConvertFrom-Json
if ($release.tagName -ne $Tag) {
    throw "Expected release tag $Tag but got $($release.tagName)."
}
if ($release.isDraft -or $release.isPrerelease) {
    throw "$Tag must be a normal public release, not draft or prerelease."
}
if ($ExpectedCommit) {
    $expected = $ExpectedCommit.Trim().ToLowerInvariant()
    if ($release.targetCommitish.ToLowerInvariant() -ne $expected) {
        throw "$Tag release target mismatch. Expected $expected but got $($release.targetCommitish)."
    }
}

$remoteRefs = & git ls-remote "https://github.com/$Repo.git" "refs/heads/main" "refs/tags/$Tag"
if ($LASTEXITCODE -ne 0) {
    throw "Could not read remote refs for $Repo."
}
$remoteMain = ""
$remoteTag = ""
foreach ($line in $remoteRefs) {
    $parts = $line -split "\s+"
    if ($parts.Count -lt 2) {
        continue
    }
    if ($parts[1] -eq "refs/heads/main") {
        $remoteMain = $parts[0].ToLowerInvariant()
    } elseif ($parts[1] -eq "refs/tags/$Tag") {
        $remoteTag = $parts[0].ToLowerInvariant()
    }
}
if (-not $remoteMain -or -not $remoteTag) {
    throw "Remote main and $Tag refs must both exist."
}
if ($remoteMain -ne $remoteTag) {
    throw "Remote main and $Tag must point to the same commit. main=$remoteMain tag=$remoteTag"
}
if ($ExpectedCommit -and $remoteTag -ne $ExpectedCommit.Trim().ToLowerInvariant()) {
    throw "Remote $Tag ref mismatch. Expected $ExpectedCommit but got $remoteTag."
}

$assetNames = @($release.assets | ForEach-Object { $_.name } | Sort-Object)
$requiredSorted = @($requiredAssets | Sort-Object)
if (@($assetNames).Count -ne @($requiredSorted).Count) {
    throw "$Tag must expose exactly $($requiredSorted.Count) release assets. Found: $($assetNames -join ', ')"
}
for ($i = 0; $i -lt $requiredSorted.Count; $i++) {
    if ($assetNames[$i] -ne $requiredSorted[$i]) {
        throw "$Tag release assets mismatch. Expected $($requiredSorted -join ', ') but got $($assetNames -join ', ')"
    }
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-github-v1-release-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    & $gh release download $Tag --repo $Repo --pattern "*.sha256" --dir $tmp
    if ($LASTEXITCODE -ne 0) {
        throw "Could not download release SHA256 files."
    }
    foreach ($shaName in @(
        "install-iris-windows.ps1.sha256",
        "iris-windows-installer.zip.sha256",
        "iris-windows.zip.sha256"
    )) {
        $shaPath = Join-Path $tmp $shaName
        if (-not (Test-Path -LiteralPath $shaPath -PathType Leaf)) {
            throw "Missing downloaded SHA256 asset: $shaName"
        }
        $hash = Read-HashFile -Path $shaPath
        $expectedPayload = $shaName -replace "\.sha256$", ""
        if ($hash.FileName -ne $expectedPayload) {
            throw "$shaName points to $($hash.FileName), expected $expectedPayload."
        }
    }

    if ($DownloadPayloads) {
        foreach ($asset in @(
            "install-iris-windows.ps1",
            "iris-windows-installer.zip",
            "iris-windows.zip"
        )) {
            & $gh release download $Tag --repo $Repo --pattern $asset --dir $tmp --clobber
            if ($LASTEXITCODE -ne 0) {
                throw "Could not download release asset: $asset"
            }
            $sha = Read-HashFile -Path (Join-Path $tmp "$asset.sha256")
            $actual = (Get-FileHash -LiteralPath (Join-Path $tmp $asset) -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $sha.Hash) {
                throw "$asset SHA256 mismatch. Expected $($sha.Hash) but got $actual."
            }
        }
    }

    Write-Host "GitHub Iris $Tag release verification passed."
    Write-Host "Release: $($release.url)"
    Write-Host "Commit: $remoteTag"
    Write-Host "Assets: $($assetNames -join ', ')"
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
