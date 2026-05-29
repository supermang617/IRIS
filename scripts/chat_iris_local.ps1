$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

if ($args.Count -gt 0) {
    $prompt = $args -join " "
    cargo run -p iris-runtime -- chat-local $prompt
} else {
    cargo run -p iris-runtime -- chat-local
}

if ($LASTEXITCODE -ne 0) { throw "Iris local chat failed" }
