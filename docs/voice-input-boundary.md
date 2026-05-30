# Voice Input Boundary

Status: active checkpoint.

## Purpose

This verifies that Iris can capture a spoken user prompt as transcript text before chaining it into the response and Kokoro speech path.

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_voice_input_boundary.ps1

## Test phrase

Iris, your voice sounds awesome.

## Next after this passes

Voice input
-> transcript
-> checked HUD response path
-> VoiceOutputPlan
-> Kokoro spoken answer
