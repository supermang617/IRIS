param(
    [string]$ExpectedPackageVersion = "",
    [string]$ExpectedPublisher = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot

$msixPath = Join-Path $repoRoot "release\dist\iris-windows.msix"
$shaPath = "$msixPath.sha256"
$certPath = Join-Path $repoRoot "release\dist\iris-msix-signing.cer"
$certShaPath = "$certPath.sha256"

foreach ($path in @($msixPath, $shaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing signed MSIX artifact: $path"
    }
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
