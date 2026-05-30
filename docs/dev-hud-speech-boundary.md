# Dev HUD Speech Boundary

Status: active development-only speech test.

## Purpose

This verifies the safe path before wiring HUD speech deeper into the app.

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_dev_hud_speech_boundary.ps1 -Prompt "Iris, your voice sounds awesome."

## Boundary

This is a development script.

The Rust runtime does not spawn PowerShell, Python, shell, or external processes.

The runtime only creates checked response text and a VoiceOutputPlan.

## Required path

HUD typed prompt simulation
-> checked HUD response
-> ResponsePostChecker
-> VoiceOutputPlan
-> PowerShell dev boundary
-> existing Kokoro speak script

## Required speech text

Speech text must be:

- approved by response check
- repaired for Iris/user role accuracy
- free of censor-marker asterisks
- ready for Kokoro playback
