$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$sourceRoot = Join-Path $repoRoot ".iris-runtime\browser"
$pruneScript = Join-Path $repoRoot "scripts\prune_windows_browser_runtime.ps1"
$thirdPartyRoot = Join-Path $repoRoot "third_party\agent-browser"
$controllerArchive = Join-Path $thirdPartyRoot "agent-browser-win32-x64.zip"
$controllerPatch = Join-Path $thirdPartyRoot "iris-default-context-race.patch"
$controllerProvenance = Join-Path $thirdPartyRoot "provenance.json"
$installedController = Join-Path $sourceRoot "node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
$upstreamLicense = Join-Path $sourceRoot "node_modules\agent-browser\LICENSE"
$projectNotice = Join-Path $repoRoot "NOTICE.md"
$packageScript = Join-Path $repoRoot "scripts\package_windows_release.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-browser-prune-" + [System.Guid]::NewGuid().ToString("N"))

try {
    foreach ($required in @(
            $controllerArchive,
            $controllerPatch,
            $controllerProvenance,
            $installedController,
            $upstreamLicense,
            $projectNotice,
            $packageScript
        )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required browser payload input is missing: $required"
        }
    }

    $provenance = Get-Content -LiteralPath $controllerProvenance -Raw | ConvertFrom-Json
    $archiveHash = (Get-FileHash -LiteralPath $controllerArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    $patchHash = (Get-FileHash -LiteralPath $controllerPatch -Algorithm SHA256).Hash.ToLowerInvariant()
    $installedHash = (Get-FileHash -LiteralPath $installedController -Algorithm SHA256).Hash.ToLowerInvariant()
    if (
        $provenance.package.version -ne "0.33.2" -or
        $provenance.source.pull_request_head -ne "c21c9b741a1eb23218c2bc9d165dc9c0af718604" -or
        $archiveHash -ne $provenance.artifact.archive_sha256 -or
        (Get-Item -LiteralPath $controllerArchive).Length -ne [int64]$provenance.artifact.archive_bytes -or
        $patchHash -ne $provenance.source.local_patch_sha256 -or
        $installedHash -ne $provenance.artifact.executable_sha256 -or
        (Get-Item -LiteralPath $installedController).Length -ne [int64]$provenance.artifact.executable_bytes
    ) {
        throw "Pinned browser controller or provenance drifted."
    }

    $artifactExtract = Join-Path $testRoot "artifact"
    New-Item -ItemType Directory -Force -Path $artifactExtract | Out-Null
    Expand-Archive -LiteralPath $controllerArchive -DestinationPath $artifactExtract
    $expandedController = Join-Path $artifactExtract "agent-browser-win32-x64.exe"
    if (
        -not (Test-Path -LiteralPath $expandedController -PathType Leaf) -or
        (Get-FileHash -LiteralPath $expandedController -Algorithm SHA256).Hash.ToLowerInvariant() -ne
        $provenance.artifact.executable_sha256
    ) {
        throw "Pinned browser archive does not expand to the reviewed Windows controller."
    }

    $controllerVersion = (& $installedController --version).Trim()
    if ($LASTEXITCODE -ne 0 -or $controllerVersion -ne "agent-browser 0.33.2") {
        throw "Installed browser controller version mismatch: $controllerVersion"
    }

    $licenseText = Get-Content -LiteralPath $upstreamLicense -Raw
    $noticeText = Get-Content -LiteralPath $projectNotice -Raw
    if (
        -not $licenseText.Contains("Apache License") -or
        -not $licenseText.Contains("Copyright 2025 Vercel Inc.") -or
        -not $noticeText.Contains("packages a modified Windows x64 native controller")
    ) {
        throw "Modified agent-browser license or notice obligations are incomplete."
    }

    $packageScriptText = Get-Content -LiteralPath $packageScript -Raw
    foreach ($requiredManifestBinding in @(
            'modified_controller = $true',
            'upstream_commit = "c21c9b741a1eb23218c2bc9d165dc9c0af718604"',
            'local_patch_sha256 = "b62c7599e3e185e92813f3e891b0e446da54ad1bdc7810f9c6e0bb5750e2a36f"',
            'provisioning_archive_sha256 = "4b7e61f0c106b679f9451f146bdd6a3c7ef33f2287a490605e40ca049240a04f"',
            'binary_sha256 = $browserPrune.WindowsBinarySha256'
        )) {
        if (-not $packageScriptText.Contains($requiredManifestBinding)) {
            throw "Release runtime manifest is missing browser provenance: $requiredManifestBinding"
        }
    }

    $testBin = Join-Path $testRoot "node_modules\agent-browser\bin"
    New-Item -ItemType Directory -Force -Path $testBin | Out-Null
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot "node_modules\agent-browser\bin") -File)) {
        Copy-Item -LiteralPath $file.FullName -Destination $testBin -Force
    }

    $before = @(Get-ChildItem -LiteralPath $testBin -File -Filter "agent-browser-*")
    $foreignBefore = @($before | Where-Object Name -ne "agent-browser-win32-x64.exe")
    if ($foreignBefore.Count -lt 1) {
        throw "Test fixture does not contain non-Windows agent-browser binaries."
    }

    $result = & $pruneScript -BrowserRuntimeRoot $testRoot -PassThru
    if ($result.RemovedCount -ne $foreignBefore.Count) {
        throw "Pruner removed $($result.RemovedCount) files; expected $($foreignBefore.Count)."
    }
    if ($result.BytesRemoved -le 0) {
        throw "Pruner did not report a positive byte reduction."
    }
    if (-not (Test-Path -LiteralPath $result.WindowsBinary -PathType Leaf)) {
        throw "Pruner removed the required Windows browser binary."
    }
    $remaining = @(Get-ChildItem -LiteralPath $testBin -File -Filter "agent-browser-*" |
            Where-Object Name -ne "agent-browser-win32-x64.exe")
    if ($remaining.Count -ne 0) {
        throw "Non-Windows browser binaries remain: $($remaining.Name -join ', ')"
    }

    Write-Host "Windows browser payload pruning test passed."
    Write-Host "Removed: $($result.RemovedCount) files / $($result.BytesRemoved) bytes."
    Write-Host "Iris-patched controller provenance test passed."
    Write-Host "Controller SHA256: $installedHash"
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [System.IO.Path]::GetFullPath($testRoot)
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove browser test directory outside temp: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
