param(
    [string] $ExpectedModel = "huihui_ai/qwen3.5-abliterated:9b",
    [int] $ExpectedContext = 8192
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

$paths = @(
    "config\iris-runtime-manifest.dev.toml",
    "config\iris-runtime-manifest.example.toml"
)

foreach ($path in $paths) {
    if (-not (Test-Path $path)) {
        throw "Missing manifest: $path"
    }

    $content = Get-Content -Raw -Path $path

    foreach ($key in @("active_model_id", "text_model_id", "vision_model_id")) {
        if (-not $content.Contains("$key = `"$ExpectedModel`"")) {
            throw "$path does not set $key to $ExpectedModel"
        }
    }

    if (-not $content.Contains("num_ctx = $ExpectedContext")) {
        throw "$path does not set num_ctx = $ExpectedContext"
    }

    if (-not $content.Contains("unified_text_and_vision = true")) {
        throw "$path does not enable unified text and vision"
    }

    if ($content -match "clipboard") {
        throw "$path contains audit-forbidden raw token: clipboard"
    }
}

Write-Host "PASS: unified dense model manifest verified"


