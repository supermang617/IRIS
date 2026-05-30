$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris text and voice milestone verification ==="

cargo fmt --all
if ($LASTEXITCODE -ne 0) { throw "cargo fmt failed" }

cargo build --workspace
if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }

cargo test --workspace
if ($LASTEXITCODE -ne 0) { throw "cargo test failed" }

cargo run -p xtask
if ($LASTEXITCODE -ne 0) { throw "xtask audit failed" }

cargo run -p iris-runtime -- self-check
if ($LASTEXITCODE -ne 0) { throw "iris-runtime self-check failed" }

cargo run -p iris-runtime -- panic-stop-test
if ($LASTEXITCODE -ne 0) { throw "iris-runtime panic-stop test failed" }

cargo run -p iris-runtime -- response-check-test
if ($LASTEXITCODE -ne 0) { throw "iris-runtime response-check test failed" }

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\test_iris_text_voice_response.ps1" -Prompt "In one sentence, say hello as Iris and confirm you are running locally." -NoSpeak
if ($LASTEXITCODE -ne 0) { throw "text prompt plus checked response test failed" }

Write-Host ""
Write-Host "Voice input live test is not run automatically here."
Write-Host "Run this manually when ready:"
Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_voice_text_response.ps1 -TimeoutSeconds 8"

Write-Host ""
Write-Host "PASS: Text and voice milestone verification completed."
