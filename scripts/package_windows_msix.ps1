param(
    [string]$Publisher = "CN=Iris Local Test",
    [string]$Version = "1.0.0.0",
    [string]$CertificateThumbprint = "",
    [string]$PfxPath = "",
    [string]$PfxPassword = "",
    [string]$TimestampUrl = "http://timestamp.acs.microsoft.com",
    [switch]$AllowSelfSignedDevelopmentCertificate,
    [switch]$ReadinessOnly,
    [switch]$AllowIncompleteReadiness,
    [switch]$SkipSigning,
    [switch]$KeepPackagingWorkspace
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot
. (Join-Path $PSScriptRoot "iris_release_workspace.ps1")

$releaseRoot = Join-Path $repoRoot "release"
$distRoot = Join-Path $releaseRoot "dist"
$msixRoot = Join-Path $releaseRoot "msix"
$layoutRoot = Join-Path $msixRoot "layout"
$appRoot = Join-Path $layoutRoot "VFS\ProgramFilesX64\Iris"
$zipPath = Join-Path $distRoot "iris-windows.zip"
$shaPath = "$zipPath.sha256"
$msixPath = Join-Path $distRoot "iris-windows.msix"
$msixShaPath = "$msixPath.sha256"
$certExportPath = Join-Path $distRoot "iris-msix-signing.cer"
$certExportShaPath = "$certExportPath.sha256"

if ($Version -notmatch "^(0|[1-9][0-9]{0,4})(\.(0|[1-9][0-9]{0,4})){3}$") {
    throw "MSIX Version must contain four numeric components, for example 1.0.0.0."
}
foreach ($part in $Version.Split(".")) {
    if ([int]$part -gt 65535) {
        throw "MSIX Version components must be between 0 and 65535: $Version"
    }
}
if (-not $Publisher.Trim() -or $Publisher -cne $Publisher.Trim()) {
    throw "Publisher must match the subject of the certificate used to sign the MSIX."
}
$publisherXml = [System.Security.SecurityElement]::Escape($Publisher)
if (-not $publisherXml) {
    throw "Publisher could not be encoded safely for AppxManifest.xml."
}
if (-not $SkipSigning -and -not $TimestampUrl.Trim()) {
    throw "An RFC 3161 timestamp URL is required for durable production signatures."
}

function Find-Tool {
    param([Parameter(Mandatory = $true)][string]$Name)
    $direct = Get-Command $Name -ErrorAction SilentlyContinue
    if ($direct) {
        return $direct.Source
    }
    $sdkRoots = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "${env:ProgramFiles}\Windows Kits\10\bin"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($sdkRoot in $sdkRoots) {
        $match = Get-ChildItem -LiteralPath $sdkRoot -Recurse -Filter $Name -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }
    return $null
}

function Get-PngDimensions {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $header = New-Object byte[] 24
        if ($stream.Read($header, 0, $header.Length) -ne $header.Length) {
            throw "PNG is too short to contain an IHDR header: $Path"
        }
        $signature = @(137, 80, 78, 71, 13, 10, 26, 10)
        for ($index = 0; $index -lt $signature.Count; $index++) {
            if ($header[$index] -ne $signature[$index]) {
                throw "File is not a valid PNG: $Path"
            }
        }
        [pscustomobject]@{
            Width = (
                ($header[16] * 16777216) +
                ($header[17] * 65536) +
                ($header[18] * 256) +
                $header[19]
            )
            Height = (
                ($header[20] * 16777216) +
                ($header[21] * 65536) +
                ($header[22] * 256) +
                $header[23]
            )
        }
    } finally {
        $stream.Dispose()
    }
}

function Add-Result {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("PASS", "WARN", "FAIL")][string]$Status,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    [pscustomobject]@{
        Status = $Status
        Name = $Name
        Detail = $Detail
    }
}

function Test-CodeSigningEku {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )
    $eku = @(
        $Certificate.Extensions |
            Where-Object { $_.Oid.Value -eq "2.5.29.37" }
    ) | Select-Object -First 1
    if (-not $eku) {
        return $false
    }
    $enhanced = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new(
        $eku,
        $eku.Critical
    )
    return @($enhanced.EnhancedKeyUsages | ForEach-Object Value) -contains "1.3.6.1.5.5.7.3.3"
}

