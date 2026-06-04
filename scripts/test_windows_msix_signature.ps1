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
if ($signature.SignerCertificate.Subject -notlike "*Iris*") {
    throw "MSIX signer subject is unexpected: $($signature.SignerCertificate.Subject)"
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
