$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

$model = "huihui_ai/qwen3.5-abliterated:9b:9b"
$prompt = if ($args.Count -gt 0) {
    ($args -join " ")
} else {
    "In one sentence, say hello as Iris and confirm you are running locally."
}

Write-Host ""
Write-Host "=== Project Iris selected model ask-local test ==="
Write-Host "Model: $model"
Write-Host "Prompt: $prompt"

cargo run -p iris-runtime -- ask-local $prompt
if ($LASTEXITCODE -ne 0) { throw "Iris selected model ask-local test failed" }

Write-Host ""
Write-Host "=== PASS ==="
git status --short





