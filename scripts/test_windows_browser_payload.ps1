$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$sourceRoot = Join-Path $repoRoot ".iris-runtime\browser"
$pruneScript = Join-Path $repoRoot "scripts\prune_windows_browser_runtime.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-browser-prune-" + [System.Guid]::NewGuid().ToString("N"))

try {
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
