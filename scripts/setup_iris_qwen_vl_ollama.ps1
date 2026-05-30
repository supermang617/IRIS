param(
    [string] $ModelName = "huihui_ai/qwen3.5-abliterated",
    [string] $Prompt = "In one sentence, say hello as Iris and confirm you are running locally.",
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris Qwen2.5-VL Ollama setup ==="
Write-Host "Model: $ModelName"

if ($DryRun) {
    Write-Host "Dry run only. No model pull or network call performed."
    Write-Host "Setup script is ready."
    exit 0
}

$ollamaCommand = Get-Command ollama -ErrorAction SilentlyContinue
if ($null -eq $ollamaCommand) {
    throw "Ollama command not found. Install Ollama or add it to PATH."
}

try {
    Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 5 | Out-Null
} catch {
    throw "Ollama is not responding at 127.0.0.1:11434. Start Ollama and retry."
}

Write-Host ""
Write-Host "=== Pulling model through Ollama ==="
ollama pull $ModelName
if ($LASTEXITCODE -ne 0) { throw "ollama pull failed" }

Write-Host ""
Write-Host "=== Verifying model exists ==="
$tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 10

$installed = $false
foreach ($model in $tags.models) {
    if ($model.name -eq $ModelName) {
        $installed = $true
    }
}

if (-not $installed) {
    Write-Host "Installed models:"
    $tags.models | ForEach-Object { Write-Host "- $($_.name)" }
    throw "Expected model was not found after pull: $ModelName"
}

Write-Host ""
Write-Host "=== Running Iris local-thinking test ==="
cargo run -p iris-runtime -- ollama-test $ModelName $Prompt
if ($LASTEXITCODE -ne 0) { throw "Iris Ollama loopback test failed" }

Write-Host ""
Write-Host "=== PASS ==="
Write-Host "Model installed and Iris loopback test completed."



