$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$generator = Join-Path $repoRoot "scripts\generate_winget_manifests.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-winget-manifest-" + [System.Guid]::NewGuid().ToString("N"))
$fakeMsix = Join-Path $testRoot "iris-windows.msix"
$outputRoot = Join-Path $testRoot "output"
$version = "99.98.97"
$generatorSource = Get-Content -LiteralPath $generator -Raw
$updateHelper = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\update_iris_windows.ps1") -Raw
$msixPackager = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\package_windows_msix.ps1") -Raw
$privacyPath = Join-Path $repoRoot "PRIVACY.md"

if (-not (Test-Path -LiteralPath $privacyPath -PathType Leaf)) {
    throw "WinGet PrivacyUrl must resolve to the repository privacy policy."
}
foreach ($generatorFragment in @(
        "[string]`$ExpectedPublisher",
        "MSIX package identity must be ProjectIris.LocalAssistant",
        "MSIX processor architecture must be x64",
        "must contain exactly the three manifests",
        '$manifestVersion = "1.10.0"',
        '$wingetManifestValidationWarning = -1978335192',
        '$PSNativeCommandUseErrorActionPreference = $false',
        "Manifest has the following dependencies that were not validated",
        "winget validate returned an unexpected manifest warning"
    )) {
    if (-not $generatorSource.Contains($generatorFragment)) {
        throw "WinGet generator is missing production artifact binding: $generatorFragment"
    }
}
foreach ($displayNameFragment in @(
        "<DisplayName>Iris</DisplayName>",
        '<uap:VisualElements DisplayName="Iris"'
    )) {
    if (-not $msixPackager.Contains($displayNameFragment)) {
        throw "MSIX display name must match WinGet PackageName: $displayNameFragment"
    }
}

