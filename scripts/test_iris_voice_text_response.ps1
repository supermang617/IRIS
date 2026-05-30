param(
    [int] $TimeoutSeconds = 8,
    [switch] $NoSpeak,
    [switch] $DryRun,
    [string] $TtsBackend = "Kokoro",
    [string] $KokoroVoice = "af_heart",
    [double] $KokoroSpeed = 0.95,
    [int] $KokoroWakeSignalMs = 900,
    [double] $KokoroWakeSignalAmplitude = 0.004,
    [double] $KokoroWakeSignalHz = 220.0,
    [int] $KokoroLeadSilenceMs = 300,
    [int] $KokoroTailSilenceMs = 300,
    [string] $VoiceName = ""
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

if ($DryRun) {
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\listen_iris_local_speak.ps1" -DryRun
    if ($LASTEXITCODE -ne 0) { throw "voice text response dry-run failed" }
    return
}

$scriptArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\listen_iris_local_speak.ps1",
    "-TimeoutSeconds",
    "$TimeoutSeconds",
    "-TtsBackend",
    $TtsBackend,
    "-KokoroVoice",
    $KokoroVoice,
    "-KokoroSpeed",
    "$KokoroSpeed",
    "-KokoroWakeSignalMs",
    "$KokoroWakeSignalMs",
    "-KokoroWakeSignalAmplitude",
    "$KokoroWakeSignalAmplitude",
    "-KokoroWakeSignalHz",
    "$KokoroWakeSignalHz",
    "-KokoroLeadSilenceMs",
    "$KokoroLeadSilenceMs",
    "-KokoroTailSilenceMs",
    "$KokoroTailSilenceMs"
)

if (-not [string]::IsNullOrWhiteSpace($VoiceName)) {
    $scriptArgs += "-VoiceName"
    $scriptArgs += $VoiceName
}

if ($NoSpeak) {
    $scriptArgs += "-NoSpeak"
}

powershell @scriptArgs
if ($LASTEXITCODE -ne 0) {
    throw "voice text response test failed"
}
