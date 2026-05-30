# HUD Speech Plan Gate

Status: active pre-audio checkpoint.

## Purpose

Before the HUD speaks with Kokoro, Iris must prove that the text sent to speech is safe and correct.

## Current command

cargo run -p iris-runtime -- hud-speech-plan-test "Iris, your voice sounds awesome."

## What it verifies

- HUD typed prompt reaches the checked response path
- ResponsePostChecker approves the response before speech
- assistant output does not contain censor-marker asterisks
- Iris says "my voice" when referring to her own voice
- the speech path is a plan only
- Rust runtime does not spawn PowerShell, Python, shell, or external processes

## Architecture rule

Runtime may create a `VoiceOutputPlan`.

Runtime must not execute shell/process commands to speak.

Actual Kokoro playback must be wired through an approved local TTS boundary, not ad-hoc process spawning from the runtime.
