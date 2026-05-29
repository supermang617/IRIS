$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

$model = "huihui_ai/qwen2.5-vl-abliterated:3b"
$prompt = "In one sentence, say hello as Iris and confirm you are running locally."

Write-Host ""
Write-Host "=== Project Iris selected model smoke test ==="
Write-Host "Model: $model"

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

cargo run -p iris-runtime -- model-plan
if ($LASTEXITCODE -ne 0) { throw "iris-runtime model-plan failed" }

cargo run -p iris-runtime -- prompt-preview "hello iris contact@example.com password=secret"
if ($LASTEXITCODE -ne 0) { throw "iris-runtime prompt-preview failed" }

Write-Host ""
Write-Host "=== Ollama availability ==="

try {
    $tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 5
} catch {
    throw "Ollama is not responding at 127.0.0.1:11434."
}

$installed = $false
foreach ($tag in $tags.models) {
    if ($tag.name -eq $model) {
        $installed = $true
    }
}

if (-not $installed) {
    Write-Host "Installed models:"
    $tags.models | ForEach-Object { Write-Host "- $($_.name)" }
    throw "Selected model is not installed: $model"
}

Write-Host ""
Write-Host "=== Iris local thinking smoke test ==="

cargo run -p iris-runtime -- ollama-test $model $prompt
if ($LASTEXITCODE -ne 0) { throw "Iris selected model smoke test failed" }

Write-Host ""
Write-Host "=== PASS ==="
git status --short
