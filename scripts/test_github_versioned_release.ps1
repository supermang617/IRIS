param(
    [string]$Repo = "supermang617/IRIS",
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$ExpectedCommit = "",
    [long]$ExpectedReleaseId = 0,
    [string]$ExpectedAuthor = "",
    [string]$ExpectedName = "",
    [string]$ExpectedBodyPrefix = "",
    [string]$ExpectedPublisher = "",
    [string]$ExpectedSignerThumbprint = "",
    [string]$ExpectedProvenancePath = "",
    [switch]$AllowDraft,
    [switch]$RequireLatest,
    [switch]$RequireSignedMsix,
    [switch]$RequireWingetBundle,
    [switch]$RequireBuildProvenance,
    [switch]$RequireLifecycleEvidence,
    [switch]$RequireWackReport,
    [switch]$RequireWingetClientValidation,
    [switch]$DownloadPayloads,
    [ValidateRange(1, 168)][int]$LifecycleMaximumAgeHours = 168
)

$ErrorActionPreference = "Stop"

if ($Tag -notmatch "^v(?<major>0|[1-9][0-9]*)\.(?<minor>0|[1-9][0-9]*)\.(?<patch>0|[1-9][0-9]*)$") {
    throw "Versioned release verification requires an immutable semantic tag such as v1.0.0."
}
$packageVersion = "$($Matches.major).$($Matches.minor).$($Matches.patch)"
foreach ($component in @($Matches.major, $Matches.minor, $Matches.patch)) {
    if ([uint64]$component -gt 65535) {
        throw "Every release version component must fit the MSIX range 0-65535."
    }
}
if ($RequireWingetClientValidation) {
    $RequireWingetBundle = $true
}
if ($ExpectedProvenancePath) {
    $RequireBuildProvenance = $true
}
if ($RequireBuildProvenance) {
    $RequireWingetBundle = $true
}
if ($RequireWackReport) {
    $RequireLifecycleEvidence = $true
}
if ($RequireWingetBundle -or $RequireLifecycleEvidence) {
    $RequireSignedMsix = $true
}
if ($ExpectedSignerThumbprint) {
    if ($ExpectedSignerThumbprint -notmatch "^[a-fA-F0-9]{40}$") {
        throw "ExpectedSignerThumbprint must contain exactly 40 hexadecimal characters."
    }
    $ExpectedSignerThumbprint = $ExpectedSignerThumbprint.ToLowerInvariant()
    $RequireSignedMsix = $true
}
if ($ExpectedPublisher -match "[\r\n]") {
    throw "ExpectedPublisher must be a single certificate-subject line."
}
if (
    $RequireSignedMsix -and
    (
        -not $ExpectedPublisher.Trim() -or
        -not $ExpectedSignerThumbprint
    )
) {
    throw "Signed release verification requires owner-pinned ExpectedPublisher and ExpectedSignerThumbprint values."
}

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

function Get-VerifiedWackReport {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Published WACK report is missing: $resolved"
    }
    $item = Get-Item -LiteralPath $resolved
    if ($item.Length -le 0 -or $item.Length -gt 32MB) {
        throw "Published WACK report is empty or exceeds the 32 MiB evidence bound."
    }

    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = $null
    try {
        $reader = [System.Xml.XmlReader]::Create($resolved, $settings)
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($reader)
    } catch {
        throw "Published WACK report is not safe, valid XML: $($_.Exception.Message)"
    } finally {
        if ($reader) {
            $reader.Dispose()
        }
    }
    if ([string]$document.REPORT.OVERALL_RESULT -cne "PASS") {
        throw "Published WACK report did not record REPORT.OVERALL_RESULT=PASS."
    }

    return [pscustomobject]@{
        Length = [int64]$item.Length
        Sha256 = (
            Get-FileHash -LiteralPath $resolved -Algorithm SHA256
        ).Hash.ToLowerInvariant()
    }
}

