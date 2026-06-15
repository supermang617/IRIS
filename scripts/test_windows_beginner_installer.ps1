$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$bundlePath = Join-Path $repoRoot "release\dist\iris-windows-installer.zip"
$bundleShaPath = "$bundlePath.sha256"

foreach ($path in @($bundlePath, $bundleShaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing beginner installer test input: $path"
    }
}

$expectedBundleHash = ((Get-Content -LiteralPath $bundleShaPath -Raw).Trim() -split "\s+")[0].ToLowerInvariant()
$actualBundleHash = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualBundleHash -ne $expectedBundleHash) {
    throw "Beginner installer bundle SHA256 mismatch."
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-beginner-installer-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

try {
    Expand-Archive -LiteralPath $bundlePath -DestinationPath $testRoot -Force

    $required = @(
        "Install Iris.bat",
        "README.txt",
        "install-iris-windows.ps1",
        "iris-windows.zip",
        "iris-windows.zip.sha256"
    )
    foreach ($relative in $required) {
        $path = Join-Path $testRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Beginner installer bundle is missing $relative"
        }
    }

    $payloadZip = Join-Path $testRoot "iris-windows.zip"
    $payloadSha = Join-Path $testRoot "iris-windows.zip.sha256"
    $expectedPayloadHash = ((Get-Content -LiteralPath $payloadSha -Raw).Trim() -split "\s+")[0].ToLowerInvariant()
    $actualPayloadHash = (Get-FileHash -LiteralPath $payloadZip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualPayloadHash -ne $expectedPayloadHash) {
        throw "Beginner installer contains a payload ZIP with an invalid SHA256."
    }

    $launcher = Get-Content -LiteralPath (Join-Path $testRoot "Install Iris.bat") -Raw
    foreach ($requiredText in @(
        "install-iris-windows.ps1",
        "-SourceZip",
        "iris-windows.zip",
        "-Sha256Path",
        "iris-windows.zip.sha256",
        "-RunSetup",
        "-LaunchAfterInstall"
    )) {
        if (-not $launcher.Contains($requiredText)) {
            throw "Beginner installer launcher is missing $requiredText"
        }
    }

    $installer = Get-Content -LiteralPath (Join-Path $testRoot "install-iris-windows.ps1") -Raw
    $setupPosition = $installer.IndexOf('if ($RunSetup)')
    $selfCheckPosition = $installer.IndexOf('"Start Iris.ps1") --self-check')
    if ($setupPosition -lt 0 -or $selfCheckPosition -lt 0 -or $setupPosition -gt $selfCheckPosition) {
        throw "Installer must run the setup wizard before the final live self-check."
    }

    Write-Host "Beginner installer bundle smoke test passed."
    Write-Host "SHA256: $actualBundleHash"
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
