$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Installed Windows speech voices ==="

Add-Type -AssemblyName System.Speech

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer

try {
    $voices = $synth.GetInstalledVoices()

    if ($voices.Count -eq 0) {
        Write-Host "No installed Windows speech voices found."
        exit 0
    }

    foreach ($voice in $voices) {
        $info = $voice.VoiceInfo
        Write-Host ""
        Write-Host "Name: $($info.Name)"
        Write-Host "Gender: $($info.Gender)"
        Write-Host "Culture: $($info.Culture)"
        Write-Host "Age: $($info.Age)"
        Write-Host "Enabled: $($voice.Enabled)"
    }

    Write-Host ""
    Write-Host "Use a voice like this:"
    Write-Host 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_text_voice_response.ps1 -Prompt "hello iris" -VoiceName "VOICE NAME HERE"'
} finally {
    $synth.Dispose()
}