function Read-YamlScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet("Root", "InstallerMember")][string]$Scope = "Root"
    )

    $prefix = if ($Scope -eq "Root") { "^" } else { "^ {4}" }
    $pattern = "(?m)$prefix$([regex]::Escape($Key)):[ \t]*(?<value>[^\r\n#]+?)[ \t]*$"
    $matches = @([regex]::Matches($Text, $pattern))
    if ($matches.Count -ne 1) {
        throw "$Path must contain exactly one scalar '$Key' value."
    }
    return $matches[0].Groups["value"].Value.Trim()
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
if ($RequireBuildProvenance) {
    $expectedAssets.Add("iris-unsigned-build.json")
    $expectedAssets.Add("iris-signed-build.json")
}
if ($RequireLifecycleEvidence) {
    $expectedAssets.Add("iris-msix-lifecycle-evidence.json")
    $expectedAssets.Add("iris-msix-lifecycle-evidence.json.sha256")
}
if ($RequireWackReport) {
    $expectedAssets.Add("iris-windows-wack-report.xml")
    $expectedAssets.Add("iris-windows-wack-report.xml.sha256")
}

$releaseJson = & $gh release view $Tag --repo $Repo --json author,databaseId,tagName,targetCommitish,isDraft,isPrerelease,name,body,url,assets
if ($LASTEXITCODE -ne 0) {
    throw "GitHub release $Repo/$Tag was not readable."
}
$release = $releaseJson | ConvertFrom-Json
if ($release.tagName -ne $Tag -or $release.isPrerelease) {
    throw "$Tag must be a non-prerelease release with the exact requested tag."
}
if ($AllowDraft -and -not $release.isDraft) {
    throw "$Tag must remain a draft until its assets pass verification."
}
if (-not $AllowDraft -and $release.isDraft) {
    throw "$Tag must be a normal public release."
}
if ($ExpectedName -and [string]$release.name -cne $ExpectedName) {
    throw "$Tag title mismatch. Expected '$ExpectedName' but got '$($release.name)'."
}
if ($ExpectedReleaseId -gt 0 -and [long]$release.databaseId -ne $ExpectedReleaseId) {
    throw "$Tag release ID does not match the atomically created draft."
}
if ($ExpectedAuthor -and [string]$release.author.login -cne $ExpectedAuthor) {
    throw "$Tag release author does not match '$ExpectedAuthor'."
}
if ($ExpectedBodyPrefix -and -not ([string]$release.body).StartsWith($ExpectedBodyPrefix, [System.StringComparison]::Ordinal)) {
    throw "$Tag release notes do not start with the required product summary."
}

