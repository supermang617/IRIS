param(
    [Parameter(Mandatory = $true)][string]$PackageVersion,
    [Parameter(Mandatory = $true)][string]$MsixPath,
    [string]$InstallerUrl = "",
    [string]$OutputRoot = "",
    [string]$ReleaseDate = "",
    [switch]$SkipWingetValidation,
    [switch]$AllowUnsignedTestArtifact
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$packageIdentifier = "AlejandroPinto.Iris"
$manifestVersion = "1.12.0"

if ($PackageVersion -notmatch "^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$") {
    throw "PackageVersion must be a three-part numeric version such as 1.0.1. Mutable tags such as v1 cannot support WinGet upgrades."
}
foreach ($part in $PackageVersion.Split(".")) {
    if ([int64]$part -gt 65535) {
        throw "Each PackageVersion component must fit the MSIX version range 0-65535: $PackageVersion"
    }
}

$msix = [System.IO.Path]::GetFullPath($MsixPath)
if (-not (Test-Path -LiteralPath $msix -PathType Leaf)) {
    throw "Signed MSIX artifact is missing: $msix"
}

if (-not $InstallerUrl) {
    $InstallerUrl = "https://github.com/supermang617/IRIS/releases/download/v$PackageVersion/iris-windows.msix"
}
$expectedUrl = "https://github.com/supermang617/IRIS/releases/download/v$PackageVersion/iris-windows.msix"
if ($InstallerUrl -cne $expectedUrl) {
    throw "InstallerUrl must use the immutable version tag v${PackageVersion}: $expectedUrl"
}

if (-not $ReleaseDate) {
    $ReleaseDate = Get-Date -Format "yyyy-MM-dd"
}
if ($ReleaseDate -notmatch "^\d{4}-\d{2}-\d{2}$") {
    throw "ReleaseDate must use YYYY-MM-DD."
}

$signature = Get-AuthenticodeSignature -LiteralPath $msix
if (-not $signature.SignerCertificate -and -not $AllowUnsignedTestArtifact) {
    throw "WinGet manifests require the production signed MSIX. The artifact is unsigned: $msix"
}
if ($signature.SignerCertificate -and $signature.Status -ne "Valid" -and -not $AllowUnsignedTestArtifact) {
    throw "MSIX signature is not valid on this machine: $($signature.Status) $($signature.StatusMessage)"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($msix)
try {
    $manifestEntry = $archive.GetEntry("AppxManifest.xml")
    $signatureEntry = $archive.GetEntry("AppxSignature.p7x")
    if (-not $AllowUnsignedTestArtifact) {
        if (-not $manifestEntry) {
            throw "MSIX is missing AppxManifest.xml."
        }
        if (-not $signatureEntry) {
            throw "Signed MSIX is missing AppxSignature.p7x."
        }
    }

    $signatureSha256 = ""
    if ($signatureEntry) {
        $stream = $signatureEntry.Open()
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $signatureSha256 = ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
            } finally {
                $sha.Dispose()
            }
        } finally {
            $stream.Dispose()
        }
    }

    if ($manifestEntry -and $signature.SignerCertificate) {
        $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
        try {
            [xml]$appxManifest = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }
        $identity = $appxManifest.Package.Identity
        if ([string]$identity.Publisher -cne [string]$signature.SignerCertificate.Subject) {
            throw "MSIX manifest publisher does not match its signing certificate subject."
        }
        $expectedMsixVersion = "$PackageVersion.0"
        if ([string]$identity.Version -ne $expectedMsixVersion) {
            throw "MSIX version $($identity.Version) does not match WinGet version $PackageVersion (expected MSIX $expectedMsixVersion)."
        }
    }
} finally {
    $archive.Dispose()
}

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot "release\dist\winget"
}
$output = [System.IO.Path]::GetFullPath($OutputRoot).TrimEnd("\")
$versionRoot = Join-Path $output "manifests\a\AlejandroPinto\Iris\$PackageVersion"
$versionRootResolved = [System.IO.Path]::GetFullPath($versionRoot)
if (-not $versionRootResolved.StartsWith($output + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to generate WinGet manifests outside OutputRoot: $versionRootResolved"
}
if (Test-Path -LiteralPath $versionRootResolved) {
    Remove-Item -LiteralPath $versionRootResolved -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $versionRootResolved | Out-Null

$installerSha256 = (Get-FileHash -LiteralPath $msix -Algorithm SHA256).Hash.ToLowerInvariant()
$versionManifest = @"
# Created with Project Iris release tooling. Validate again before submitting to microsoft/winget-pkgs.
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.$manifestVersion.schema.json

PackageIdentifier: $packageIdentifier
PackageVersion: $PackageVersion
DefaultLocale: en-US
ManifestType: version
ManifestVersion: $manifestVersion
"@

$signatureLine = if ($signatureSha256) { "    SignatureSha256: $signatureSha256`n" } else { "" }
$installerManifest = @"
# Created with Project Iris release tooling. The installer URL must remain immutable.
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.$manifestVersion.schema.json

PackageIdentifier: $packageIdentifier
PackageVersion: $PackageVersion
InstallerType: msix
Scope: user
UpgradeBehavior: install
MinimumOSVersion: 10.0.19041.0
Dependencies:
  PackageDependencies:
    - PackageIdentifier: Microsoft.Edge
    - PackageIdentifier: Microsoft.EdgeWebView2Runtime
    - PackageIdentifier: Ollama.Ollama
    - PackageIdentifier: Python.Python.3.13
    - PackageIdentifier: tesseract-ocr.tesseract
Installers:
  - Architecture: x64
    InstallerUrl: $InstallerUrl
    InstallerSha256: $installerSha256
$signatureLine    RestrictedCapabilities:
      - runFullTrust
    ReleaseDate: $ReleaseDate
ManifestType: installer
ManifestVersion: $manifestVersion
"@

$localeManifest = @"
# Created with Project Iris release tooling. Public catalog submission still requires Microsoft review.
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.$manifestVersion.schema.json

PackageIdentifier: $packageIdentifier
PackageVersion: $PackageVersion
PackageLocale: en-US
Publisher: Alejandro Pinto
PublisherUrl: https://github.com/supermang617
PublisherSupportUrl: https://github.com/supermang617/IRIS/issues
Author: Alejandro Pinto
PackageName: Iris
PackageUrl: https://supermang617.github.io/IRIS/
License: MIT
LicenseUrl: https://github.com/supermang617/IRIS/blob/main/LICENSE
Copyright: Copyright (c) Alejandro Pinto
ShortDescription: Local-first Windows companion assistant with voice, vision, memory, and approval-gated agent tools.
Description: Iris is a local-first Windows companion assistant using Ollama, native Whisper ASR, Kokoro speech, private local memory, vision, and explicitly approved Hermes tools.
Moniker: iris
Tags:
  - ai
  - assistant
  - local-ai
  - ollama
  - privacy
  - voice
ReleaseNotesUrl: https://github.com/supermang617/IRIS/releases/tag/v$PackageVersion
InstallationNotes: >-
  For full local text and vision, run `ollama pull huihui_ai/gemma-4-abliterated:e2b`, then launch Iris from the Windows Start menu. Iris includes its pinned Python voice packages; Microsoft Edge supplies the separately isolated browser engine. The Ollama model uses several gigabytes. Portable or legacy-install diagnostics use Start Iris.ps1 -SelfCheck.
ManifestType: defaultLocale
ManifestVersion: $manifestVersion
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$versionPath = Join-Path $versionRootResolved "$packageIdentifier.yaml"
$installerPath = Join-Path $versionRootResolved "$packageIdentifier.installer.yaml"
$localePath = Join-Path $versionRootResolved "$packageIdentifier.locale.en-US.yaml"
[System.IO.File]::WriteAllText($versionPath, $versionManifest.Trim() + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText($installerPath, $installerManifest.Trim() + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText($localePath, $localeManifest.Trim() + "`n", $utf8NoBom)

if (-not $SkipWingetValidation) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        & $winget.Source validate --manifest $versionRootResolved --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            throw "winget validate failed with exit code $LASTEXITCODE"
        }
    } else {
        Write-Warning "winget.exe is unavailable; local invariants passed but official client validation was skipped."
    }
}

$bundlePath = Join-Path $output "iris-winget-manifests.zip"
$bundleShaPath = "$bundlePath.sha256"
if (Test-Path -LiteralPath $bundlePath) {
    Remove-Item -LiteralPath $bundlePath -Force
}
Compress-Archive -Path (Join-Path $output "manifests\*") -DestinationPath $bundlePath -Force
$bundleHash = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $bundleShaPath -Value "$bundleHash  iris-winget-manifests.zip" -Encoding ascii

Write-Host "WinGet manifests: $versionRootResolved"
Write-Host "WinGet submission bundle: $bundlePath"
Write-Host "Package command after catalog acceptance: winget install --id $packageIdentifier -e"
Write-Host "Upgrade command after catalog acceptance: winget upgrade --id $packageIdentifier -e"
