$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

$defaultModel = "huihui_ai/qwen3.5-abliterated:9b"
$model = $args[0]

$prompt = if ($args.Count -gt 1) {
    ($args[1..($args.Count - 1)] -join " ")
} else {
    "In one sentence, say hello as Iris and confirm you are running locally."
}

Write-Host ""
Write-Host "=== Project Iris local thinking test ==="

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
Write-Host "=== Ollama check ==="

$ollamaCommand = Get-Command ollama -ErrorAction SilentlyContinue
if ($null -eq $ollamaCommand) {
    Write-Host "Ollama command not found."
    Write-Host "Install/start Ollama before local model testing."
    git status --short
    exit 0
}

try {
    $tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 5
} catch {
    Write-Host "Ollama is not responding at 127.0.0.1:11434."
    Write-Host "Start Ollama, then rerun this script."
    git status --short
    exit 0
}

Write-Host ""
Write-Host "=== Installed Ollama models ==="

if ($null -eq $tags.models -or $tags.models.Count -eq 0) {
    Write-Host "No Ollama models installed."
    Write-Host "Run:"
    Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_qwen_vl_ollama.ps1"
    git status --short
    exit 0
}

$tags.models | ForEach-Object {
    Write-Host "- $($_.name)"
}

if ([string]::IsNullOrWhiteSpace($model)) {
    $exact = $tags.models |
        Where-Object { $_.name -eq $defaultModel } |
        Select-Object -First 1

    if ($null -ne $exact) {
        $model = $defaultModel
    } else {
        $candidate = $tags.models |
            Where-Object { $_.name -match "qwen|qwq" } |
            Select-Object -First 1

        if ($null -eq $candidate) {
            Write-Host ""
            Write-Host "No Qwen-family model detected."
            Write-Host "Run:"
            Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_qwen_vl_ollama.ps1"
            git status --short
            exit 0
        }

        $model = $candidate.name
    }
}

Write-Host ""
Write-Host "=== Running Iris local thinking test ==="
Write-Host "Model: $model"
Write-Host "Prompt: $prompt"

cargo run -p iris-runtime -- ollama-test $model $prompt
if ($LASTEXITCODE -ne 0) { throw "iris-runtime Ollama loopback test failed" }

Write-Host ""
Write-Host "=== Git status ==="
git status --short


