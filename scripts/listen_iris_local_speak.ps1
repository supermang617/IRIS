param(
    [int] $TimeoutSeconds = 8,
    [switch] $DryRun,
    [switch] $NoSpeak,
    [int] $Rate = 0,
    [int] $Volume = 90
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris one-shot voice input + spoken response test ==="

if ($DryRun) {
    Write-Host "Dry run only."
    Write-Host "This script will:"
    Write-Host "- listen once through the default Windows microphone"
    Write-Host "- convert the spoken phrase to a transcript using local Windows speech recognition"
    Write-Host "- route the transcript through Iris ask-local"
    Write-Host "- require Response post-check: PASS"
    Write-Host "- print the model response"
    Write-Host "- speak the checked response using local Windows speech synthesis unless -NoSpeak is used"
    Write-Host "No microphone capture was started."
    Write-Host "No model call was made."
    Write-Host "No speech was played."
    Write-Host "Result: PASS"
    return
}

if ($TimeoutSeconds -lt 2) {
    throw "TimeoutSeconds must be at least 2."
}

Write-Host "Mode: explicit one-shot voice input"
Write-Host "Timeout seconds: $TimeoutSeconds"
Write-Host "Default microphone: Windows default audio input"
Write-Host ""
Write-Host "Speak after the listening message."

Add-Type -AssemblyName System.Speech

$recognizer = New-Object System.Speech.Recognition.SpeechRecognitionEngine

try {
    $grammar = New-Object System.Speech.Recognition.DictationGrammar
    $recognizer.LoadGrammar($grammar)
    $recognizer.SetInputToDefaultAudioDevice()

    Write-Host ""
    Write-Host "Listening now..."

    $result = $recognizer.Recognize([TimeSpan]::FromSeconds($TimeoutSeconds))

    if ($null -eq $result) {
        throw "No speech was recognized. Try again closer to the microphone."
    }

    $transcript = $result.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($transcript)) {
        throw "Recognized transcript was empty."
    }

    Write-Host ""
    Write-Host "=== Recognized transcript ==="
    Write-Host $transcript
} finally {
    $recognizer.Dispose()
}

Write-Host ""
Write-Host "=== Sending transcript to Iris ==="

$scriptArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\ask_iris_local_speak.ps1",
    "-Prompt",
    $transcript,
    "-Rate",
    "$Rate",
    "-Volume",
    "$Volume"
)

if ($NoSpeak) {
    $scriptArgs += "-NoSpeak"
}

powershell @scriptArgs
if ($LASTEXITCODE -ne 0) {
    throw "Iris voice input response test failed"
}

Write-Host ""
Write-Host "Result: PASS"
