param(
    [string] $Prompt = "In one sentence, say hello as Iris and confirm you are running locally.",
    [string] $Voice = "af_heart",
    [double] $Speed = 1.0,
    [switch] $NoPlay,
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris text prompt + Kokoro spoken response test ==="

if ($DryRun) {
    Write-Host "Dry run only."
    Write-Host "This script will:"
    Write-Host "- call Iris ask-local through the compiled runtime"
    Write-Host "- require Response post-check: PASS"
    Write-Host "- extract the model response"
    Write-Host "- speak the checked response through Kokoro ONNX"
    Write-Host "No model call was made."
    Write-Host "No Kokoro generation was run."
    Write-Host "Result: PASS"
    return
}

$runtimeExe = Join-Path (Get-Location) "target\debug\iris-runtime.exe"

if (-not (Test-Path -Path $runtimeExe)) {
    cargo build -p iris-runtime
    if ($LASTEXITCODE -ne 0) { throw "cargo build -p iris-runtime failed" }
}

$outputLines = & $runtimeExe "ask-local" $Prompt
$exitCode = $LASTEXITCODE
$output = $outputLines -join [Environment]::NewLine

Write-Host ""
Write-Host "=== Raw Iris output ==="
Write-Host $output

if ($exitCode -ne 0) {
    throw "Iris ask-local failed with exit code $exitCode"
}

if ($output -match "Response post-check: BLOCKED") {
    throw "Response was blocked. Refusing to speak model output."
}

if ($output -notmatch "Response post-check: PASS") {
    throw "Response post-check did not pass. Refusing to speak model output."
}

$lines = $output -split '\r?\n'
$startIndex = -1

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq "Model response:") {
        $startIndex = $i + 1
        break
    }
}

if ($startIndex -lt 0) {
    throw "Could not find model response in Iris output."
}

$responseLines = New-Object System.Collections.Generic.List[string]

for ($i = $startIndex; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    if ($line.StartsWith("Backend:") -or $line.StartsWith("Result:")) {
        break
    }

    if (-not [string]::IsNullOrWhiteSpace($line)) {
        $responseLines.Add($line)
    }
}

$responseText = ($responseLines -join "`n").Trim()

if ([string]::IsNullOrWhiteSpace($responseText)) {
    throw "Model response was empty."
}

Write-Host ""
Write-Host "=== Iris text response ==="
Write-Host $responseText

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\speak_iris_kokoro.ps1" -Text $responseText -Voice $Voice -Speed $Speed -NoPlay:$NoPlay
if ($LASTEXITCODE -ne 0) { throw "Kokoro response speech failed" }

Write-Host ""
Write-Host "Result: PASS"