$releaseApi = $null
for ($attempt = 1; $attempt -le 6; $attempt++) {
    $releaseApiJson = & $gh api "repos/$Repo/releases/tags/$Tag"
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub release API metadata for $Repo/$Tag was not readable."
    }
    $releaseApi = $releaseApiJson | ConvertFrom-Json
    if ($AllowDraft -or $releaseApi.immutable) {
        break
    }
    if ($attempt -lt 6) {
        Start-Sleep -Seconds 2
    }
}
if ([string]$releaseApi.tag_name -cne $Tag) {
    throw "GitHub release API returned the wrong tag for $Tag."
}
if (-not $AllowDraft -and -not $releaseApi.immutable) {
    throw "$Tag is public but GitHub does not report it as immutable."
}
if ($RequireLatest) {
    $latestJson = & $gh api "repos/$Repo/releases/latest"
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub latest-release metadata was not readable."
    }
    $latest = $latestJson | ConvertFrom-Json
    if ([string]$latest.tag_name -cne $Tag) {
        throw "$Tag is not GitHub's Latest release; latest is '$($latest.tag_name)'."
    }
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
    $msixSha256 = ""
    $msixSignatureSha256 = ""
    $msixPublisher = ""
    $msixSignerThumbprint = ""
    $buildProvenance = $null
    $buildProvenancePath = ""
    $unsignedBuildProvenancePath = ""

    if ($RequireBuildProvenance) {
        & $gh release download $Tag `
            --repo $Repo `
            --pattern "iris-unsigned-build.json" `
            --pattern "iris-signed-build.json" `
            --dir $testRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Could not download the protected build provenance."
        }
        $unsignedBuildProvenancePath = Join-Path $testRoot "iris-unsigned-build.json"
        $buildProvenancePath = Join-Path $testRoot "iris-signed-build.json"
        if ($ExpectedProvenancePath) {
            $trustedProvenancePath = [System.IO.Path]::GetFullPath($ExpectedProvenancePath)
            if (-not (Test-Path -LiteralPath $trustedProvenancePath -PathType Leaf)) {
                throw "Expected signed build provenance is missing: $trustedProvenancePath"
            }
            $expectedProvenanceHash = (
                Get-FileHash -LiteralPath $trustedProvenancePath -Algorithm SHA256
            ).Hash.ToLowerInvariant()
            $releaseProvenanceHash = (
                Get-FileHash -LiteralPath $buildProvenancePath -Algorithm SHA256
            ).Hash.ToLowerInvariant()
            if ($releaseProvenanceHash -cne $expectedProvenanceHash) {
                throw "Release provenance does not match the exact protected workflow artifact."
            }
        }
        try {
            $buildProvenance = Get-Content -LiteralPath $buildProvenancePath -Raw | ConvertFrom-Json
        } catch {
            throw "Signed build provenance is not valid JSON: $($_.Exception.Message)"
        }
        if (
            [int]$buildProvenance.schema -ne 3 -or
            [string]$buildProvenance.tag -cne $Tag -or
            [string]$buildProvenance.source_commit -cne $remoteCommit -or
            [string]$buildProvenance.package_version -cne $packageVersion -or
            [string]$buildProvenance.msix_version -cne "$packageVersion.0" -or
            [long]$buildProvenance.workflow_run_id -le 0 -or
            [int]$buildProvenance.workflow_run_attempt -le 0
        ) {
            throw "Signed build provenance does not match the release tag, commit, or version."
        }
        if (
            -not ([string]$buildProvenance.signer_subject).Trim() -or
            [string]$buildProvenance.signer_subject -match "[\r\n]" -or
            [string]$buildProvenance.signer_thumbprint -notmatch "^[a-fA-F0-9]{40}$" -or
            -not ([string]$buildProvenance.timestamp_subject).Trim() -or
            [string]$buildProvenance.timestamp_subject -match "[\r\n]" -or
            [string]$buildProvenance.timestamp_thumbprint -notmatch "^[a-fA-F0-9]{40}$"
        ) {
            throw "Signed build provenance has invalid signer or timestamp metadata."
        }
        if (
            $ExpectedPublisher -and
            [string]$buildProvenance.signer_subject -cne $ExpectedPublisher
        ) {
            throw "Signed build provenance publisher does not match ExpectedPublisher."
        }
        if (
            $ExpectedSignerThumbprint -and
            ([string]$buildProvenance.signer_thumbprint).ToLowerInvariant() -cne
            $ExpectedSignerThumbprint
        ) {
            throw "Signed build provenance signer does not match ExpectedSignerThumbprint."
        }
        $unsignedBuildProvenanceHash = (
            Get-FileHash -LiteralPath $unsignedBuildProvenancePath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        if (
            [string]$buildProvenance.unsigned_build_provenance_sha256 -notmatch
                "^[a-fA-F0-9]{64}$" -or
            $unsignedBuildProvenanceHash -cne
                ([string]$buildProvenance.unsigned_build_provenance_sha256).ToLowerInvariant()
        ) {
            throw "Published unsigned build provenance does not match its protected signed-build binding."
        }
        try {
            $unsignedBuildProvenance = (
                Get-Content -LiteralPath $unsignedBuildProvenancePath -Raw |
                    ConvertFrom-Json
            )
        } catch {
            throw "Unsigned build provenance is not valid JSON: $($_.Exception.Message)"
        }
        if (
            [int]$unsignedBuildProvenance.schema -ne 2 -or
            [string]$unsignedBuildProvenance.tag -cne $Tag -or
            [string]$unsignedBuildProvenance.source_commit -cne $remoteCommit
        ) {
            throw "Unsigned build provenance does not match the release tag and commit."
        }
    }

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
    if ($RequireLifecycleEvidence) {
        $payloadNames += "iris-msix-lifecycle-evidence.json"
    }
    if ($RequireWackReport) {
        $payloadNames += "iris-windows-wack-report.xml"
    }

    foreach ($payload in $payloadNames) {
        $sha = Read-HashFile -Path (Join-Path $testRoot "$payload.sha256")
        if ($sha.FileName -ne $payload) {
            throw "$payload.sha256 names '$($sha.FileName)' instead of '$payload'."
        }
        if (
            $DownloadPayloads -or
            $RequireBuildProvenance -or
            $payload -in @(
                "iris-windows.msix",
                "iris-msix-signing.cer",
                "iris-winget-manifests.zip",
                "iris-msix-lifecycle-evidence.json",
                "iris-windows-wack-report.xml"
            )
        ) {
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

    if ($RequireBuildProvenance) {
        $provenanceFiles = [ordered]@{
            "install-iris-windows.ps1" = "install-iris-windows.ps1"
            "install-iris-windows.ps1.sha256" = "install-iris-windows.ps1.sha256"
            "iris-windows-installer.zip" = "iris-windows-installer.zip"
            "iris-windows-installer.zip.sha256" = "iris-windows-installer.zip.sha256"
            "iris-windows.zip" = "iris-windows.zip"
            "iris-windows.zip.sha256" = "iris-windows.zip.sha256"
            "iris-windows.msix" = "iris-windows.msix"
            "iris-windows.msix.sha256" = "iris-windows.msix.sha256"
            "iris-msix-signing.cer" = "iris-msix-signing.cer"
            "iris-msix-signing.cer.sha256" = "iris-msix-signing.cer.sha256"
            "winget/iris-winget-manifests.zip" = "iris-winget-manifests.zip"
            "winget/iris-winget-manifests.zip.sha256" = "iris-winget-manifests.zip.sha256"
        }
        $provenanceNames = @($buildProvenance.files.PSObject.Properties.Name | Sort-Object)
        if (
            $provenanceNames.Count -ne $provenanceFiles.Count -or
            (Compare-Object `
                -ReferenceObject @($provenanceFiles.Keys | Sort-Object) `
                -DifferenceObject $provenanceNames)
        ) {
            throw "Signed build provenance contains an unexpected release file set."
        }
        if ([string]$buildProvenance.unsigned_build_provenance_sha256 -notmatch "^[a-fA-F0-9]{64}$") {
            throw "Signed build provenance has an invalid unsigned-build binding."
        }
        foreach ($relativePath in $provenanceFiles.Keys) {
            $assetPath = Join-Path $testRoot $provenanceFiles[$relativePath]
            if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
                throw "Provenance-bound release asset is missing: $($provenanceFiles[$relativePath])"
            }
            $expectedHash = [string]$buildProvenance.files.PSObject.Properties[$relativePath].Value
            if ($expectedHash -notmatch "^[a-fA-F0-9]{64}$") {
                throw "Signed build provenance has an invalid hash for $relativePath."
            }
            $actualHash = (
                Get-FileHash -LiteralPath $assetPath -Algorithm SHA256
            ).Hash.ToLowerInvariant()
            if ($actualHash -cne $expectedHash.ToLowerInvariant()) {
                throw "Release asset does not match signed build provenance: $relativePath"
            }
        }
    }

    if ($RequireSignedMsix) {
        $msix = Join-Path $testRoot "iris-windows.msix"
        $msixSha256 = (
            Get-FileHash -LiteralPath $msix -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        $signature = Get-AuthenticodeSignature -LiteralPath $msix
        if (-not $signature.SignerCertificate -or $signature.Status -ne "Valid") {
            throw "Published MSIX does not have a valid trusted signature: $($signature.Status)"
        }
        if (-not $signature.TimeStamperCertificate) {
            throw "Published MSIX does not have a trusted RFC 3161 timestamp."
        }
        $msixSignerThumbprint = (
            [string]$signature.SignerCertificate.Thumbprint
        ).ToLowerInvariant()
        if (
            $ExpectedSignerThumbprint -and
            $msixSignerThumbprint -cne $ExpectedSignerThumbprint
        ) {
            throw "Published MSIX signer does not match ExpectedSignerThumbprint."
        }
        if (
            $RequireBuildProvenance -and
            (
                [string]$signature.SignerCertificate.Subject -cne
                    [string]$buildProvenance.signer_subject -or
                $msixSignerThumbprint -cne
                    ([string]$buildProvenance.signer_thumbprint).ToLowerInvariant() -or
                [string]$signature.TimeStamperCertificate.Subject -cne
                    [string]$buildProvenance.timestamp_subject -or
                ([string]$signature.TimeStamperCertificate.Thumbprint).ToLowerInvariant() -cne
                    ([string]$buildProvenance.timestamp_thumbprint).ToLowerInvariant()
            )
        ) {
            throw "Published MSIX signer or timestamp does not match protected build provenance."
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($msix)
        try {
            $manifestEntry = $archive.GetEntry("AppxManifest.xml")
            $signatureEntry = $archive.GetEntry("AppxSignature.p7x")
            if (-not $manifestEntry) {
                throw "Published MSIX is missing AppxManifest.xml."
            }
            if (-not $signatureEntry) {
                throw "Published MSIX is missing AppxSignature.p7x."
            }
            $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
            try {
                [xml]$manifest = $reader.ReadToEnd()
            } finally {
                $reader.Dispose()
            }
            $identity = $manifest.Package.Identity
            if ([string]$identity.Name -cne "ProjectIris.LocalAssistant") {
                throw "Published MSIX has the wrong package identity."
            }
            if ([string]$identity.ProcessorArchitecture -cne "x64") {
                throw "Published MSIX is not the x64 production package."
            }
            if ([string]$identity.Version -cne "$packageVersion.0") {
                throw "Published MSIX version does not match $Tag."
            }
            if ([string]$identity.Publisher -cne [string]$signature.SignerCertificate.Subject) {
                throw "Published MSIX manifest publisher does not match its signing certificate."
            }
            if ($ExpectedPublisher -and [string]$identity.Publisher -cne $ExpectedPublisher) {
                throw "Published MSIX publisher does not match ExpectedPublisher."
            }
            $applications = @($manifest.Package.Applications.Application)
            if ($applications.Count -ne 1 -or [string]$applications[0].Id -cne "Iris") {
                throw "Published MSIX does not register the expected Iris application identity."
            }
            $msixPublisher = [string]$identity.Publisher
            $signatureStream = $signatureEntry.Open()
            try {
                $sha = [System.Security.Cryptography.SHA256]::Create()
                try {
                    $msixSignatureSha256 = (
                        [System.BitConverter]::ToString($sha.ComputeHash($signatureStream))
                    ).Replace("-", "").ToLowerInvariant()
                } finally {
                    $sha.Dispose()
                }
            } finally {
                $signatureStream.Dispose()
            }
        } finally {
            $archive.Dispose()
        }
        $publishedCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            (Join-Path $testRoot "iris-msix-signing.cer")
        )
        try {
            if (
                ([string]$publishedCertificate.Thumbprint).ToLowerInvariant() -cne
                ([string]$signature.SignerCertificate.Thumbprint).ToLowerInvariant()
            ) {
                throw "Published certificate does not match the MSIX signer."
            }
            if ([string]$publishedCertificate.Subject -cne $msixPublisher) {
                throw "Published certificate subject does not match the MSIX publisher."
            }
        } finally {
            $publishedCertificate.Dispose()
        }
    }

    $lifecycle = $null
    if ($RequireLifecycleEvidence) {
        $lifecyclePath = Join-Path $testRoot "iris-msix-lifecycle-evidence.json"
        try {
            $lifecycle = Get-Content -LiteralPath $lifecyclePath -Raw | ConvertFrom-Json
        } catch {
            throw "Published lifecycle evidence is not valid JSON: $($_.Exception.Message)"
        }
        if ([int]$lifecycle.schema -ne 3) {
            throw "Published lifecycle evidence must use release-only schema 3."
        }
        $virtualMachine = ([string]$lifecycle.virtual_machine).Trim()
        if (
            -not $virtualMachine -or
            $virtualMachine.Length -gt 200 -or
            $virtualMachine -match "[\x00-\x1f\x7f]"
        ) {
            throw "Published lifecycle evidence has an invalid virtual-machine identity."
        }
        if ([string]$lifecycle.test_context_id -notmatch "^iris-disposable-guest-[0-9a-fA-F]{32}$") {
            throw "Published lifecycle evidence has an invalid disposable guest context."
        }
        if ([string]$lifecycle.package_identity -cne "ProjectIris.LocalAssistant" -or
            [string]$lifecycle.application_id -cne "Iris") {
            throw "Published lifecycle evidence identifies the wrong registered Iris application."
        }
        if ([string]$lifecycle.package_family_name -notmatch "^ProjectIris\.LocalAssistant_[A-Za-z0-9]+$") {
            throw "Published lifecycle evidence has an invalid package family name."
        }
        if (
            [string]$lifecycle.app_user_model_id -cne
            "$([string]$lifecycle.package_family_name)!$([string]$lifecycle.application_id)"
        ) {
            throw "Published lifecycle evidence has an invalid AppUserModelId."
        }
        if ([string]$lifecycle.release_version -cne "$packageVersion.0") {
            throw "Published lifecycle evidence version does not match $Tag."
        }
        if (
            ([string]$lifecycle.release_sha256).ToLowerInvariant() -cne
            $msixSha256
        ) {
            throw "Published lifecycle evidence does not bind to the exact MSIX."
        }
        if ([string]$lifecycle.publisher -cne $msixPublisher) {
            throw "Published lifecycle evidence publisher does not match the MSIX."
        }
        if ([string]$lifecycle.signer_thumbprint -notmatch "^[a-fA-F0-9]{40}$" -or
            ([string]$lifecycle.signer_thumbprint).ToLowerInvariant() -cne
            ([string]$signature.SignerCertificate.Thumbprint).ToLowerInvariant()) {
            throw "Published lifecycle evidence signer does not match the MSIX."
        }
        if (
            $ExpectedSignerThumbprint -and
            ([string]$lifecycle.signer_thumbprint).ToLowerInvariant() -cne
            $ExpectedSignerThumbprint
        ) {
            throw "Published lifecycle evidence signer does not match ExpectedSignerThumbprint."
        }
        if ([string]$lifecycle.state_root -cne "%LOCALAPPDATA%\Iris" -or
            [string]$lifecycle.state_probe_sha256 -notmatch "^[a-fA-F0-9]{64}$") {
            throw "Published lifecycle evidence does not prove canonical Iris state."
        }
        if (
            [string]$lifecycle.wack_overall_result -cne "PASS" -or
            [string]$lifecycle.wack_package_sha256 -notmatch "^[a-fA-F0-9]{64}$" -or
            ([string]$lifecycle.wack_package_sha256).ToLowerInvariant() -cne
                $msixSha256 -or
            [string]$lifecycle.wack_report_sha256 -notmatch "^[a-fA-F0-9]{64}$" -or
            [long]$lifecycle.wack_report_length_bytes -le 0 -or
            [long]$lifecycle.wack_report_length_bytes -gt 32MB
        ) {
            throw "Published lifecycle evidence does not prove a bounded external WACK PASS report."
        }
        try {
            $probeBytes = [Convert]::FromBase64String(
                [string]$lifecycle.state_probe_content_base64
            )
        } catch {
            throw "Published lifecycle evidence contains an invalid encoded Iris state probe."
        }
        if ($probeBytes.Length -le 0 -or $probeBytes.Length -gt 8192) {
            throw "Published lifecycle state probe is empty or exceeds the evidence bound."
        }
        $probeSha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $probeHash = (
                [System.BitConverter]::ToString($probeSha.ComputeHash($probeBytes))
            ).Replace("-", "").ToLowerInvariant()
        } finally {
            $probeSha.Dispose()
        }
        if (
            $probeHash -cne
            ([string]$lifecycle.state_probe_sha256).ToLowerInvariant()
        ) {
            throw "Published lifecycle state-probe content does not match its hash."
        }
        try {
            $probe = (
                [System.Text.Encoding]::UTF8.GetString($probeBytes) |
                    ConvertFrom-Json
            )
        } catch {
            throw "Published lifecycle state-probe content is not valid JSON."
        }
        if (
            [int]$probe.schema -ne 1 -or
            [string]$probe.purpose -cne "signed-release-lifecycle" -or
            [string]$probe.test_context_id -cne [string]$lifecycle.test_context_id -or
            [string]$probe.executable -cne "iris-tauri.exe" -or
            [long]$probe.created_utc_ms -le 0
        ) {
            throw "Published lifecycle state-probe content has invalid Iris provenance."
        }
        $testedUtc = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$lifecycle.tested_utc, [ref]$testedUtc)) {
            throw "Published lifecycle evidence has an invalid tested_utc value."
        }
        $now = [DateTimeOffset]::UtcNow
        if ($testedUtc -gt $now.AddMinutes(5) -or
            $testedUtc -lt $now.AddHours(-$LifecycleMaximumAgeHours)) {
            throw "Published lifecycle evidence is outside the accepted time window."
        }
        foreach ($field in @(
                "install_succeeded",
                "activation_succeeded",
                "uninstall_succeeded",
                "state_survived"
            )) {
            if ($lifecycle.$field -ne $true) {
                throw "Published lifecycle evidence does not prove '$field'."
            }
        }
    }

    if ($RequireWackReport) {
        $wackReport = Get-VerifiedWackReport -Path (
            Join-Path $testRoot "iris-windows-wack-report.xml"
        )
        if (
            $wackReport.Sha256 -cne
                ([string]$lifecycle.wack_report_sha256).ToLowerInvariant() -or
            $wackReport.Length -ne [long]$lifecycle.wack_report_length_bytes
        ) {
            throw "Published WACK report does not match clean-VM lifecycle evidence."
        }
    }

    if ($RequireWingetBundle) {
        $bundlePath = Join-Path $testRoot "iris-winget-manifests.zip"
        $manifestEntries = @(
            "a/AlejandroPinto/Iris/$packageVersion/AlejandroPinto.Iris.installer.yaml",
            "a/AlejandroPinto/Iris/$packageVersion/AlejandroPinto.Iris.locale.en-US.yaml",
            "a/AlejandroPinto/Iris/$packageVersion/AlejandroPinto.Iris.yaml"
        ) | Sort-Object
        $bundle = [System.IO.Compression.ZipFile]::OpenRead($bundlePath)
        try {
            $actualEntries = @(
                $bundle.Entries |
                    Where-Object { -not [string]::IsNullOrEmpty([string]$_.Name) } |
                    ForEach-Object { ([string]$_.FullName).Replace("\", "/") } |
                    Sort-Object
            )
            if (
                $actualEntries.Count -ne $manifestEntries.Count -or
                (Compare-Object -ReferenceObject $manifestEntries -DifferenceObject $actualEntries)
            ) {
                throw "Published WinGet bundle must contain exactly the three manifests for $packageVersion."
            }
        } finally {
            $bundle.Dispose()
        }

        $manifestExtract = Join-Path $testRoot "winget"
        Expand-Archive -LiteralPath $bundlePath -DestinationPath $manifestExtract -Force
        $manifestRoot = Join-Path $manifestExtract "a\AlejandroPinto\Iris\$packageVersion"
        $versionManifestPath = Join-Path $manifestRoot "AlejandroPinto.Iris.yaml"
        $installerManifestPath = Join-Path $manifestRoot "AlejandroPinto.Iris.installer.yaml"
        $localeManifestPath = Join-Path $manifestRoot "AlejandroPinto.Iris.locale.en-US.yaml"
        foreach ($manifestPath in @(
                $versionManifestPath,
                $installerManifestPath,
                $localeManifestPath
            )) {
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                throw "Published WinGet manifest bundle is missing $(Split-Path -Leaf $manifestPath)."
            }
        }

        $versionManifest = Get-Content -LiteralPath $versionManifestPath -Raw
        $installerManifest = Get-Content -LiteralPath $installerManifestPath -Raw
        $localeManifest = Get-Content -LiteralPath $localeManifestPath -Raw

        $manifestAssertions = @(
            [pscustomobject]@{ Text = $versionManifest; Key = "PackageIdentifier"; Expected = "AlejandroPinto.Iris"; Path = $versionManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $versionManifest; Key = "PackageVersion"; Expected = $packageVersion; Path = $versionManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $versionManifest; Key = "DefaultLocale"; Expected = "en-US"; Path = $versionManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $versionManifest; Key = "ManifestType"; Expected = "version"; Path = $versionManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $installerManifest; Key = "PackageIdentifier"; Expected = "AlejandroPinto.Iris"; Path = $installerManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $installerManifest; Key = "PackageVersion"; Expected = $packageVersion; Path = $installerManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $installerManifest; Key = "ManifestType"; Expected = "installer"; Path = $installerManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $installerManifest; Key = "InstallerType"; Expected = "msix"; Path = $installerManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $installerManifest; Key = "Scope"; Expected = "user"; Path = $installerManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $installerManifest; Key = "InstallerUrl"; Expected = "https://github.com/$Repo/releases/download/$Tag/iris-windows.msix"; Path = $installerManifestPath; Scope = "InstallerMember" }
            [pscustomobject]@{ Text = $installerManifest; Key = "InstallerSha256"; Expected = $msixSha256; Path = $installerManifestPath; Scope = "InstallerMember" }
            [pscustomobject]@{ Text = $installerManifest; Key = "SignatureSha256"; Expected = $msixSignatureSha256; Path = $installerManifestPath; Scope = "InstallerMember" }
            [pscustomobject]@{ Text = $localeManifest; Key = "PackageIdentifier"; Expected = "AlejandroPinto.Iris"; Path = $localeManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $localeManifest; Key = "PackageVersion"; Expected = $packageVersion; Path = $localeManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $localeManifest; Key = "PackageLocale"; Expected = "en-US"; Path = $localeManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $localeManifest; Key = "Publisher"; Expected = "Alejandro Pinto"; Path = $localeManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $localeManifest; Key = "PackageName"; Expected = "Iris"; Path = $localeManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $localeManifest; Key = "ReleaseNotesUrl"; Expected = "https://github.com/$Repo/releases/tag/$Tag"; Path = $localeManifestPath; Scope = "Root" }
            [pscustomobject]@{ Text = $localeManifest; Key = "ManifestType"; Expected = "defaultLocale"; Path = $localeManifestPath; Scope = "Root" }
        )
        foreach ($assertion in $manifestAssertions) {
            $actual = Read-YamlScalar `
                -Text $assertion.Text `
                -Key $assertion.Key `
                -Path $assertion.Path `
                -Scope $assertion.Scope
            if ($actual -cne $assertion.Expected) {
                throw "$($assertion.Path) '$($assertion.Key)' mismatch. Expected '$($assertion.Expected)'; got '$actual'."
            }
        }
        $architectureMatches = @(
            [regex]::Matches(
                $installerManifest,
                "(?m)^[ \t]*-[ \t]+Architecture:[ \t]*x64[ \t]*$"
            )
        )
        if ($architectureMatches.Count -ne 1) {
            throw "$installerManifestPath must declare exactly one x64 installer."
        }
        $capabilityBlock = [regex]::Match(
            $installerManifest,
            '(?ms)^ {4}RestrictedCapabilities:[ \t]*\r?\n(?<body>.*?)^ {4}ReleaseDate:'
        )
        if (-not $capabilityBlock.Success) {
            throw "$installerManifestPath has no parseable restricted-capability block."
        }
        $capabilities = @(
            [regex]::Matches(
                $capabilityBlock.Groups["body"].Value,
                '(?m)^ {6}-[ \t]+(?<capability>[^\r\n]+)'
            ) |
                ForEach-Object { $_.Groups["capability"].Value.Trim() } |
                Sort-Object
        )
        $expectedCapabilities = @("runFullTrust", "unvirtualizedResources") | Sort-Object
        if (($capabilities -join "`n") -cne ($expectedCapabilities -join "`n")) {
            throw (
                "$installerManifestPath restricted capabilities must be exactly " +
                "$($expectedCapabilities -join ', ')."
            )
        }
        if ($RequireWingetClientValidation) {
            $winget = Require-Command -Name "winget.exe"
            $validationOutput = @(& $winget validate --manifest $manifestRoot --disable-interactivity 2>&1)
            $validationExitCode = $LASTEXITCODE
            foreach ($line in $validationOutput) {
                Write-Host ([string]$line)
            }
            $warningLines = @($validationOutput |
                    ForEach-Object { ([string]$_).Trim() } |
                    Where-Object { $_.StartsWith("Manifest Warning:", [System.StringComparison]::Ordinal) })
            if ($validationExitCode -ne 0 -or $warningLines.Count -ne 0) {
                throw "Published WinGet manifest bundle failed clean official validation."
            }
        }
    }

    Write-Host "GitHub Iris versioned release verification passed."
    Write-Host "Release: $($release.url)"
    Write-Host "Commit: $remoteCommit"
    Write-Host "Draft: $($release.isDraft)"
    Write-Host "Immutable: $($releaseApi.immutable)"
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
