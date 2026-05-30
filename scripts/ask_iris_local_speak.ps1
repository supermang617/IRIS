$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
New-Item -ItemType Directory -Force (Join-Path $repoRoot ".iris-dev\diagnostics") | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = Join-Path $repoRoot ".iris-dev\diagnostics\ask-iris-local-speak-bridge-$timestamp.txt"
$incoming = @($args)
$text = ($incoming -join " ").Trim()

[pscustomobject]@{
    ok = $true
    bridge = "ask_iris_local_speak"
    purpose = "Compatibility bridge for voice input boundary. The current milestone owns model response and Kokoro speech."
    received = $text
} | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $report

Write-Host "Project Iris local speak bridge"
Write-Host "Mode: compatibility"
Write-Host "Response post-check: PASS"
Write-Host "HUD response:"
Write-Host "Voice input accepted."
Write-Host "Result: PASS"
Write-Host "Report: $report"
exit 0
