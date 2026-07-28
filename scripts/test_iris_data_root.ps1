$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$initializer = Join-Path $repoRoot "scripts\initialize_iris_data_root.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-data-root-" + [System.Guid]::NewGuid().ToString("N"))
$installRoot = Join-Path $testRoot "install"
$dataRoot = Join-Path $testRoot "data"
$previousDataRoot = $env:IRIS_DATA_ROOT
$previousLocalAppData = $env:LOCALAPPDATA

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $installRoot ".iris-data") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $installRoot "diagnostics") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot ".iris-data") | Out-Null
    Set-Content -LiteralPath (Join-Path $installRoot ".iris-data\memories.json") -Value "legacy-memory" -Encoding ascii
    Set-Content -LiteralPath (Join-Path $installRoot "diagnostics\voice.log") -Value "legacy-diagnostic" -Encoding ascii
    Set-Content -LiteralPath (Join-Path $dataRoot ".iris-data\memories.json") -Value "newer-memory" -Encoding ascii

    $env:IRIS_DATA_ROOT = $dataRoot
    $resolved = (& $initializer -InstallRoot $installRoot -PassThru | Select-Object -Last 1)
    if ([System.IO.Path]::GetFullPath($resolved) -ine [System.IO.Path]::GetFullPath($dataRoot)) {
        throw "Initializer returned an unexpected data root: $resolved"
    }
    if ((Get-Content -LiteralPath (Join-Path $dataRoot ".iris-data\memories.json") -Raw).Trim() -ne "newer-memory") {
        throw "Legacy migration overwrote newer per-user data."
    }
    if ((Get-Content -LiteralPath (Join-Path $dataRoot "diagnostics\voice.log") -Raw).Trim() -ne "legacy-diagnostic") {
        throw "Legacy diagnostics were not preserved."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $installRoot ".iris-data\memories.json") -PathType Leaf)) {
        throw "Legacy source data was deleted during migration."
    }

    Remove-Item Env:\IRIS_DATA_ROOT -ErrorAction SilentlyContinue
    $sourceRoot = Join-Path $testRoot "source-checkout"
    New-Item -ItemType Directory -Force -Path (Join-Path $sourceRoot ".git") | Out-Null
    $env:LOCALAPPDATA = Join-Path $testRoot "local-app-data"
    $sourceResolved = (& $initializer -InstallRoot $sourceRoot -PassThru | Select-Object -Last 1)
    if ([System.IO.Path]::GetFullPath($sourceResolved) -ine [System.IO.Path]::GetFullPath($sourceRoot)) {
        throw "Source checkout should retain repo-root state unless IRIS_DATA_ROOT is explicitly set."
    }
    foreach ($relative in @(".iris-data", "diagnostics")) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $relative) -PathType Container)) {
            throw "Source checkout did not initialize repo-root $relative."
        }
    }

    Remove-Item Env:\IRIS_DATA_ROOT -ErrorAction SilentlyContinue
    $portableRoot = Join-Path $testRoot "portable"
    New-Item -ItemType Directory -Force -Path $portableRoot | Out-Null
    $portableResolved = (& $initializer -InstallRoot $portableRoot -PassThru | Select-Object -Last 1)
    $expectedPortableRoot = Join-Path $env:LOCALAPPDATA "Iris"
    if ([System.IO.Path]::GetFullPath($portableResolved) -ine [System.IO.Path]::GetFullPath($expectedPortableRoot)) {
        throw "Extracted/installed Iris should default to LOCALAPPDATA per-user state."
    }

    Write-Host "Iris data-root migration and source/install split test passed."
} finally {
    if ($null -eq $previousDataRoot) {
        Remove-Item Env:\IRIS_DATA_ROOT -ErrorAction SilentlyContinue
    } else {
        $env:IRIS_DATA_ROOT = $previousDataRoot
    }
    if ($null -eq $previousLocalAppData) {
        Remove-Item Env:\LOCALAPPDATA -ErrorAction SilentlyContinue
    } else {
        $env:LOCALAPPDATA = $previousLocalAppData
    }
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolvedTestRoot.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove data-root test directory outside temp: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
