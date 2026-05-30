# Kokoro Voice Milestone

Status: active milestone.

## Current default voice

Backend:

Kokoro ONNX

Voice:

af_heart

Speed:

0.95

Playback wake-up:

900 ms wake signal
300 ms lead silence
300 ms tail silence

## Main verification command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_kokoro_voice_milestone.ps1

## What this verifies

- cargo fmt
- cargo build
- cargo test
- xtask audit
- runtime self-check
- runtime voice-status
- Panic Stop test
- response post-check test
- direct Kokoro voice playback
- typed prompt to checked Kokoro spoken response

## Manual voice input command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_voice_text_response.ps1 -TimeoutSeconds 10

## Safety boundary

Kokoro TTS is output only.

This milestone does not add:

- always-listening voice
- wake word runtime
- mouse control
- keyboard control
- clipboard access
- shell execution inside Iris runtime
- browser automation
- plugins
- cloud TTS
