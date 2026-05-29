$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

function Invoke-IrisStep {
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

Write-Host "Project Iris verification started."

Invoke-IrisStep "Git status before verification" {
    git status --short
}

Invoke-IrisStep "Cargo format" {
    cargo fmt --all
}

Invoke-IrisStep "Cargo build" {
    cargo build --workspace
}

Invoke-IrisStep "Cargo test" {
    cargo test --workspace
}

Invoke-IrisStep "Xtask audit" {
    cargo run -p xtask
}

Invoke-IrisStep "Runtime demo" {
    cargo run -p iris-runtime
}

Invoke-IrisStep "Runtime self-check" {
    cargo run -p iris-runtime -- self-check
}

Invoke-IrisStep "Runtime model-plan" {
    cargo run -p iris-runtime -- model-plan
}

Invoke-IrisStep "Runtime prompt-preview" {
    cargo run -p iris-runtime -- prompt-preview "hello iris contact@example.com password=secret"
}

Invoke-IrisStep "Runtime ask mode" {
    cargo run -p iris-runtime -- ask "hello iris contact@example.com password=secret"
}

Invoke-IrisStep "Runtime Ollama test readiness" {
    cargo run -p iris-runtime -- ollama-test
}

Invoke-IrisStep "Git status after verification" {
    git status --short
}

Write-Host ""
Write-Host "Project Iris verification completed successfully."
