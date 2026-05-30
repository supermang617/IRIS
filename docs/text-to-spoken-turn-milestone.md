# Text To Spoken Turn Milestone

Status: active milestone verification.

## Purpose

This verifies the first working audible Iris conversation turn from typed input.

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_text_to_spoken_turn.ps1

Dry run without playback:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_text_to_spoken_turn.ps1 -NoPlay

## Verified path

Typed prompt
-> HUD checked response path
-> role repair
-> profanity marker normalization
-> ResponsePostChecker
-> VoiceOutputPlan
-> dev Kokoro speech boundary
-> audible Iris voice

## Boundary

This is still a development speech boundary.

The Rust runtime does not spawn shell, PowerShell, Python, or external playback processes.

## Next milestone after this

Voice input
-> transcript
-> same checked response path
-> Kokoro spoken answer
