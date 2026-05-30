param(
    [string] $Prompt = "In one sentence, say hello as Iris and confirm you are running locally.",
    [switch] $DryRun,
    [switch] $NoSpeak,
    [string] $VoiceName = "",
    [int] $Rate = 0,
    [int] $Volume = 90
)

$ErrorActionPreference = "Stop"

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris text prompt + spoken response test ==="
Write-Host "Prompt: $Prompt"

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run only."
    Write-Host "This script will:"
    Write-Host "- call the compiled Iris runtime binary directly"
    Write-Host "- avoid parsing cargo run output"
    Write-Host "- require Response post-check: PASS"
    Write-Host "- extract the checked model response"
    Write-Host "- print the text response"
    Write-Host "- optionally select a Windows voice by name"
    Write-Host "- speak the checked response unless -NoSpeak is used"
    Write-Host "No model call was made."
    Write-Host "No speech was played."
    Write-Host "Result: PASS"
    return
}

$runtimeExe = Join-Path (Get-Location) "target\debug\iris-runtime.exe"

if (-not (Test-Path -Path $runtimeExe)) {
    Write-Host ""
    Write-Host "Runtime binary not found. Building iris-runtime first..."

    cargo build -p iris-runtime
    if ($LASTEXITCODE -ne 0) { throw "cargo build -p iris-runtime failed" }
}

if (-not (Test-Path -Path $runtimeExe)) {
    throw "Runtime binary still not found after build: $runtimeExe"
}

Write-Host ""
Write-Host "=== Running compiled Iris runtime ==="

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
    if (-not [string]::IsNullOrWhiteSpace($VoiceName)) {
        Write-Host "Requested voice: $VoiceName"
        try {
            $synth.SelectVoice($VoiceName)
        } catch {
            Write-Host ""
            Write-Host "Requested voice was not found. Installed voices:"
            $synth.GetInstalledVoices() | ForEach-Object {
                Write-Host "- $($_.VoiceInfo.Name) [$($_.VoiceInfo.Gender)]"
            }
            throw "Voice not found: $VoiceName"
        }
    }

    Write-Host "Speaking with voice: $($synth.Voice.Name)"
    $synth.Speak($responseText)
} finally {
    $synth.Dispose()
}

Write-Host ""
Write-Host "Result: PASS"
