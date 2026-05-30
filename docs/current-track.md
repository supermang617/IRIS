# Current Track

## Current checkpoint

HUD speech-plan gate.

Command:

cargo run -p iris-runtime -- hud-speech-plan-test "Iris, your voice sounds awesome."

## Why this is next

Before HUD Kokoro audio, Iris must prove that the exact text sent to speech is:

- checked
- role-repaired
- free of censor-marker asterisks
- speakable by policy

## Next after this passes

Choose the actual HUD speech boundary:

1. dev-only PowerShell wrapper around existing Kokoro scripts, or
2. Rust-native local TTS backend with explicitly approved dependencies.

Do not make the Rust runtime spawn shell/process commands.
