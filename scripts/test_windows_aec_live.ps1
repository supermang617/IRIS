param(
    [switch]$RequireReduction,
    [switch]$AllowConcurrentIris
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$runningIris = @(Get-Process -Name "iris-tauri" -ErrorAction SilentlyContinue)
if ($runningIris.Count -gt 0 -and -not $AllowConcurrentIris) {
    $processIds = ($runningIris | ForEach-Object { $_.Id }) -join ", "
    throw "Close the running Iris process before the live AEC probe (PID: $processIds), or pass -AllowConcurrentIris after coordinating the audio-device conflict."
}

$previousRequirement = $env:IRIS_AEC_PROBE_REQUIRE_REDUCTION
try {
    if ($RequireReduction) {
        $env:IRIS_AEC_PROBE_REQUIRE_REDUCTION = "1"
    } else {
        Remove-Item Env:IRIS_AEC_PROBE_REQUIRE_REDUCTION -ErrorAction SilentlyContinue
    }
    Push-Location $repoRoot
    try {
        & cargo test -p iris-tauri live_windows_voice_capture_dsp_probe -- --ignored --nocapture --test-threads=1
        if ($LASTEXITCODE -ne 0) {
            throw "Windows AEC live probe failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
} finally {
    if ($null -eq $previousRequirement) {
        Remove-Item Env:IRIS_AEC_PROBE_REQUIRE_REDUCTION -ErrorAction SilentlyContinue
    } else {
        $env:IRIS_AEC_PROBE_REQUIRE_REDUCTION = $previousRequirement
    }
}