function Get-CertificateTrustReadiness {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]$ExtraStore
    )

    $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
    try {
        $chain.ChainPolicy.RevocationMode =
            [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        $chain.ChainPolicy.VerificationFlags =
            [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag
        [void]$chain.ChainPolicy.ApplicationPolicy.Add(
            [System.Security.Cryptography.Oid]::new("1.3.6.1.5.5.7.3.3")
        )
        if ($chain.ChainPolicy.PSObject.Properties.Name -contains "DisableCertificateDownloads") {
            $chain.ChainPolicy.DisableCertificateDownloads = $true
        }
        if ($ExtraStore) {
            foreach ($extraCertificate in $ExtraStore) {
                if ($extraCertificate.Thumbprint -cne $Certificate.Thumbprint) {
                    [void]$chain.ChainPolicy.ExtraStore.Add($extraCertificate)
                }
            }
        }

        $chainTrusted = $chain.Build($Certificate)
        $chainStatus = @(
            $chain.ChainStatus |
                ForEach-Object Status |
                ForEach-Object ToString |
                Where-Object { $_ }
        )
        $rootCertificate = if ($chain.ChainElements.Count -gt 0) {
            $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate
        } else {
            $null
        }
        $publicRoot = $false
        if ($rootCertificate) {
            foreach ($storeLocation in @(
                    [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser,
                    [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
                )) {
                $authRootStore = [System.Security.Cryptography.X509Certificates.X509Store]::new(
                    "AuthRoot",
                    $storeLocation
                )
                try {
                    $authRootStore.Open(
                        [System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly
                    )
                    if (@(
                            $authRootStore.Certificates |
                                Where-Object Thumbprint -eq $rootCertificate.Thumbprint
                        ).Count -gt 0) {
                        $publicRoot = $true
                        break
                    }
                } finally {
                    $authRootStore.Dispose()
                }
            }
        }

        [pscustomobject]@{
            ChainTrusted = $chainTrusted
            ChainStatus = if ($chainStatus.Count -gt 0) { $chainStatus -join ", " } else { "none" }
            RootSubject = if ($rootCertificate) { [string]$rootCertificate.Subject } else { "unresolved" }
            PublicRoot = $publicRoot
        }
    } finally {
        $chain.Dispose()
    }
}

function Add-CertificateReadiness {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$ExpectedPublisher,
        [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]$ExtraStore,
        [switch]$AllowSelfSignedDevelopmentCertificate
    )
    $now = [DateTime]::Now
    $subjectName = [System.BitConverter]::ToString($Certificate.SubjectName.RawData)
    $issuerName = [System.BitConverter]::ToString($Certificate.IssuerName.RawData)
    $isSelfIssued =
        $subjectName -ceq $issuerName -or
        [string]$Certificate.Subject -ieq [string]$Certificate.Issuer
    $trust = Get-CertificateTrustReadiness -Certificate $Certificate -ExtraStore $ExtraStore
    $developmentSelfSignedStatus = $isSelfIssued -and $AllowSelfSignedDevelopmentCertificate
    @(
        Add-Result -Status ($(if ($Certificate.HasPrivateKey) { "PASS" } else { "FAIL" })) `
            -Name "signing private key" `
            -Detail "$Source certificate private key is $(if ($Certificate.HasPrivateKey) { 'available' } else { 'missing' })."
        Add-Result -Status ($(if (Test-CodeSigningEku -Certificate $Certificate) { "PASS" } else { "FAIL" })) `
            -Name "code-signing usage" `
            -Detail "$Source certificate must include the Code Signing enhanced key usage."
        Add-Result -Status ($(if ($isSelfIssued) { if ($AllowSelfSignedDevelopmentCertificate) { "WARN" } else { "FAIL" } } else { "PASS" })) `
            -Name "certificate authority issuance" `
            -Detail $(if ($isSelfIssued) { "$Source certificate is self-issued. Self-signed development certificates are $(if ($AllowSelfSignedDevelopmentCertificate) { 'allowed only for this explicitly opted-in development build; production readiness remains NOT READY' } else { 'not accepted for production signing' })." } else { "$Source certificate was issued by '$($Certificate.Issuer)'." })
        Add-Result -Status ($(if ($trust.ChainTrusted) { "PASS" } elseif ($developmentSelfSignedStatus) { "WARN" } else { "FAIL" })) `
            -Name "offline system chain trust" `
            -Detail "$Source certificate offline chain status is '$($trust.ChainStatus)' with root '$($trust.RootSubject)'."
        Add-Result -Status ($(if ($trust.PublicRoot) { "PASS" } else { "WARN" })) `
            -Name "Windows public root inventory" `
            -Detail $(if ($trust.PublicRoot) { "$Source certificate chains to a root in the Windows AuthRoot public trust store." } else { "$Source certificate root is not in this machine's Windows AuthRoot inventory. A system-trusted enterprise chain may still be eligible for managed deployment, but this does not establish public trust on clean user devices." })
        Add-Result -Status ($(if ($Certificate.NotBefore -le $now -and $Certificate.NotAfter -gt $now) { "PASS" } else { "FAIL" })) `
            -Name "certificate validity" `
            -Detail "$Source certificate validity is $($Certificate.NotBefore.ToString('o')) through $($Certificate.NotAfter.ToString('o'))."
        Add-Result -Status ($(if ([string]$Certificate.Subject -ceq $ExpectedPublisher) { "PASS" } else { "FAIL" })) `
            -Name "publisher identity" `
            -Detail "$Source certificate subject is '$($Certificate.Subject)'."
    )
}

$makeAppx = Find-Tool -Name "makeappx.exe"
$signTool = Find-Tool -Name "signtool.exe"
$makePri = Find-Tool -Name "makepri.exe"
$results = @()
$results += Add-Result -Status ($(if ($makeAppx) { "PASS" } else { "FAIL" })) -Name "makeappx.exe" -Detail ($(if ($makeAppx) { $makeAppx } else { "Windows SDK packaging tool is not installed or not on PATH." }))
$results += Add-Result -Status ($(if ($signTool) { "PASS" } else { "FAIL" })) -Name "signtool.exe" -Detail ($(if ($signTool) { $signTool } else { "Windows SDK signing tool is not installed or not on PATH." }))
$results += Add-Result -Status ($(if ($makePri) { "PASS" } else { "WARN" })) -Name "makepri.exe" -Detail ($(if ($makePri) { $makePri } else { "Not required for this first slice because the package uses fixed assets only." }))
$zipExists = Test-Path -LiteralPath $zipPath -PathType Leaf
$shaExists = Test-Path -LiteralPath $shaPath -PathType Leaf
$results += Add-Result -Status ($(if ($zipExists) { "PASS" } else { "FAIL" })) -Name "portable ZIP" -Detail $zipPath
$results += Add-Result -Status ($(if ($shaExists) { "PASS" } else { "FAIL" })) -Name "portable ZIP SHA256" -Detail $shaPath
if ($zipExists -and $shaExists) {
    $checksumText = (Get-Content -LiteralPath $shaPath -Raw).Trim()
    $checksumMatch = [regex]::Match(
        $checksumText,
        "^(?<hash>[a-fA-F0-9]{64}) {2}iris-windows\.zip$"
    )
    if (-not $checksumMatch.Success) {
        $results += Add-Result -Status "FAIL" -Name "portable ZIP integrity" -Detail "Portable ZIP checksum must contain exactly one SHA-256 digest and the filename iris-windows.zip."
    } else {
        $expectedZipHash = $checksumMatch.Groups["hash"].Value.ToLowerInvariant()
        $actualZipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $results += Add-Result `
            -Status ($(if ($actualZipHash -ceq $expectedZipHash) { "PASS" } else { "FAIL" })) `
            -Name "portable ZIP integrity" `
            -Detail $(if ($actualZipHash -ceq $expectedZipHash) { "Portable ZIP matches its exact SHA-256 checksum." } else { "Portable ZIP SHA-256 mismatch. Expected $expectedZipHash but got $actualZipHash." })
    }
}
$certificateStoreLocation = $null
$expectedSignerThumbprint = $null
if ($SkipSigning) {
    $results += Add-Result -Status "WARN" -Name "signing input" -Detail "SkipSigning was requested; unsigned MSIX files are not installable for normal users."
} else {
    $explicitThumbprint = $PSBoundParameters.ContainsKey("CertificateThumbprint")
    $explicitPfx = $PSBoundParameters.ContainsKey("PfxPath")
    $thumbprintInput = $null
    $pfxInput = $null
    $signingInputError = $null
    if ($explicitThumbprint -and $explicitPfx) {
        $signingInputError = "Provide exactly one explicit signing source: -CertificateThumbprint or -PfxPath, not both."
    } elseif ($explicitThumbprint) {
        if (-not $CertificateThumbprint.Trim()) {
            $signingInputError = "Explicit -CertificateThumbprint must not be empty."
        } else {
            $thumbprintInput = $CertificateThumbprint
        }
    } elseif ($explicitPfx) {
        if (-not $PfxPath.Trim()) {
            $signingInputError = "Explicit -PfxPath must not be empty."
        } else {
            $pfxInput = $PfxPath
        }
    } else {
        $environmentThumbprint = [string]$env:IRIS_SIGNING_CERT_THUMBPRINT
        $environmentPfx = [string]$env:IRIS_SIGNING_PFX
        if ($environmentThumbprint.Trim() -and $environmentPfx.Trim()) {
            $signingInputError = "Both IRIS_SIGNING_CERT_THUMBPRINT and IRIS_SIGNING_PFX are set. Keep exactly one ambient signing source."
        } elseif ($environmentThumbprint.Trim()) {
            $thumbprintInput = $environmentThumbprint
        } elseif ($environmentPfx.Trim()) {
            $pfxInput = $environmentPfx
        }
    }
    if ($thumbprintInput) {
        $thumbprintInput = ([string]$thumbprintInput -replace "\s", "").ToUpperInvariant()
    }
    if ($signingInputError) {
        $results += Add-Result -Status "FAIL" -Name "signing input" -Detail $signingInputError
    } elseif ($thumbprintInput) {
        if ($thumbprintInput -notmatch "^[A-F0-9]{40}$") {
            $certificate = $null
            $results += Add-Result -Status "FAIL" -Name "signing input" -Detail "Certificate thumbprint must contain exactly 40 hexadecimal characters."
        } else {
            $certificate = @(
                Get-ChildItem -LiteralPath Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
                    Where-Object Thumbprint -eq $thumbprintInput
            ) | Select-Object -First 1
            if ($certificate) {
                $certificateStoreLocation = "CurrentUser"
            } else {
                $certificate = @(
                    Get-ChildItem -LiteralPath Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
                        Where-Object Thumbprint -eq $thumbprintInput
                ) | Select-Object -First 1
                if ($certificate) {
                    $certificateStoreLocation = "LocalMachine"
                }
            }
            $results += Add-Result -Status ($(if ($certificate) { "PASS" } else { "FAIL" })) -Name "signing input" -Detail ($(if ($certificate) { "Certificate thumbprint resolved in $certificateStoreLocation\My for $($certificate.Subject)." } else { "Certificate thumbprint was provided but not found in CurrentUser or LocalMachine personal stores." }))
        }
        if ($certificate) {
            $expectedSignerThumbprint = ([string]$certificate.Thumbprint).ToUpperInvariant()
            $results += Add-CertificateReadiness `
                -Certificate $certificate `
                -Source "$certificateStoreLocation\My" `
                -ExpectedPublisher $Publisher `
                -AllowSelfSignedDevelopmentCertificate:$AllowSelfSignedDevelopmentCertificate
        }
    } elseif ($pfxInput) {
        $pfxResolved = [System.IO.Path]::GetFullPath($pfxInput)
        $pfxExists = Test-Path -LiteralPath $pfxResolved -PathType Leaf
        $results += Add-Result -Status ($(if ($pfxExists) { "PASS" } else { "FAIL" })) -Name "signing input" -Detail ($(if ($pfxExists) { "PFX path exists." } else { "PFX path was provided but does not exist: $pfxResolved" }))
        if ($pfxExists) {
            $pfxPasswordInput = if ($PfxPassword) { $PfxPassword } else { $env:IRIS_SIGNING_PFX_PASSWORD }
            $pfxCertificates = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
            try {
                $pfxCertificates.Import(
                    $pfxResolved,
                    $pfxPasswordInput,
                    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
                )
                $eligiblePfxCertificates = @(
                    $pfxCertificates |
                        Where-Object {
                            $_.HasPrivateKey -and
                            (Test-CodeSigningEku -Certificate $_)
                        }
                )
                $eligiblePfxCertificateCount = $eligiblePfxCertificates.Count
                $pfxCertificate = $eligiblePfxCertificates | Select-Object -First 1
                $results += Add-Result -Status ($(if ($eligiblePfxCertificateCount -eq 1) { "PASS" } else { "FAIL" })) `
                    -Name "PFX certificate" `
                    -Detail ($(if ($eligiblePfxCertificateCount -eq 1) { "PFX contains exactly one private-key code-signing certificate." } elseif ($eligiblePfxCertificateCount -eq 0) { "PFX contains no private-key code-signing certificate." } else { "PFX contains $eligiblePfxCertificateCount private-key code-signing certificates; provide an unambiguous PFX." }))
                if ($eligiblePfxCertificateCount -eq 1) {
                    $expectedSignerThumbprint = ([string]$pfxCertificate.Thumbprint).ToUpperInvariant()
                    $results += Add-CertificateReadiness `
                        -Certificate $pfxCertificate `
                        -Source "PFX" `
                        -ExpectedPublisher $Publisher `
                        -ExtraStore $pfxCertificates `
                        -AllowSelfSignedDevelopmentCertificate:$AllowSelfSignedDevelopmentCertificate
                }
            } catch {
                $results += Add-Result -Status "FAIL" -Name "PFX certificate" -Detail "PFX could not be opened with the supplied password."
            } finally {
                foreach ($pfxCertificateToDispose in $pfxCertificates) {
                    $pfxCertificateToDispose.Dispose()
                }
            }
        }
    } else {
        $results += Add-Result -Status "FAIL" -Name "signing input" -Detail "Provide -CertificateThumbprint, IRIS_SIGNING_CERT_THUMBPRINT, -PfxPath, or IRIS_SIGNING_PFX."
    }
}

