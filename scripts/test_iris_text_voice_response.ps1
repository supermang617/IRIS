param(
    [string] $Prompt = "In one sentence, say hello as Iris and confirm you are running locally.",
    [switch] $DryRun,
    [switch] $NoSpeak,
    [string] $TtsBackend = "Kokoro",
    [string] $KokoroVoice = "af_heart",
    [double] $KokoroSpeed = 0.95,
    [int] $KokoroWakeSignalMs = 900,
    [double] $KokoroWakeSignalAmplitude = 0.004,
    [int] $KokoroLeadSilenceMs = 300,
    [int] $KokoroTailSilenceMs = 300,
    [string] $VoiceName = "",
    [int] $Rate = 0,
    [int] $Volume = 90
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

$scriptArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\ask_iris_local_speak.ps1"
)

if ($DryRun) {
    $scriptArgs += "-DryRun"
} else {
    $scriptArgs += "-Prompt"
    $scriptArgs += $Prompt
    $scriptArgs += "-TtsBackend"
    $scriptArgs += $TtsBackend
    $scriptArgs += "-KokoroVoice"
    $scriptArgs += $KokoroVoice
    $scriptArgs += "-KokoroSpeed"
    $scriptArgs += "$KokoroSpeed"
    $scriptArgs += "-KokoroWakeSignalMs"
    $scriptArgs += "$KokoroWakeSignalMs"
    $scriptArgs += "-KokoroWakeSignalAmplitude"
    $scriptArgs += "$KokoroWakeSignalAmplitude"
    $scriptArgs += "-KokoroLeadSilenceMs"
    $scriptArgs += "$KokoroLeadSilenceMs"
    $scriptArgs += "-KokoroTailSilenceMs"
    $scriptArgs += "$KokoroTailSilenceMs"
    $scriptArgs += "-Rate"
    $scriptArgs += "$Rate"
    $scriptArgs += "-Volume"
    $scriptArgs += "$Volume"

    if (-not [string]::IsNullOrWhiteSpace($VoiceName)) {
        $scriptArgs += "-VoiceName"
        $scriptArgs += $VoiceName
    }

    if ($NoSpeak) {
        $scriptArgs += "-NoSpeak"
    }
}

powershell @scriptArgs
if ($LASTEXITCODE -ne 0) {
    throw "Iris text voice response test failed"
}
