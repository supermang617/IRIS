param(
    [switch]$RequireReady
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot

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

$script = Join-Path $repoRoot "scripts\package_windows_msix.ps1"
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    throw "Missing MSIX packaging script: $script"
}
$packagingSource = Get-Content -LiteralPath $script -Raw
foreach ($requiredManifestFragment in @(
        'xmlns:desktop6="http://schemas.microsoft.com/appx/manifest/desktop/windows10/6"',
        'IgnorableNamespaces="uap desktop desktop6 rescap"',
        '<desktop6:FileSystemWriteVirtualization>disabled</desktop6:FileSystemWriteVirtualization>',
        '<rescap:Capability Name="unvirtualizedResources" />',
        '<Logo>VFS\ProgramFilesX64\Iris\assets\iris-package-logo-50.png</Logo>',
        'Square150x150Logo="VFS\ProgramFilesX64\Iris\assets\iris-square-150.png"',
        'Square44x44Logo="VFS\ProgramFilesX64\Iris\assets\iris-square-44.png"',
        '$dimensions = Get-PngDimensions -Path $logoPath',
        '/tr $TimestampUrl /td SHA256'
    )) {
    if (-not $packagingSource.Contains($requiredManifestFragment)) {
        throw "MSIX packaging source is missing durable AppData state protection: $requiredManifestFragment"
    }
}
foreach ($requiredSigningFragment in @(
        '$certificateStoreLocation = "CurrentUser"',
        '$certificateStoreLocation = "LocalMachine"',
        'Certificate thumbprint must contain exactly 40 hexadecimal characters',
        '-replace "\s", ""',
        'if ($certificateStoreLocation -eq "LocalMachine")',
        '/sm /sha1 $thumbprint',
        '/td SHA256 /sha1 $thumbprint $msixPath',
        '1.3.6.1.5.5.7.3.3',
        '$Certificate.HasPrivateKey',
        '[string]$Certificate.Subject -ceq $ExpectedPublisher',
        'X509KeyStorageFlags]::EphemeralKeySet',
        '[System.Security.SecurityElement]::Escape($Publisher)',
        'Encoded AppxManifest publisher does not round-trip',
        '$maximumMsixBytes = 610MB',
        'Iris MSIX exceeds the 610 MiB release budget',
        '$signature.Status -ne "Valid"',
        '$signature.TimeStamperCertificate',
        '$signTool verify /pa /v',
        'foreach ($staleCertificateArtifact in @($certExportPath, $certExportShaPath))',
        'Remove-Item -LiteralPath $staleCertificateArtifact -Force'
    )) {
    if (-not $packagingSource.Contains($requiredSigningFragment)) {
        throw "MSIX packaging source is missing certificate-store-aware signing: $requiredSigningFragment"
    }
}

$logoAssets = [ordered]@{
    "iris-package-logo-50.png" = 50
    "iris-square-150.png" = 150
    "iris-square-44.png" = 44
}
foreach ($logoName in $logoAssets.Keys) {
    $logoPath = Join-Path $repoRoot "assets\$logoName"
    if (-not (Test-Path -LiteralPath $logoPath -PathType Leaf)) {
        throw "MSIX logo asset is missing: $logoPath"
    }
    $dimensions = Get-PngDimensions -Path $logoPath
    $expectedSize = [int]$logoAssets[$logoName]
    if ($dimensions.Width -ne $expectedSize -or $dimensions.Height -ne $expectedSize) {
        throw (
            "MSIX logo $logoName must be ${expectedSize}x$expectedSize, " +
            "but is $($dimensions.Width)x$($dimensions.Height)."
        )
    }
}

$readinessRejected = $false
try {
    & $script -ReadinessOnly
} catch {
    $readinessRejected = $true
}

$report = Join-Path $repoRoot "release\dist\iris-msix-readiness.txt"
if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
    throw "MSIX readiness report was not written: $report"
}
$content = Get-Content -LiteralPath $report -Raw
foreach ($required in @(
        "Iris MSIX/App Installer readiness",
        "MSIX/App Installer",
        "makeappx.exe",
        "signtool.exe",
        "signing input",
        "Overall production readiness:"
    )) {
    if (-not $content.Contains($required)) {
        throw "MSIX readiness report missing: $required"
    }
}

$hasFailure = $content.Contains("[FAIL]")
$reportsReady = $content.Contains("Overall production readiness: READY")
$reportsNotReady = $content.Contains("Overall production readiness: NOT READY")
if ($reportsNotReady -and -not $readinessRejected) {
    throw "Readiness script returned success despite reporting NOT READY."
}
if ($reportsReady -and $readinessRejected) {
    throw "Readiness script rejected a report that says READY."
}
if ($hasFailure -and -not $reportsNotReady) {
    throw "Readiness report has failures but does not say NOT READY."
}
if (-not $hasFailure -and -not $reportsReady) {
    throw "Readiness report has no failures but does not say READY."
}
if ($RequireReady -and -not $reportsReady) {
    throw "A production-ready signed installer was required, but the MSIX readiness report is NOT READY."
}

if ($reportsReady) {
    Write-Host "Windows signed-installer readiness is READY."
} else {
    Write-Host "Windows signed-installer readiness accurately reported NOT READY."
}
