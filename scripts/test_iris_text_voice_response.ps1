$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

$prompt = if ($args.Count -gt 0) {
    ($args -join " ")
} else {
    "In one sentence, say hello as Iris and confirm you are running locally."
}

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\ask_iris_local_speak.ps1" -Prompt $prompt

if ($LASTEXITCODE -ne 0) {
    throw "Iris text voice response test failed"
}
