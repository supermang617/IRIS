param(
    [Parameter(Mandatory = $true)][string]$BrowserRuntimeRoot,
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

$root = [System.IO.Path]::GetFullPath($BrowserRuntimeRoot).TrimEnd("\")
$binRoot = Join-Path $root "node_modules\agent-browser\bin"
$windowsBinary = Join-Path $binRoot "agent-browser-win32-x64.exe"

if (-not (Test-Path -LiteralPath $windowsBinary -PathType Leaf)) {
    throw "Windows agent-browser binary is missing: $windowsBinary"
}

$removed = New-Object System.Collections.Generic.List[object]
foreach ($candidate in @(Get-ChildItem -LiteralPath $binRoot -File -Filter "agent-browser-*" -ErrorAction Stop)) {
    if ($candidate.Name -ieq "agent-browser-win32-x64.exe") {
        continue
    }
    $resolved = [System.IO.Path]::GetFullPath($candidate.FullName)
    if (-not $resolved.StartsWith($binRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to prune a browser binary outside the packaged browser bin directory: $resolved"
    }
    $removed.Add([pscustomobject]@{
            Name = $candidate.Name
            Bytes = $candidate.Length
        }) | Out-Null
    Remove-Item -LiteralPath $resolved -Force
}

$remainingForeign = @(Get-ChildItem -LiteralPath $binRoot -File -Filter "agent-browser-*" |
        Where-Object Name -ne "agent-browser-win32-x64.exe")
if ($remainingForeign.Count -gt 0) {
    throw "Non-Windows agent-browser binaries remain after pruning: $($remainingForeign.Name -join ', ')"
}

$bytesRemoved = [int64](($removed | Measure-Object -Property Bytes -Sum).Sum)
Write-Host "Windows browser payload retained: $windowsBinary"
Write-Host "Pruned $($removed.Count) non-Windows agent-browser binaries ($bytesRemoved bytes)."

if ($PassThru) {
    [pscustomobject]@{
        RemovedFiles = @($removed.Name)
        RemovedCount = $removed.Count
        BytesRemoved = $bytesRemoved
        WindowsBinary = $windowsBinary
        WindowsBinarySha256 = (Get-FileHash -LiteralPath $windowsBinary -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