New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
$readinessPath = Join-Path $distRoot "iris-msix-readiness.txt"
$lines = @(
    "Iris MSIX/App Installer readiness",
    "Generated: $(Get-Date -Format o)",
    "Recommendation: MSIX/App Installer for signed distribution; keep PowerShell ZIP installer as fallback.",
    "Package version: $Version",
    "Publisher identity: $Publisher",
    ""
)
foreach ($result in $results) {
    $line = "[$($result.Status)] $($result.Name): $($result.Detail)"
    Write-Host $line
    $lines += $line
}
Set-Content -LiteralPath $readinessPath -Value $lines -Encoding utf8

$failCount = @($results | Where-Object Status -eq "FAIL").Count
$signingInputReady =
    $failCount -eq 0 -and
    [bool]$expectedSignerThumbprint -and
    -not $SkipSigning -and
    -not $AllowSelfSignedDevelopmentCertificate
$signingSummary = "Signing input readiness: $(if ($signingInputReady) { 'READY' } else { 'NOT READY' }); failures=$failCount; unsigned=$($SkipSigning.IsPresent.ToString().ToLowerInvariant()); development_self_signed_opt_in=$($AllowSelfSignedDevelopmentCertificate.IsPresent.ToString().ToLowerInvariant())"
$productionSummary = "Overall production readiness: NOT READY; signed_artifact_verified=false; clean_vm_wack_lifecycle_verified=false"
Write-Host $signingSummary
Write-Host $productionSummary
Add-Content -LiteralPath $readinessPath -Value @("", $signingSummary, $productionSummary) -Encoding utf8
Write-Host "Readiness report: $readinessPath"

