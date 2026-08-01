param(
    [Parameter(Mandatory = $true)][string]$PackageVersion,
    [Parameter(Mandatory = $true)][string]$MsixPath,
    [string]$InstallerUrl = "",
    [string]$OutputRoot = "",
    [string]$ReleaseDate = "",
    [string]$ExpectedPublisher = "",
    [switch]$SkipWingetValidation,
    [switch]$AllowUnsignedTestArtifact
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$packageIdentifier = "AlejandroPinto.Iris"
$manifestVersion = "1.12.0"

if ($PackageVersion -notmatch "^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$") {
    throw "PackageVersion must be a three-part numeric version such as 1.0.0. Mutable tags such as v1 cannot support WinGet upgrades."
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
if (
    -not $AllowUnsignedTestArtifact -and
    -not $signature.TimeStamperCertificate
) {
    throw "WinGet manifests require an MSIX with a trusted RFC 3161 timestamp."
}
if (-not $AllowUnsignedTestArtifact -and -not $ExpectedPublisher.Trim()) {
    throw "ExpectedPublisher must be the exact production signing certificate subject."
}
if (
    $ExpectedPublisher -and
    $signature.SignerCertificate -and
    [string]$signature.SignerCertificate.Subject -cne $ExpectedPublisher
) {
    throw "MSIX signer '$($signature.SignerCertificate.Subject)' does not match ExpectedPublisher '$ExpectedPublisher'."
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
        if ([string]$identity.Name -cne "ProjectIris.LocalAssistant") {
            throw "MSIX package identity must be ProjectIris.LocalAssistant."
        }
        if ([string]$identity.ProcessorArchitecture -cne "x64") {
            throw "MSIX processor architecture must be x64."
        }
        if ([string]$identity.Publisher -cne [string]$signature.SignerCertificate.Subject) {
            throw "MSIX manifest publisher does not match its signing certificate subject."
        }
        if ($ExpectedPublisher -and [string]$identity.Publisher -cne $ExpectedPublisher) {
            throw "MSIX manifest publisher does not match ExpectedPublisher."
        }
        $expectedMsixVersion = "$PackageVersion.0"
        if ([string]$identity.Version -cne $expectedMsixVersion) {
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
$manifestsRoot = Join-Path $output "manifests"
$manifestsRootResolved = [System.IO.Path]::GetFullPath($manifestsRoot)
if (-not $manifestsRootResolved.StartsWith($output + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace WinGet manifests outside OutputRoot: $manifestsRootResolved"
}
$versionRoot = Join-Path $output "manifests\a\AlejandroPinto\Iris\$PackageVersion"
$versionRootResolved = [System.IO.Path]::GetFullPath($versionRoot)
if (-not $versionRootResolved.StartsWith($output + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to generate WinGet manifests outside OutputRoot: $versionRootResolved"
}
if (Test-Path -LiteralPath $manifestsRootResolved) {
    Remove-Item -LiteralPath $manifestsRootResolved -Recurse -Force
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
    - PackageIdentifier: Google.Chrome
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
      - unvirtualizedResources
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
PrivacyUrl: https://github.com/supermang617/IRIS/blob/main/PRIVACY.md
License: MIT
LicenseUrl: https://github.com/supermang617/IRIS/blob/main/LICENSE
Copyright: Copyright (c) Alejandro Pinto
CopyrightUrl: https://github.com/supermang617/IRIS/blob/main/LICENSE
ShortDescription: Local-first Windows companion assistant with voice, vision, memory, and approval-gated agent tools.
Description: >-
  Iris is a local-first Windows companion assistant using Ollama, native
  Whisper ASR, Kokoro speech, private local memory, vision, and explicitly
  approved Hermes tools.
Moniker: iris
Tags:
  - ai
  - assistant
  - desktop-assistant
  - hermes
  - local-ai
  - local-first
  - local-llm
  - memory
  - ollama
  - privacy
  - speech-to-text
  - text-to-speech
  - vision
  - voice-assistant
  - windows
  - windows-ai
ReleaseNotes: >-
  Iris $PackageVersion is the signed Windows release represented by this
  manifest. See the versioned GitHub release for its verified assets, changes,
  requirements, and known limitations.
ReleaseNotesUrl: https://github.com/supermang617/IRIS/releases/tag/v$PackageVersion
Documentations:
  - DocumentLabel: Download and setup guide
    DocumentUrl: https://github.com/supermang617/IRIS/blob/main/docs/download-and-run.md
  - DocumentLabel: Security policy
    DocumentUrl: https://github.com/supermang617/IRIS/security/policy
  - DocumentLabel: WinGet release and upgrade guide
    DocumentUrl: https://github.com/supermang617/IRIS/blob/main/docs/winget-release.md
InstallationNotes: >-
  For full local text and vision, run `ollama pull huihui_ai/gemma-4-abliterated:e2b`, then launch Iris from the Windows Start menu. Iris includes its pinned Python voice packages; Google Chrome supplies the separately isolated browser engine, while WebView2 powers the Iris desktop shell. The Ollama model uses several gigabytes. Portable or legacy-install diagnostics use Start Iris.ps1 -SelfCheck.
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
        $hasNativeErrorPreference = Test-Path -LiteralPath Variable:PSNativeCommandUseErrorActionPreference
        if ($hasNativeErrorPreference) {
            $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
            $PSNativeCommandUseErrorActionPreference = $false
        }
        try {
            $validationOutput = @(& $winget.Source validate --manifest $versionRootResolved --disable-interactivity 2>&1)
            $validationExitCode = $LASTEXITCODE
        } finally {
            if ($hasNativeErrorPreference) {
                $PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
            }
        }
        foreach ($line in $validationOutput) {
            Write-Host ([string]$line)
        }
        $wingetManifestValidationWarning = -1978335192 # 0x8A150028
        if ($validationExitCode -eq $wingetManifestValidationWarning) {
            $expectedDependencyWarningLines = @(
                "Manifest has the following dependencies that were not validated; ensure that they are valid:",
                "- Packages",
                "Google.Chrome",
                "Microsoft.EdgeWebView2Runtime",
                "Ollama.Ollama",
                "Python.Python.3.13",
                "tesseract-ocr.tesseract",
                "Manifest validation succeeded."
            )
            $actualDependencyWarningLines = @($validationOutput |
                    ForEach-Object { ([string]$_).Trim() } |
                    Where-Object { $_ })
            $unexpectedDependencyWarningLines = @($actualDependencyWarningLines |
                    Where-Object { $_ -notin $expectedDependencyWarningLines })
            $missingDependencyWarningLines = @($expectedDependencyWarningLines |
                    Where-Object { $_ -notin $actualDependencyWarningLines })
            if (
                $unexpectedDependencyWarningLines.Count -ne 0 -or
                $missingDependencyWarningLines.Count -ne 0
            ) {
                throw "winget validate returned an unexpected manifest warning (exit code $validationExitCode)."
            }
            Write-Warning "winget validated the manifest structure but could not validate its five external package dependencies on this host."
            $validationExitCode = 0
        }
        $warningLines = @($validationOutput |
                ForEach-Object { ([string]$_).Trim() } |
                Where-Object { $_.StartsWith("Manifest Warning:", [System.StringComparison]::Ordinal) })
        if ($validationExitCode -ne 0 -or $warningLines.Count -ne 0) {
            throw "winget validate failed with exit code $validationExitCode"
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
$bundleArchive = [System.IO.Compression.ZipFile]::OpenRead($bundlePath)
try {
    $bundleEntries = @(
        $bundleArchive.Entries |
            Where-Object { -not [string]::IsNullOrEmpty([string]$_.Name) } |
            ForEach-Object { ([string]$_.FullName).Replace("\", "/") } |
            Sort-Object
    )
    $expectedBundleEntries = @(
        "a/AlejandroPinto/Iris/$PackageVersion/$packageIdentifier.installer.yaml",
        "a/AlejandroPinto/Iris/$PackageVersion/$packageIdentifier.locale.en-US.yaml",
        "a/AlejandroPinto/Iris/$PackageVersion/$packageIdentifier.yaml"
    ) | Sort-Object
    if (
        $bundleEntries.Count -ne $expectedBundleEntries.Count -or
        (Compare-Object -ReferenceObject $expectedBundleEntries -DifferenceObject $bundleEntries)
    ) {
        throw "WinGet submission bundle must contain exactly the three manifests for $PackageVersion."
    }
} finally {
    $bundleArchive.Dispose()
}
$bundleHash = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $bundleShaPath -Value "$bundleHash  iris-winget-manifests.zip" -Encoding ascii

Write-Host "WinGet manifests: $versionRootResolved"
Write-Host "WinGet submission bundle: $bundlePath"
Write-Host "Package command after catalog acceptance: winget install --id $packageIdentifier -e"
Write-Host "Upgrade command after catalog acceptance: winget upgrade --id $packageIdentifier -e"
