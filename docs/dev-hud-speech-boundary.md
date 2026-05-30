# Dev HUD Speech Boundary

Status: active development-only speech test.

## Command

Dry run without playback:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_dev_hud_speech_boundary.ps1 -Prompt "Iris, your voice sounds awesome." -NoPlay

Playback test:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_dev_hud_speech_boundary.ps1 -Prompt "Iris, your voice sounds awesome."

## Boundary

This is a development script.

Rust runtime does not spawn PowerShell, Python, shell, or external processes.

Runtime only produces:

- checked response text
- VoiceOutputPlan

## Required speech text

Speech text must be:

- approved by response check
- repaired for Iris/user role accuracy
- free of censor-marker asterisks
- ready for Kokoro playback