if ($ReadinessOnly) {
    if (-not $signingInputReady) {
        $message = "MSIX signing input is not ready on this machine. Overall production readiness also requires the exact signed artifact and clean-VM WACK/lifecycle evidence. This readiness check was non-destructive."
        if ($AllowIncompleteReadiness) {
            Write-Warning $message
            return
        }
        throw $message
    }
    return
}
if ($failCount -gt 0) {
    throw "MSIX build prerequisites are missing. Run with -ReadinessOnly -AllowIncompleteReadiness for a non-blocking report."
}

foreach ($staleCertificateArtifact in @($certExportPath, $certExportShaPath)) {
    if (Test-Path -LiteralPath $staleCertificateArtifact -PathType Leaf) {
        Remove-Item -LiteralPath $staleCertificateArtifact -Force
    }
}
Remove-IrisReleaseWorkspace -RepositoryRoot $repoRoot -Workspace msix
New-Item -ItemType Directory -Force -Path $appRoot | Out-Null

$checksumText = (Get-Content -LiteralPath $shaPath -Raw).Trim()
$checksumMatch = [regex]::Match(
    $checksumText,
    "^(?<hash>[a-fA-F0-9]{64}) {2}iris-windows\.zip$"
)
if (-not $checksumMatch.Success) {
    throw "Portable ZIP checksum must contain exactly one SHA-256 digest and the filename iris-windows.zip."
}
$expectedHash = $checksumMatch.Groups["hash"].Value
$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash.ToLowerInvariant()) {
    throw "ZIP SHA256 mismatch. Expected $expectedHash but got $actualHash."
}
Expand-Archive -LiteralPath $zipPath -DestinationPath $appRoot -Force

