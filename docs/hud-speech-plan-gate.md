# HUD Speech Plan Gate

Status: active pre-audio checkpoint.

## Command

cargo run -p iris-runtime -- hud-speech-plan-test "Iris, your voice sounds awesome."

## Purpose

Before the HUD speaks with Kokoro, Iris must prove that the exact text sent to speech is:

- checked by ResponsePostChecker
- role-repaired
- free of censor-marker asterisks
- speakable by voice policy

## Runtime boundary

This is a speech plan only.

The Rust runtime must not spawn shell, PowerShell, Python, or external processes to speak.