foreach ($fragment in @(
        '$wingetUpdateNotApplicable = -1978335189',
        '$wingetNoApplicationsFound = -1978335212',
        '$irisUpgradeExitCode -eq $wingetUpdateNotApplicable',
        '$dependencyUpgradeExitCode -eq $wingetUpdateNotApplicable',
        '$installedPackageExitCode -eq $wingetNoApplicationsFound',
        'winget.exe install --id $packageId'
    )) {
    if (-not $updateHelper.Contains($fragment)) {
        throw "WinGet update helper must treat the official no-applicable-update result as success; missing: $fragment"
    }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $fixtureRoot = Join-Path $testRoot "fixture"
    New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $fixtureRoot "fixture.txt") -Value "unsigned test artifact" -Encoding ascii
    [System.IO.Compression.ZipFile]::CreateFromDirectory($fixtureRoot, $fakeMsix)

    $unsignedRejected = $false
    try {
        & $generator -PackageVersion $version -MsixPath $fakeMsix -OutputRoot $outputRoot -SkipWingetValidation
    } catch {
        $unsignedRejected = $true
    }
    if (-not $unsignedRejected) {
        throw "WinGet generator did not reject an unsigned production artifact."
    }

    $mutableUrlRejected = $false
    try {
        & $generator -PackageVersion $version -MsixPath $fakeMsix -InstallerUrl "https://github.com/supermang617/IRIS/releases/download/v1/iris-windows.msix" -OutputRoot $outputRoot -SkipWingetValidation -AllowUnsignedTestArtifact
    } catch {
        $mutableUrlRejected = $_.Exception.Message.Contains("immutable version tag")
    }
    if (-not $mutableUrlRejected) {
        throw "WinGet generator accepted a mutable v1 installer URL."
    }

    $staleVersionRoot = Join-Path $outputRoot "manifests\a\AlejandroPinto\Iris\0.0.1"
    New-Item -ItemType Directory -Force -Path $staleVersionRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $staleVersionRoot "stale.yaml") -Value "stale" -Encoding ascii

    & $generator -PackageVersion $version -MsixPath $fakeMsix -OutputRoot $outputRoot -ReleaseDate "2099-12-31" -AllowUnsignedTestArtifact

    $manifestRoot = Join-Path $outputRoot "manifests\a\AlejandroPinto\Iris\$version"
    $versionPath = Join-Path $manifestRoot "AlejandroPinto.Iris.yaml"
    $installerPath = Join-Path $manifestRoot "AlejandroPinto.Iris.installer.yaml"
    $localePath = Join-Path $manifestRoot "AlejandroPinto.Iris.locale.en-US.yaml"
    foreach ($path in @($versionPath, $installerPath, $localePath, (Join-Path $outputRoot "iris-winget-manifests.zip"), (Join-Path $outputRoot "iris-winget-manifests.zip.sha256"))) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "WinGet generator omitted required output: $path"
        }
    }
    if (Test-Path -LiteralPath $staleVersionRoot) {
        throw "WinGet generator retained stale manifests from a prior version."
    }
    $bundleArchive = [System.IO.Compression.ZipFile]::OpenRead(
        (Join-Path $outputRoot "iris-winget-manifests.zip")
    )
    try {
        $bundleEntries = @(
            $bundleArchive.Entries |
                Where-Object { $_.Name } |
                ForEach-Object { ([string]$_.FullName).Replace("\", "/") } |
                Sort-Object
        )
        $expectedBundleEntries = @(
            "a/AlejandroPinto/Iris/$version/AlejandroPinto.Iris.installer.yaml",
            "a/AlejandroPinto/Iris/$version/AlejandroPinto.Iris.locale.en-US.yaml",
            "a/AlejandroPinto/Iris/$version/AlejandroPinto.Iris.yaml"
        ) | Sort-Object
        if (
            $bundleEntries.Count -ne $expectedBundleEntries.Count -or
            (Compare-Object -ReferenceObject $expectedBundleEntries -DifferenceObject $bundleEntries)
        ) {
            throw "WinGet bundle contains stale or unexpected manifests: $($bundleEntries -join ', ')."
        }
    } finally {
        $bundleArchive.Dispose()
    }

    $installer = Get-Content -LiteralPath $installerPath -Raw
    foreach ($fragment in @(
            "PackageIdentifier: AlejandroPinto.Iris",
            "PackageVersion: $version",
            "InstallerType: msix",
            "UpgradeBehavior: install",
            "releases/download/v$version/iris-windows.msix",
            "PackageIdentifier: Google.Chrome",
            "PackageIdentifier: Microsoft.EdgeWebView2Runtime",
            "PackageIdentifier: Ollama.Ollama",
            "PackageIdentifier: Python.Python.3.13",
            "PackageIdentifier: tesseract-ocr.tesseract",
            "RestrictedCapabilities:",
            "ReleaseDate: 2099-12-31"
        )) {
        if (-not $installer.Contains($fragment)) {
            throw "Generated installer manifest is missing: $fragment"
        }
    }
    $dependencyBlock = [regex]::Match($installer, '(?ms)^Dependencies:\s*(?<body>.*?)^Installers:')
    if (-not $dependencyBlock.Success) {
        throw "Generated installer manifest has no parseable dependency block."
    }
    $dependencyIds = @([regex]::Matches($dependencyBlock.Groups["body"].Value, 'PackageIdentifier:\s*(?<id>[^\r\n]+)') |
            ForEach-Object { $_.Groups["id"].Value.Trim() } |
            Sort-Object)
    $expectedDependencies = @(
        "Google.Chrome",
        "Microsoft.EdgeWebView2Runtime",
        "Ollama.Ollama",
        "Python.Python.3.13",
        "tesseract-ocr.tesseract"
    ) | Sort-Object
    if (($dependencyIds -join "`n") -cne ($expectedDependencies -join "`n")) {
        throw "Generated WinGet dependency set is inaccurate. Expected $($expectedDependencies -join ', '); got $($dependencyIds -join ', ')."
    }
    $capabilityBlock = [regex]::Match(
        $installer,
        '(?ms)^ {4}RestrictedCapabilities:[ \t]*\r?\n(?<body>.*?)^ {4}ReleaseDate:'
    )
    if (-not $capabilityBlock.Success) {
        throw "Generated installer manifest has no parseable restricted-capability block."
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
            "Generated WinGet restricted capabilities are inaccurate. Expected " +
            "$($expectedCapabilities -join ', '); got $($capabilities -join ', ')."
        )
    }
    foreach ($dependency in $expectedDependencies) {
        if (-not $updateHelper.Contains("`"$dependency`"")) {
            throw "WinGet dependency update helper is missing: $dependency"
        }
    }
    $expectedHash = (Get-FileHash -LiteralPath $fakeMsix -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not $installer.Contains("InstallerSha256: $expectedHash")) {
        throw "Generated installer manifest does not use the artifact SHA256."
    }
    $locale = Get-Content -LiteralPath $localePath -Raw
    foreach ($fragment in @(
            "PackageName: Iris",
            "PrivacyUrl: https://github.com/supermang617/IRIS/blob/main/PRIVACY.md",
            "CopyrightUrl: https://github.com/supermang617/IRIS/blob/main/LICENSE",
            "ReleaseNotes: >-",
            "Iris $version is the signed Windows release represented by this",
            "ReleaseNotesUrl: https://github.com/supermang617/IRIS/releases/tag/v$version",
            "DocumentLabel: Download and setup guide",
            "DocumentUrl: https://github.com/supermang617/IRIS/blob/main/docs/download-and-run.md",
            "DocumentLabel: Security policy",
            "DocumentUrl: https://github.com/supermang617/IRIS/security/policy",
            "DocumentLabel: WinGet release and upgrade guide",
            "DocumentUrl: https://github.com/supermang617/IRIS/blob/main/docs/winget-release.md"
        )) {
        if (-not $locale.Contains($fragment)) {
            throw "Generated locale manifest is missing: $fragment"
        }
    }
    if ($locale -match "(?m)^Icons:") {
        throw "Initial WinGet submission must omit verified-publisher-only Icons metadata."
    }
    $tagBlock = [regex]::Match($locale, '(?ms)^Tags:\s*(?<body>.*?)^ReleaseNotes:')
    if (-not $tagBlock.Success) {
        throw "Generated locale manifest has no parseable tag block."
    }
    $tags = @([regex]::Matches($tagBlock.Groups["body"].Value, '(?m)^\s*-\s+(?<tag>[^\r\n]+)') |
            ForEach-Object { $_.Groups["tag"].Value.Trim() })
    $expectedTags = @(
        "ai",
        "assistant",
        "desktop-assistant",
        "hermes",
        "local-ai",
        "local-first",
        "local-llm",
        "memory",
        "ollama",
        "privacy",
        "speech-to-text",
        "text-to-speech",
        "vision",
        "voice-assistant",
        "windows",
        "windows-ai"
    )
    if ($tags.Count -gt 16) {
        throw "Generated locale manifest exceeds the WinGet limit of 16 tags."
    }
    if (($tags | Select-Object -Unique).Count -ne $tags.Count) {
        throw "Generated locale manifest contains duplicate tags."
    }
    if (($tags -join "`n") -cne ($expectedTags -join "`n")) {
        throw "Generated locale manifest tags are incomplete or out of order."
    }
    if (-not $locale.Contains("launch Iris from the Windows Start menu") -or
        -not $locale.Contains("ollama pull huihui_ai/gemma-4-abliterated:e2b") -or
        -not $locale.Contains("includes its pinned Python voice packages") -or
        -not $locale.Contains("Google Chrome supplies the separately isolated browser engine") -or
        -not $locale.Contains("WebView2 powers the Iris desktop shell") -or
        $locale.Contains("pip install kokoro-onnx") -or
        -not $locale.Contains("Start Iris.ps1 -SelfCheck") -or
        $locale.Contains("Start Iris.ps1 --self-check")) {
        throw "Generated WinGet notes must make fresh-install model/voice setup actionable and use canonical syntax only for portable/legacy diagnostics."
    }
    foreach ($buildOnlyDependency in @("Rustlang.Rustup", "Rustlang.Rust.GNU", "Rustlang.Rust.MSVC")) {
        if ($installer.Contains("PackageIdentifier: $buildOnlyDependency")) {
            throw "Generated WinGet manifest must not make build-only Rust a user dependency: $buildOnlyDependency"
        }
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        $validationOutput = @(& $winget.Source validate --manifest $manifestRoot --disable-interactivity 2>&1)
        $validationExitCode = $LASTEXITCODE
        foreach ($line in $validationOutput) {
            Write-Host ([string]$line)
        }
        $warningLines = @($validationOutput |
                ForEach-Object { ([string]$_).Trim() } |
                Where-Object { $_.StartsWith("Manifest Warning:", [System.StringComparison]::Ordinal) })
        if ($validationExitCode -ne 0 -or $warningLines.Count -ne 0) {
            throw "Official winget manifest validation failed with exit code $validationExitCode"
        }
    }

    Write-Host "WinGet manifest generation test passed."
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [System.IO.Path]::GetFullPath($testRoot)
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove WinGet test directory outside temp: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
