$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris Kokoro voice milestone verification ==="

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

Invoke-IrisStep "Runtime self-check" {
    cargo run -p iris-runtime -- self-check
}

Invoke-IrisStep "Runtime voice status" {
    cargo run -p iris-runtime -- voice-status
}

Invoke-IrisStep "Runtime Panic Stop test" {
    cargo run -p iris-runtime -- panic-stop-test
}

Invoke-IrisStep "Runtime response post-check test" {
    cargo run -p iris-runtime -- response-check-test
}

Invoke-IrisStep "Kokoro direct voice dry-run" {
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\speak_iris_kokoro.ps1" -DryRun
}

Invoke-IrisStep "Kokoro direct voice playback" {
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\speak_iris_kokoro.ps1" `
        -Text "Hello, I am Iris. My Kokoro voice milestone check is working." `
        -Voice "af_heart" `
        -Speed 0.95 `
        -WakeSignalMs 900 `
        -LeadSilenceMs 300 `
        -TailSilenceMs 300
}

Invoke-IrisStep "Text prompt to checked Kokoro response dry-run" {
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\test_iris_text_voice_response.ps1" -DryRun
}

Invoke-IrisStep "Text prompt to checked Kokoro response" {
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\test_iris_text_voice_response.ps1" `
        -Prompt "Hello Iris. In one short sentence, confirm your local Kokoro voice is working." `
        -TtsBackend "Kokoro" `
        -KokoroVoice "af_heart" `
        -KokoroSpeed 0.95 `
        -KokoroWakeSignalMs 900 `
        -KokoroLeadSilenceMs 300 `
        -KokoroTailSilenceMs 300
}

Write-Host ""
Write-Host "Voice input live test is not run automatically inside this verifier."
Write-Host "Manual voice input test command:"
Write-Host 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_voice_text_response.ps1 -TimeoutSeconds 10'

Write-Host ""
Write-Host "PASS: Kokoro voice milestone verification completed."