$requiredLogoAssets = [ordered]@{
    "assets\iris-package-logo-50.png" = 50
    "assets\iris-square-150.png" = 150
    "assets\iris-square-44.png" = 44
}
foreach ($relativeLogoPath in $requiredLogoAssets.Keys) {
    $logoPath = Join-Path $appRoot $relativeLogoPath
    if (-not (Test-Path -LiteralPath $logoPath -PathType Leaf)) {
        throw "MSIX logo asset is missing: $relativeLogoPath"
    }
    $dimensions = Get-PngDimensions -Path $logoPath
    $expectedSize = [int]$requiredLogoAssets[$relativeLogoPath]
    if ($dimensions.Width -ne $expectedSize -or $dimensions.Height -ne $expectedSize) {
        throw (
            "MSIX logo asset $relativeLogoPath must be ${expectedSize}x$expectedSize, " +
            "but is $($dimensions.Width)x$($dimensions.Height)."
        )
    }
}

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10"
  xmlns:desktop6="http://schemas.microsoft.com/appx/manifest/desktop/windows10/6"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap desktop desktop6 rescap">
  <Identity Name="ProjectIris.LocalAssistant" Publisher="$publisherXml" Version="$Version" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>Iris</DisplayName>
    <PublisherDisplayName>Alejandro Pinto</PublisherDisplayName>
    <Logo>VFS\ProgramFilesX64\Iris\assets\iris-package-logo-50.png</Logo>
    <desktop6:FileSystemWriteVirtualization>disabled</desktop6:FileSystemWriteVirtualization>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26200.0" />
  </Dependencies>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
    <rescap:Capability Name="unvirtualizedResources" />
  </Capabilities>
  <Applications>
    <Application Id="Iris" Executable="VFS\ProgramFilesX64\Iris\bin\iris-tauri.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="Iris" Description="Local-first Iris assistant" BackgroundColor="transparent" Square150x150Logo="VFS\ProgramFilesX64\Iris\assets\iris-square-150.png" Square44x44Logo="VFS\ProgramFilesX64\Iris\assets\iris-square-44.png" />
      <Extensions>
        <desktop:Extension Category="windows.fullTrustProcess" Executable="VFS\ProgramFilesX64\Iris\bin\iris-tauri.exe" />
      </Extensions>
    </Application>
  </Applications>
