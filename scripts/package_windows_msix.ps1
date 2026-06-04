param(
    [string]$Publisher = "CN=Iris Local Test",
    [string]$Version = "0.1.0.0",
    [string]$CertificateThumbprint = "",
    [string]$PfxPath = "",
    [string]$PfxPassword = "",
    [switch]$ReadinessOnly,
    [switch]$SkipSigning
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot

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

$makeAppx = Find-Tool -Name "makeappx.exe"
$signTool = Find-Tool -Name "signtool.exe"
$makePri = Find-Tool -Name "makepri.exe"
$results = @()
$results += Add-Result -Status ($(if ($makeAppx) { "PASS" } else { "FAIL" })) -Name "makeappx.exe" -Detail ($(if ($makeAppx) { $makeAppx } else { "Windows SDK packaging tool is not installed or not on PATH." }))
$results += Add-Result -Status ($(if ($signTool) { "PASS" } else { "FAIL" })) -Name "signtool.exe" -Detail ($(if ($signTool) { $signTool } else { "Windows SDK signing tool is not installed or not on PATH." }))
$results += Add-Result -Status ($(if ($makePri) { "PASS" } else { "WARN" })) -Name "makepri.exe" -Detail ($(if ($makePri) { $makePri } else { "Not required for this first slice because the package uses fixed assets only." }))
$results += Add-Result -Status ($(if (Test-Path -LiteralPath $zipPath -PathType Leaf) { "PASS" } else { "FAIL" })) -Name "portable ZIP" -Detail $zipPath
$results += Add-Result -Status ($(if (Test-Path -LiteralPath $shaPath -PathType Leaf) { "PASS" } else { "FAIL" })) -Name "portable ZIP SHA256" -Detail $shaPath
if ($SkipSigning) {
    $results += Add-Result -Status "WARN" -Name "signing input" -Detail "SkipSigning was requested; unsigned MSIX files are not installable for normal users."
} elseif ($CertificateThumbprint -or $env:IRIS_SIGNING_CERT_THUMBPRINT -or $PfxPath -or $env:IRIS_SIGNING_PFX) {
    $results += Add-Result -Status "PASS" -Name "signing input" -Detail "A certificate thumbprint or PFX path was provided."
} else {
    $results += Add-Result -Status "FAIL" -Name "signing input" -Detail "Provide -CertificateThumbprint, IRIS_SIGNING_CERT_THUMBPRINT, -PfxPath, or IRIS_SIGNING_PFX."
}

New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
$readinessPath = Join-Path $distRoot "iris-msix-readiness.txt"
$lines = @(
    "Iris MSIX/App Installer readiness",
    "Generated: $(Get-Date -Format o)",
    "Recommendation: MSIX/App Installer for signed distribution; keep PowerShell ZIP installer as fallback.",
    ""
)
foreach ($result in $results) {
    $line = "[$($result.Status)] $($result.Name): $($result.Detail)"
    Write-Host $line
    $lines += $line
}
Set-Content -LiteralPath $readinessPath -Value $lines -Encoding utf8
Write-Host "Readiness report: $readinessPath"

$failCount = @($results | Where-Object Status -eq "FAIL").Count
if ($ReadinessOnly) {
    if ($failCount -gt 0) {
        Write-Host "MSIX build is not ready on this machine. This readiness check is non-destructive."
    }
    exit 0
}
if ($failCount -gt 0) {
    throw "MSIX build prerequisites are missing. Run with -ReadinessOnly for a non-blocking report."
}

Remove-Item -LiteralPath $msixRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $appRoot | Out-Null

$expectedHash = ((Get-Content -LiteralPath $shaPath -Raw).Trim() -split "\s+")[0]
$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash.ToLowerInvariant()) {
    throw "ZIP SHA256 mismatch. Expected $expectedHash but got $actualHash."
}
Expand-Archive -LiteralPath $zipPath -DestinationPath $appRoot -Force

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap desktop rescap">
  <Identity Name="ProjectIris.LocalAssistant" Publisher="$Publisher" Version="$Version" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>Project Iris</DisplayName>
    <PublisherDisplayName>Alejandro Pinto</PublisherDisplayName>
    <Logo>VFS\ProgramFilesX64\Iris\assets\iris-logo-256.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26200.0" />
  </Dependencies>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Iris" Executable="VFS\ProgramFilesX64\Iris\bin\iris-tauri.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="Project Iris" Description="Local-first Iris assistant" BackgroundColor="transparent" Square150x150Logo="VFS\ProgramFilesX64\Iris\assets\iris-logo-256.png" Square44x44Logo="VFS\ProgramFilesX64\Iris\assets\iris-logo-256.png" />
      <Extensions>
        <desktop:Extension Category="windows.fullTrustProcess" Executable="VFS\ProgramFilesX64\Iris\bin\iris-tauri.exe" />
      </Extensions>
    </Application>
  </Applications>
</Package>
"@
Set-Content -LiteralPath (Join-Path $layoutRoot "AppxManifest.xml") -Value $manifest -Encoding utf8

& $makeAppx pack /d $layoutRoot /p $msixPath /o
if ($LASTEXITCODE -ne 0) {
    throw "makeappx failed with exit code $LASTEXITCODE"
}

if (-not $SkipSigning) {
    $thumbprint = if ($CertificateThumbprint) { $CertificateThumbprint } else { $env:IRIS_SIGNING_CERT_THUMBPRINT }
    $pfx = if ($PfxPath) { $PfxPath } else { $env:IRIS_SIGNING_PFX }
    if ($thumbprint) {
        & $signTool sign /fd SHA256 /sha1 $thumbprint $msixPath
    } else {
        $password = if ($PfxPassword) { $PfxPassword } else { $env:IRIS_SIGNING_PFX_PASSWORD }
        if ($password) {
            & $signTool sign /fd SHA256 /f $pfx /p $password $msixPath
        } else {
            & $signTool sign /fd SHA256 /f $pfx $msixPath
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed with exit code $LASTEXITCODE"
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $msixPath
    if ($signature.SignerCertificate) {
        Export-Certificate -Cert $signature.SignerCertificate -FilePath $certExportPath -Force | Out-Null
        $certHash = (Get-FileHash -LiteralPath $certExportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Set-Content -LiteralPath $certExportShaPath -Value "$certHash  iris-msix-signing.cer" -Encoding ascii
        Write-Host "MSIX signing certificate: $certExportPath"
        Write-Host "MSIX signing certificate SHA256: $certExportShaPath"
        Write-Host "Certificate SHA256: $certHash"
    }
}

$msixHash = (Get-FileHash -LiteralPath $msixPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $msixShaPath -Value "$msixHash  iris-windows.msix" -Encoding ascii
Write-Host "MSIX: $msixPath"
Write-Host "MSIX SHA256: $msixShaPath"
Write-Host "SHA256: $msixHash"
