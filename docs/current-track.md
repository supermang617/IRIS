# Current Track

Use this file to avoid drifting from the roadmap.

## Current fix

Kokoro speech text is now passed through a temporary UTF-8 text file.

This avoids PowerShell splitting long model responses into accidental parameters.

## Current milestone

Iris has reached:

- local model response
- response post-check
- Kokoro ONNX voice output
- default voice: af_heart
- default speed: 0.95
- explicit one-shot voice input helper
- typed prompt helper
- Panic Stop skeleton
- runtime voice-status
- runtime push-to-talk visible-state test

## Main live command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_iris_live_text_voice_session.ps1 -SkipBuild

## Do next

Rerun the live text and voice session.

If it passes, start the smallest Iris-owned HUD typed-input scaffold next.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, or wake word runtime before push-to-talk and visible voice state are stable.
