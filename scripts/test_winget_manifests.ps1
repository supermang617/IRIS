$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$generator = Join-Path $repoRoot "scripts\generate_winget_manifests.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-winget-manifest-" + [System.Guid]::NewGuid().ToString("N"))
$fakeMsix = Join-Path $testRoot "iris-windows.msix"
$outputRoot = Join-Path $testRoot "output"
$version = "99.98.97"
$updateHelper = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\update_iris_windows.ps1") -Raw

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

    & $generator -PackageVersion $version -MsixPath $fakeMsix -OutputRoot $outputRoot -ReleaseDate "2099-12-31" -SkipWingetValidation -AllowUnsignedTestArtifact

    $manifestRoot = Join-Path $outputRoot "manifests\a\AlejandroPinto\Iris\$version"
    $versionPath = Join-Path $manifestRoot "AlejandroPinto.Iris.yaml"
    $installerPath = Join-Path $manifestRoot "AlejandroPinto.Iris.installer.yaml"
    $localePath = Join-Path $manifestRoot "AlejandroPinto.Iris.locale.en-US.yaml"
    foreach ($path in @($versionPath, $installerPath, $localePath, (Join-Path $outputRoot "iris-winget-manifests.zip"), (Join-Path $outputRoot "iris-winget-manifests.zip.sha256"))) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "WinGet generator omitted required output: $path"
        }
    }

    $installer = Get-Content -LiteralPath $installerPath -Raw
    foreach ($fragment in @(
            "PackageIdentifier: AlejandroPinto.Iris",
            "PackageVersion: $version",
            "InstallerType: msix",
            "UpgradeBehavior: install",
            "releases/download/v$version/iris-windows.msix",
            "PackageIdentifier: Microsoft.Edge",
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
        "Microsoft.Edge",
        "Microsoft.EdgeWebView2Runtime",
        "Ollama.Ollama",
        "Python.Python.3.13",
        "tesseract-ocr.tesseract"
    ) | Sort-Object
    if (($dependencyIds -join "`n") -cne ($expectedDependencies -join "`n")) {
        throw "Generated WinGet dependency set is inaccurate. Expected $($expectedDependencies -join ', '); got $($dependencyIds -join ', ')."
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
    if (-not $locale.Contains("launch Iris from the Windows Start menu") -or
        -not $locale.Contains("ollama pull huihui_ai/gemma-4-abliterated:e2b") -or
        -not $locale.Contains("includes its pinned Python voice packages") -or
        -not $locale.Contains("Microsoft Edge supplies the separately isolated browser engine") -or
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
        & $winget.Source validate --manifest $manifestRoot --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            throw "Official winget manifest validation failed with exit code $LASTEXITCODE"
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
