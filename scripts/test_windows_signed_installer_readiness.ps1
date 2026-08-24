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
        '$Certificate.SubjectName.RawData',
        '$Certificate.IssuerName.RawData',
        '[string]$Certificate.Subject -ieq [string]$Certificate.Issuer',
        '[switch]$AllowSelfSignedDevelopmentCertificate',
        'X509RevocationMode]::NoCheck',
        'DisableCertificateDownloads',
        'X509VerificationFlags]::NoFlag',
        '$chain.ChainPolicy.ApplicationPolicy.Add(',
        'offline system chain trust',
        'Windows public root inventory',
        '"AuthRoot"',
        'A system-trusted enterprise chain may still be eligible for managed deployment',
        "production readiness remains NOT READY",
        '-not $AllowSelfSignedDevelopmentCertificate',
        'development_self_signed_opt_in=',
        'Signing input readiness:',
        'signed_artifact_verified=false',
        'clean_vm_wack_lifecycle_verified=false',
        '$PSBoundParameters.ContainsKey("CertificateThumbprint")',
        '$PSBoundParameters.ContainsKey("PfxPath")',
        'Provide exactly one explicit signing source',
        'Both IRIS_SIGNING_CERT_THUMBPRINT and IRIS_SIGNING_PFX are set',
        'portable ZIP integrity',
        'Portable ZIP SHA-256 mismatch',
        '$expectedSignerThumbprint',
        'MSIX signer thumbprint does not match the exact certificate validated during readiness',
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

