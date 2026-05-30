# Current Track

Use this file to avoid drifting from the roadmap.

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

## Main live test command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_iris_live_text_voice_session.ps1

## Faster live test command after baseline already passed

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_iris_live_text_voice_session.ps1 -SkipBuild

## Wake word requirement

Wake word is a required future feature.

Preferred wake phrase:

Iris

Do not implement wake word as default yet.

Correct order:

1. typed prompt
2. explicit one-shot voice
3. push-to-talk
4. visible listening state
5. optional local wake word while Iris is open

## Do next

Run the live text and voice session.

If it passes, start the smallest UI/HUD typed-input scaffold next, because the v0.1 plan requires Iris-owned typed input and visible status instead of only PowerShell helpers.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, or wake word runtime before push-to-talk and visible voice state are stable.
