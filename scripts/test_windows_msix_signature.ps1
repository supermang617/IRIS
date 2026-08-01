param(
    [string]$ExpectedPackageVersion = "",
    [string]$ExpectedPublisher = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot

function Get-PngDimensionsFromStream {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $header = New-Object byte[] 24
    if ($Stream.Read($header, 0, $header.Length) -ne $header.Length) {
        throw "PNG is too short to contain an IHDR header: $Name"
    }
    $signature = @(137, 80, 78, 71, 13, 10, 26, 10)
    for ($index = 0; $index -lt $signature.Count; $index++) {
        if ($header[$index] -ne $signature[$index]) {
            throw "MSIX asset is not a valid PNG: $Name"
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
}

$msixPath = Join-Path $repoRoot "release\dist\iris-windows.msix"
$shaPath = "$msixPath.sha256"
$certPath = Join-Path $repoRoot "release\dist\iris-msix-signing.cer"
$certShaPath = "$certPath.sha256"

foreach ($path in @($msixPath, $shaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing signed MSIX artifact: $path"
    }
}

$maximumMsixBytes = 610MB
$msixBytes = (Get-Item -LiteralPath $msixPath).Length
if ($msixBytes -gt $maximumMsixBytes) {
    throw "Signed Iris MSIX exceeds the 610 MiB release budget: $msixBytes bytes."
}

$expected = ((Get-Content -LiteralPath $shaPath -Raw).Trim() -split "\s+")[0]
$actual = (Get-FileHash -LiteralPath $msixPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected.ToLowerInvariant()) {
    throw "MSIX SHA256 mismatch. Expected $expected but got $actual"
}

$signature = Get-AuthenticodeSignature -LiteralPath $msixPath
if (-not $signature.SignerCertificate) {
    throw "MSIX is not signed."
}
if ($signature.Status -ne "Valid") {
    throw "MSIX signature status is not valid: $($signature.Status) $($signature.StatusMessage)"
}
if (-not $signature.TimeStamperCertificate) {
    throw "MSIX signature has no trusted RFC 3161 timestamp."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($msixPath)
try {
    $manifestEntry = $archive.GetEntry("AppxManifest.xml")
    $signatureEntry = $archive.GetEntry("AppxSignature.p7x")
    if (-not $manifestEntry) {
        throw "MSIX is missing AppxManifest.xml."
    }
    if (-not $signatureEntry) {
        throw "MSIX is missing AppxSignature.p7x."
    }
    $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
    try {
        $manifestText = $reader.ReadToEnd()
        [xml]$manifest = $manifestText
    } finally {
        $reader.Dispose()
    }
    foreach ($requiredManifestFragment in @(
            'xmlns:desktop6="http://schemas.microsoft.com/appx/manifest/desktop/windows10/6"',
            'IgnorableNamespaces="uap desktop desktop6 rescap"',
            '<desktop6:FileSystemWriteVirtualization>disabled</desktop6:FileSystemWriteVirtualization>',
            '<rescap:Capability Name="unvirtualizedResources" />'
        )) {
        if (-not $manifestText.Contains($requiredManifestFragment)) {
            throw "Signed MSIX does not preserve the shared Iris AppData root: $requiredManifestFragment"
        }
    }
    $identity = $manifest.Package.Identity
    if ([string]$identity.Publisher -cne [string]$signature.SignerCertificate.Subject) {
        throw "MSIX publisher '$($identity.Publisher)' does not match signer '$($signature.SignerCertificate.Subject)'."
    }
    if ($ExpectedPublisher -and [string]$identity.Publisher -cne $ExpectedPublisher) {
        throw "MSIX publisher '$($identity.Publisher)' does not match expected publisher '$ExpectedPublisher'."
    }
    if ($ExpectedPackageVersion -and [string]$identity.Version -ne $ExpectedPackageVersion) {
        throw "MSIX version '$($identity.Version)' does not match expected version '$ExpectedPackageVersion'."
    }
    $logoAssets = [ordered]@{
        "VFS/ProgramFilesX64/Iris/assets/iris-package-logo-50.png" = 50
        "VFS/ProgramFilesX64/Iris/assets/iris-square-150.png" = 150
        "VFS/ProgramFilesX64/Iris/assets/iris-square-44.png" = 44
    }
    foreach ($entryName in $logoAssets.Keys) {
        $entry = $archive.GetEntry($entryName)
        if (-not $entry) {
            throw "Signed MSIX is missing required logo asset: $entryName"
        }
        $stream = $entry.Open()
        try {
            $dimensions = Get-PngDimensionsFromStream -Stream $stream -Name $entryName
        } finally {
            $stream.Dispose()
        }
        $expectedSize = [int]$logoAssets[$entryName]
        if ($dimensions.Width -ne $expectedSize -or $dimensions.Height -ne $expectedSize) {
            throw (
                "Signed MSIX logo $entryName must be ${expectedSize}x$expectedSize, " +
                "but is $($dimensions.Width)x$($dimensions.Height)."
            )
        }
    }
} finally {
    $archive.Dispose()
}

if ((Test-Path -LiteralPath $certPath -PathType Leaf) -and (Test-Path -LiteralPath $certShaPath -PathType Leaf)) {
    $expectedCert = ((Get-Content -LiteralPath $certShaPath -Raw).Trim() -split "\s+")[0]
    $actualCert = (Get-FileHash -LiteralPath $certPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualCert -ne $expectedCert.ToLowerInvariant()) {
        throw "MSIX signing certificate SHA256 mismatch. Expected $expectedCert but got $actualCert"
    }
}

Write-Host "MSIX signature test passed."
Write-Host "Signature status: $($signature.Status)"
Write-Host "Signer: $($signature.SignerCertificate.Subject)"
Write-Host "Package version: $($identity.Version)"