$report = Join-Path $repoRoot "release\dist\iris-msix-readiness.txt"
$selfSignedTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-msix-self-signed-" + [System.Guid]::NewGuid().ToString("N"))
$selfSignedPfx = Join-Path $selfSignedTestRoot "self-signed.pfx"
$selfSignedPassword = [System.Guid]::NewGuid().ToString("N")
$selfSignedRsa = $null
$selfSignedCertificate = $null
$fakeCaRsa = $null
$fakeCa = $null
$fakeLeafRsa = $null
$fakeLeafPublic = $null
$fakeLeaf = $null
$signingEnvironmentNames = @(
    "IRIS_SIGNING_CERT_THUMBPRINT",
    "IRIS_SIGNING_PFX",
    "IRIS_SIGNING_PFX_PASSWORD"
)
$savedSigningEnvironment = @{}
foreach ($environmentName in $signingEnvironmentNames) {
    $environmentItem = Get-Item -LiteralPath "Env:$environmentName" -ErrorAction SilentlyContinue
    $savedSigningEnvironment[$environmentName] = [pscustomobject]@{
        Exists = $null -ne $environmentItem
        Value = if ($environmentItem) { [string]$environmentItem.Value } else { "" }
    }
    Remove-Item -LiteralPath "Env:$environmentName" -ErrorAction SilentlyContinue
}
try {
    New-Item -ItemType Directory -Path $selfSignedTestRoot | Out-Null
    $selfSignedRsa = [System.Security.Cryptography.RSA]::Create(2048)
    $selfSignedRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        "CN=Iris Readiness Self-Signed Test",
        $selfSignedRsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $selfSignedUsages = [System.Security.Cryptography.OidCollection]::new()
    [void]$selfSignedUsages.Add([System.Security.Cryptography.Oid]::new("1.3.6.1.5.5.7.3.3"))
    $selfSignedRequest.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new(
            $selfSignedUsages,
            $false
        )
    )
    $selfSignedCertificate = $selfSignedRequest.CreateSelfSigned(
        [DateTimeOffset]::UtcNow.AddMinutes(-5),
        [DateTimeOffset]::UtcNow.AddDays(1)
    )
    [System.IO.File]::WriteAllBytes(
        $selfSignedPfx,
        $selfSignedCertificate.Export(
            [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx,
            $selfSignedPassword
        )
    )

    $env:IRIS_SIGNING_CERT_THUMBPRINT = "A" * 40
    & $script `
        -ReadinessOnly `
        -AllowIncompleteReadiness `
        -PfxPath $selfSignedPfx `
        -PfxPassword $selfSignedPassword `
        -Publisher "CN=Iris Readiness Self-Signed Test"
    Remove-Item -LiteralPath Env:IRIS_SIGNING_CERT_THUMBPRINT -ErrorAction SilentlyContinue
    $selfSignedReport = Get-Content -LiteralPath $report -Raw
    if (-not $selfSignedReport.Contains("[PASS] signing input: PFX path exists.")) {
        throw "An explicit PFX did not take precedence over an ambient certificate thumbprint."
    }
    if (-not $selfSignedReport.Contains("[FAIL] certificate authority issuance:")) {
        throw "MSIX readiness did not reject an in-memory self-signed code-signing certificate."
    }
    if (-not $selfSignedReport.Contains("[FAIL] offline system chain trust:")) {
        throw "MSIX readiness did not reject the untrusted self-signed certificate chain."
    }
    if (-not $selfSignedReport.Contains("[WARN] Windows public root inventory:")) {
        throw "MSIX readiness did not flag the self-signed certificate's non-public root inventory."
    }
    if (-not $selfSignedReport.Contains("Signing input readiness: NOT READY")) {
        throw "MSIX readiness incorrectly reported a self-signed certificate as production READY."
    }

    & $script `
        -ReadinessOnly `
        -AllowIncompleteReadiness `
        -CertificateThumbprint ("A" * 40) `
        -PfxPath $selfSignedPfx `
        -PfxPassword $selfSignedPassword `
        -Publisher "CN=Iris Readiness Self-Signed Test"
    $ambiguousInputReport = Get-Content -LiteralPath $report -Raw
    if (-not $ambiguousInputReport.Contains("[FAIL] signing input: Provide exactly one explicit signing source")) {
        throw "MSIX readiness did not reject simultaneous explicit thumbprint and PFX inputs."
    }
    if (-not $ambiguousInputReport.Contains("Signing input readiness: NOT READY")) {
        throw "Ambiguous explicit signing inputs incorrectly reported READY."
    }

    $env:IRIS_SIGNING_CERT_THUMBPRINT = "A" * 40
    $env:IRIS_SIGNING_PFX = $selfSignedPfx
    & $script `
        -ReadinessOnly `
        -AllowIncompleteReadiness `
        -Publisher "CN=Iris Readiness Self-Signed Test"
    Remove-Item -LiteralPath Env:IRIS_SIGNING_CERT_THUMBPRINT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath Env:IRIS_SIGNING_PFX -ErrorAction SilentlyContinue
    $ambiguousEnvironmentReport = Get-Content -LiteralPath $report -Raw
    if (-not $ambiguousEnvironmentReport.Contains("[FAIL] signing input: Both IRIS_SIGNING_CERT_THUMBPRINT and IRIS_SIGNING_PFX are set.")) {
        throw "MSIX readiness did not reject simultaneous ambient thumbprint and PFX inputs."
    }
    if (-not $ambiguousEnvironmentReport.Contains("Signing input readiness: NOT READY")) {
        throw "Ambiguous ambient signing inputs incorrectly reported READY."
    }

    & $script `
        -ReadinessOnly `
        -AllowIncompleteReadiness `
        -AllowSelfSignedDevelopmentCertificate `
        -PfxPath $selfSignedPfx `
        -PfxPassword $selfSignedPassword `
        -Publisher "CN=Iris Readiness Self-Signed Test"
    $developmentReport = Get-Content -LiteralPath $report -Raw
    if (-not $developmentReport.Contains("[WARN] certificate authority issuance:")) {
        throw "Explicit self-signed development signing did not remain visibly non-production."
    }
    if (-not $developmentReport.Contains("[WARN] offline system chain trust:")) {
        throw "Explicit untrusted self-signed development signing did not warn about chain trust."
    }
    if (-not $developmentReport.Contains("[WARN] Windows public root inventory:")) {
        throw "Explicit self-signed development signing did not warn about public trust."
    }
    if (-not $developmentReport.Contains("Signing input readiness: NOT READY")) {
        throw "Explicit self-signed development signing incorrectly reported production READY."
    }
    if (-not $developmentReport.Contains("development_self_signed_opt_in=true")) {
        throw "Explicit self-signed development signing was not recorded in readiness evidence."
    }

    $fakeCaRsa = [System.Security.Cryptography.RSA]::Create(2048)
    $fakeCaRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        "CN=Iris Untrusted Test CA",
        $fakeCaRsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $fakeCaRequest.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new(
            $true,
            $false,
            0,
            $true
        )
    )
    $fakeCaRequest.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
            [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign,
            $true
        )
    )
    $fakeCa = $fakeCaRequest.CreateSelfSigned(
        [DateTimeOffset]::UtcNow.AddMinutes(-5),
        [DateTimeOffset]::UtcNow.AddDays(1)
    )
    $fakeLeafRsa = [System.Security.Cryptography.RSA]::Create(2048)
    $fakeLeafRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        "CN=Iris Untrusted Issued Test",
        $fakeLeafRsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $fakeLeafUsages = [System.Security.Cryptography.OidCollection]::new()
    [void]$fakeLeafUsages.Add([System.Security.Cryptography.Oid]::new("1.3.6.1.5.5.7.3.3"))
    $fakeLeafRequest.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new(
            $fakeLeafUsages,
            $false
        )
    )
    $fakeLeafPublic = $fakeLeafRequest.Create(
        $fakeCa,
        [DateTimeOffset]::UtcNow.AddMinutes(-5),
        [DateTimeOffset]::UtcNow.AddHours(12),
        [System.Guid]::NewGuid().ToByteArray()
    )
    $fakeLeaf = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::CopyWithPrivateKey(
        $fakeLeafPublic,
        $fakeLeafRsa
    )
    $fakePfxCollection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
    [void]$fakePfxCollection.Add($fakeLeaf)
    [void]$fakePfxCollection.Add($fakeCa)
    $fakePfx = Join-Path $selfSignedTestRoot "untrusted-issued.pfx"
    [System.IO.File]::WriteAllBytes(
        $fakePfx,
        $fakePfxCollection.Export(
            [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx,
            $selfSignedPassword
        )
    )
    & $script `
        -ReadinessOnly `
        -AllowIncompleteReadiness `
        -PfxPath $fakePfx `
        -PfxPassword $selfSignedPassword `
        -Publisher "CN=Iris Untrusted Issued Test"
    $untrustedIssuedReport = Get-Content -LiteralPath $report -Raw
    if (-not $untrustedIssuedReport.Contains("[PASS] certificate authority issuance:")) {
        throw "Untrusted issued-certificate fixture did not exercise the non-self-issued path."
    }
    if (-not $untrustedIssuedReport.Contains("[FAIL] offline system chain trust:")) {
        throw "MSIX readiness accepted a leaf issued by an untrusted local fake CA."
    }
    if (-not $untrustedIssuedReport.Contains("[WARN] Windows public root inventory:")) {
        throw "MSIX readiness did not flag the fake CA's non-public root inventory."
    }
    if (-not $untrustedIssuedReport.Contains("Signing input readiness: NOT READY")) {
        throw "MSIX readiness incorrectly reported an untrusted issued certificate as production READY."
    }

    $checksumPath = Join-Path $repoRoot "release\dist\iris-windows.zip.sha256"
    $checksumMutex = [System.Threading.Mutex]::new(
        $false,
        "Local\ProjectIris.SignedReadinessChecksumTest"
    )
    $checksumMutexHeld = $false
    $originalChecksumBytes = $null
    $createdPortableFixture = $false
    try {
        try {
            $checksumMutexHeld = $checksumMutex.WaitOne([TimeSpan]::FromMinutes(2))
        } catch [System.Threading.AbandonedMutexException] {
            $checksumMutexHeld = $true
        }
        if (-not $checksumMutexHeld) {
            throw "Timed out waiting for the signed-readiness checksum test mutex."
        }
        $portableZipPath = Join-Path $repoRoot "release\dist\iris-windows.zip"
        $zipExists = Test-Path -LiteralPath $portableZipPath -PathType Leaf
        $checksumExists = Test-Path -LiteralPath $checksumPath -PathType Leaf
        if ($zipExists -ne $checksumExists) {
            throw "Portable ZIP readiness fixtures are incomplete; expected both ZIP and checksum or neither."
        }
        if (-not $zipExists) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $portableZipPath) | Out-Null
            [System.IO.File]::WriteAllBytes(
                $portableZipPath,
                [System.Text.Encoding]::ASCII.GetBytes("Iris readiness fixture")
            )
            $fixtureHash = (Get-FileHash -LiteralPath $portableZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
            [System.IO.File]::WriteAllText(
                $checksumPath,
                "$fixtureHash  iris-windows.zip`r`n",
                [System.Text.Encoding]::ASCII
            )
            $createdPortableFixture = $true
        }
        $originalChecksumBytes = [System.IO.File]::ReadAllBytes($checksumPath)
        Set-Content `
            -LiteralPath $checksumPath `
            -Value "$("0" * 64)  iris-windows.zip" `
            -Encoding ascii
        & $script `
            -ReadinessOnly `
            -AllowIncompleteReadiness `
            -PfxPath $selfSignedPfx `
            -PfxPassword $selfSignedPassword `
            -Publisher "CN=Iris Readiness Self-Signed Test"
        $staleChecksumReport = Get-Content -LiteralPath $report -Raw
        if (-not $staleChecksumReport.Contains("[FAIL] portable ZIP integrity: Portable ZIP SHA-256 mismatch.")) {
            throw "MSIX readiness did not reject a stale portable ZIP checksum."
        }
        if (-not $staleChecksumReport.Contains("Signing input readiness: NOT READY")) {
            throw "A stale portable ZIP checksum incorrectly reported signing input readiness as READY."
        }
    } finally {
        if ($checksumMutexHeld) {
            if ($null -ne $originalChecksumBytes) {
                [System.IO.File]::WriteAllBytes($checksumPath, $originalChecksumBytes)
            }
            if ($createdPortableFixture) {
                Remove-Item -LiteralPath $portableZipPath, $checksumPath -Force
            }
            $checksumMutex.ReleaseMutex()
        }
        $checksumMutex.Dispose()
    }
} finally {
    foreach ($environmentName in $signingEnvironmentNames) {
        $savedEnvironmentItem = $savedSigningEnvironment[$environmentName]
        if ($savedEnvironmentItem.Exists) {
            Set-Item -LiteralPath "Env:$environmentName" -Value $savedEnvironmentItem.Value
        } else {
            Remove-Item -LiteralPath "Env:$environmentName" -ErrorAction SilentlyContinue
        }
    }
    foreach ($testCertificate in @($fakeLeaf, $fakeLeafPublic, $fakeCa)) {
        if ($testCertificate) {
            $testCertificate.Dispose()
        }
    }
    if ($fakeLeafRsa) {
        $fakeLeafRsa.Dispose()
    }
    if ($fakeCaRsa) {
        $fakeCaRsa.Dispose()
    }
    if ($selfSignedCertificate) {
        $selfSignedCertificate.Dispose()
    }
    if ($selfSignedRsa) {
        $selfSignedRsa.Dispose()
    }
    if (Test-Path -LiteralPath $selfSignedTestRoot -PathType Container) {
        Remove-Item -LiteralPath $selfSignedTestRoot -Recurse -Force
    }
}

$readinessRejected = $false
try {
    & $script -ReadinessOnly
} catch {
    $readinessRejected = $true
}

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
        "Signing input readiness:",
        "Overall production readiness:"
    )) {
    if (-not $content.Contains($required)) {
        throw "MSIX readiness report missing: $required"
    }
}

$hasFailure = $content.Contains("[FAIL]")
$reportsReady = $content.Contains("Signing input readiness: READY")
$reportsNotReady = $content.Contains("Signing input readiness: NOT READY")
$reportsProductionNotReady = $content.Contains("Overall production readiness: NOT READY")
if (-not $reportsProductionNotReady -or $content.Contains("Overall production readiness: READY")) {
    throw "Readiness-only checks must never claim overall production readiness before signed-artifact and clean-VM lifecycle verification."
}
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
    throw "A ready production signing input was required, but the MSIX signing input report is NOT READY."
}

if ($reportsReady) {
    Write-Host "Windows signing input is READY; overall production readiness still requires signed-artifact and clean-VM WACK/lifecycle verification."
} else {
    Write-Host "Windows signing-input readiness accurately reported NOT READY."
}
