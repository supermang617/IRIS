param(
    [string] $Prompt = "In one sentence, say hello as Iris and confirm you are running locally.",
    [switch] $DryRun,
    [switch] $NoSpeak,
    [int] $Rate = 0,
    [int] $Volume = 90
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris text prompt + spoken response test ==="
Write-Host "Prompt: $Prompt"

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run only."
    Write-Host "This script will:"
    Write-Host "- send a text prompt through Iris ask-local"
    Write-Host "- capture stdout and stderr separately"
    Write-Host "- require Response post-check: PASS"
    Write-Host "- extract the checked model response"
    Write-Host "- print the text response"
    Write-Host "- speak the response using local Windows speech synthesis unless -NoSpeak is used"
    Write-Host "No model call was made."
    Write-Host "No speech was played."
    Write-Host "Result: PASS"
    return
}

$stdoutPath = [System.IO.Path]::GetTempFileName()
$stderrPath = [System.IO.Path]::GetTempFileName()

try {
    & cargo run -p iris-runtime -- ask-local "$Prompt" 1> $stdoutPath 2> $stderrPath
    $exitCode = $LASTEXITCODE

    $stdout = Get-Content -Raw -Path $stdoutPath
    $stderr = Get-Content -Raw -Path $stderrPath

    Write-Host ""
    Write-Host "=== Cargo/runtime stderr ==="
    if ([string]::IsNullOrWhiteSpace($stderr)) {
        Write-Host "(none)"
    } else {
        Write-Host $stderr
    }

    Write-Host ""
    Write-Host "=== Raw Iris output ==="
    Write-Host $stdout

    if ($exitCode -ne 0) {
        throw "Iris ask-local failed with exit code $exitCode"
    }

    if ($stdout -match "Response post-check: BLOCKED") {
        throw "Response was blocked. Refusing to speak model output."
    }

    if ($stdout -notmatch "Response post-check: PASS") {
        throw "Response post-check did not pass. Refusing to speak model output."
    }

    $lines = $stdout -split '\r?\n'
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

    if ($NoSpeak) {
        Write-Host ""
        Write-Host "Speech skipped because -NoSpeak was provided."
        Write-Host "Result: PASS"
        return
    }

    Write-Host ""
    Write-Host "=== Speaking Iris response locally ==="

    Add-Type -AssemblyName System.Speech

    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.Rate = $Rate
    $synth.Volume = $Volume

    try {
        $synth.Speak($responseText)
    } finally {
        $synth.Dispose()
    }

    Write-Host ""
    Write-Host "Result: PASS"
} finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $stdoutPath
    Remove-Item -Force -ErrorAction SilentlyContinue $stderrPath
}
