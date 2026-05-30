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
- iris-ui scaffold
- runtime ui-status
- clean milestone diagnostics script

## Current diagnostics command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\diagnose_iris_current_milestone.ps1

## Why this matters

The v0.1 plan requires audit tooling, visible UI status, explicit absence language, and repeatable safety checks before moving into heavier GUI, screen, OCR, memory, or wake-word work.

## Do next

Run the diagnostics command.

If diagnostics pass cleanly, the next architectural step is the smallest real HUD dependency decision.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, or wake word runtime before the HUD and visible voice-state path are stable.
