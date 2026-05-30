$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris HUD readiness gate ==="
Write-Host ""

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Command
    )

    Write-Host ""
    Write-Host "=== $Name ==="

    & $Command

    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

Invoke-Step "Cargo format" {
    cargo fmt --all
}

Invoke-Step "Cargo build" {
    cargo build --workspace
}

Invoke-Step "Cargo test" {
    cargo test --workspace
}

Invoke-Step "Xtask audit" {
    cargo run -p xtask
}

Invoke-Step "Runtime self-check" {
    cargo run -p iris-runtime -- self-check
}

Invoke-Step "Runtime UI status" {
    cargo run -p iris-runtime -- ui-status
}

Invoke-Step "Runtime voice status" {
    cargo run -p iris-runtime -- voice-status
}

Invoke-Step "Runtime push-to-talk visible-state test" {
    cargo run -p iris-runtime -- voice-ptt-state-test
}

Invoke-Step "Runtime response post-check test" {
    cargo run -p iris-runtime -- response-check-test
}

Invoke-Step "Current milestone diagnostics" {
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\diagnose_iris_current_milestone.ps1"
}

Write-Host ""
Write-Host "=== HUD readiness result ==="
Write-Host "PASS: Iris is ready for the next decision point."
Write-Host ""
Write-Host "Next decision required before coding:"
Write-Host "Approve adding the minimal GUI dependencies for the desktop HUD."
Write-Host ""
Write-Host "Candidate dependency direction:"
Write-Host "- winit"
Write-Host "- egui"
Write-Host ""
Write-Host "Do not add GUI dependencies until explicitly approved."