</Package>
"@
$manifestPath = Join-Path $layoutRoot "AppxManifest.xml"
Set-Content -LiteralPath $manifestPath -Value $manifest -Encoding utf8
[xml]$parsedManifest = Get-Content -LiteralPath $manifestPath -Raw
if ([string]$parsedManifest.Package.Identity.Publisher -cne $Publisher) {
    throw "Encoded AppxManifest publisher does not round-trip to the exact certificate subject."
}

& $makeAppx pack /d $layoutRoot /p $msixPath /o
if ($LASTEXITCODE -ne 0) {
    throw "makeappx failed with exit code $LASTEXITCODE"
}
$maximumMsixBytes = 610MB
$msixBytes = (Get-Item -LiteralPath $msixPath).Length
if ($msixBytes -gt $maximumMsixBytes) {
    throw "Iris MSIX exceeds the 610 MiB release budget: $msixBytes bytes."
}

if (-not $SkipSigning) {
    $thumbprint = $thumbprintInput
    $pfx = $pfxInput
    if ($thumbprint) {
        if ($certificateStoreLocation -eq "LocalMachine") {
            & $signTool sign /fd SHA256 /tr $TimestampUrl /td SHA256 /sm /sha1 $thumbprint $msixPath
        } else {
            & $signTool sign /fd SHA256 /tr $TimestampUrl /td SHA256 /sha1 $thumbprint $msixPath
        }
    } else {
        $password = if ($PfxPassword) { $PfxPassword } else { $env:IRIS_SIGNING_PFX_PASSWORD }
        if ($password) {
            & $signTool sign /fd SHA256 /tr $TimestampUrl /td SHA256 /f $pfx /p $password $msixPath
        } else {
            & $signTool sign /fd SHA256 /tr $TimestampUrl /td SHA256 /f $pfx $msixPath
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed with exit code $LASTEXITCODE"
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $msixPath
    if (-not $signature.SignerCertificate -or $signature.Status -ne "Valid") {
        throw "MSIX Authenticode signature is not valid and trusted: $($signature.Status) $($signature.StatusMessage)"
    }
    if ([string]$signature.SignerCertificate.Subject -cne $Publisher) {
        throw "MSIX signer subject does not match Publisher '$Publisher'."
    }
    if (
        -not $expectedSignerThumbprint -or
        ([string]$signature.SignerCertificate.Thumbprint).ToUpperInvariant() -cne
            $expectedSignerThumbprint
    ) {
        throw "MSIX signer thumbprint does not match the exact certificate validated during readiness."
    }
    if (-not $signature.TimeStamperCertificate) {
        throw "MSIX signature has no trusted RFC 3161 timestamp."
    }
    & $signTool verify /pa /v $msixPath
    if ($LASTEXITCODE -ne 0) {
        throw "signtool verification failed with exit code $LASTEXITCODE"
    }
    Export-Certificate -Cert $signature.SignerCertificate -FilePath $certExportPath -Force | Out-Null
    $certHash = (Get-FileHash -LiteralPath $certExportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath $certExportShaPath -Value "$certHash  iris-msix-signing.cer" -Encoding ascii
    Write-Host "MSIX signing certificate: $certExportPath"
    Write-Host "MSIX signing certificate SHA256: $certExportShaPath"
    Write-Host "Certificate SHA256: $certHash"
}

$msixHash = (Get-FileHash -LiteralPath $msixPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $msixShaPath -Value "$msixHash  iris-windows.msix" -Encoding ascii
if ($KeepPackagingWorkspace) {
    Write-Warning "Keeping generated MSIX packaging workspace for diagnostics: $msixRoot"
} else {
    Remove-IrisReleaseWorkspace -RepositoryRoot $repoRoot -Workspace "msix"
}

Write-Host "MSIX: $msixPath"
Write-Host "MSIX SHA256: $msixShaPath"
Write-Host "SHA256: $msixHash"
