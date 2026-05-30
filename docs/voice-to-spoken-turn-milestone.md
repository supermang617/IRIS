# Voice To Spoken Turn Milestone

Status: active milestone verification.

## Purpose

This verifies the first full spoken Iris turn.

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_voice_to_spoken_turn.ps1

Dry run without playback:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_voice_to_spoken_turn.ps1 -NoPlay

## Verified path

Voice input
-> transcript
-> checked Iris response
-> role repair
-> natural speech rendering
-> VoiceOutputPlan
-> dev Kokoro speech boundary
-> audible Iris response

## Boundary

This is still a development speech boundary.

The Rust runtime does not spawn shell, PowerShell, Python, or external playback processes.
